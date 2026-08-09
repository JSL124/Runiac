import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { createReportAutomationHandlers } from "../src/moderation/reportAutomation.js";

describe(
  "report automation handler",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;
    let handlers: ReturnType<typeof createReportAutomationHandlers>;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: "demo-runiac-moderation" });
      }
      firestore = getFirestore();
      handlers = createReportAutomationHandlers({ firestore });
    });

    beforeEach(async () => {
      await clearCollections(firestore, [
        "reports",
        "moderationCommands",
        "adminNotifications",
        "adminAuditLogs",
        "config",
      ]);
    });

    it("does not create an auto-hide command below the report threshold", async () => {
      await setAutomationConfig(firestore, { autoHide: { enabled: true, reportThreshold: 3 } });

      await seedReportAndHandle(firestore, handlers, "post-below-threshold", "report-1");
      await seedReportAndHandle(firestore, handlers, "post-below-threshold", "report-2");

      const commands = await firestore.collection("moderationCommands").get();
      assert.equal(commands.size, 0);

      const auditLogs = await firestore.collection("adminAuditLogs").get();
      assert.equal(auditLogs.size, 0);
    });

    it("creates exactly one auto-hide command and one audit entry once the threshold is reached", async () => {
      await setAutomationConfig(firestore, { autoHide: { enabled: true, reportThreshold: 3 } });

      await seedReportAndHandle(firestore, handlers, "post-at-threshold", "report-1");
      await seedReportAndHandle(firestore, handlers, "post-at-threshold", "report-2");
      await seedReportAndHandle(firestore, handlers, "post-at-threshold", "report-3");

      const commandRef = firestore.doc("moderationCommands/auto_removeFeedPost_post-at-threshold");
      const command = await commandRef.get();
      assert.equal(command.exists, true);
      assert.equal(command.get("kind"), "removeFeedPost");
      assert.equal(command.get("postId"), "post-at-threshold");
      assert.equal(command.get("requestedBy"), "system:report-auto-hide");
      assert.equal(command.get("status"), "pending");
      assert.equal(command.get("reportCount"), 3);

      const commands = await firestore.collection("moderationCommands").get();
      assert.equal(commands.size, 1);

      const auditLogs = await firestore
        .collection("adminAuditLogs")
        .where("action", "==", "moderation.report-auto-hide.request")
        .get();
      assert.equal(auditLogs.size, 1);
      const auditLog = auditLogs.docs[0]?.data();
      assert.equal(auditLog?.["actor"], "system");
      assert.equal(auditLog?.["targetType"], "moderation-command");
      assert.equal(auditLog?.["targetId"], "auto_removeFeedPost_post-at-threshold");
    });

    it("stays idempotent on replay of the triggering event", async () => {
      await setAutomationConfig(firestore, { autoHide: { enabled: true, reportThreshold: 3 } });

      await seedReportAndHandle(firestore, handlers, "post-replay", "report-1");
      await seedReportAndHandle(firestore, handlers, "post-replay", "report-2");
      const thirdReport = await seedReport(firestore, "post-replay", "report-3");

      // First delivery of the 3rd report's create event.
      await handlers.onReportCreated(thirdReport.id, thirdReport.data);
      // Replay of the same event (e.g. a redelivered Cloud Functions trigger).
      await handlers.onReportCreated(thirdReport.id, thirdReport.data);

      const commands = await firestore.collection("moderationCommands").get();
      assert.equal(commands.size, 1);

      const auditLogs = await firestore
        .collection("adminAuditLogs")
        .where("action", "==", "moderation.report-auto-hide.request")
        .get();
      assert.equal(auditLogs.size, 1);
    });

    it("does not create a command when auto-hide is disabled", async () => {
      await setAutomationConfig(firestore, { autoHide: { enabled: false, reportThreshold: 3 } });

      await seedReportAndHandle(firestore, handlers, "post-disabled", "report-1");
      await seedReportAndHandle(firestore, handlers, "post-disabled", "report-2");
      await seedReportAndHandle(firestore, handlers, "post-disabled", "report-3");

      // Assert on the deterministic command id this flow would create rather
      // than a collection-wide count: the real `reportCreated` and
      // `moderationCommandCreated` triggers also run in this shared emulator,
      // and late re-delivered executions from the sibling test files can
      // upsert unrelated status-only command docs after beforeEach clears
      // the collection.
      const command = await firestore
        .doc("moderationCommands/auto_removeFeedPost_post-disabled")
        .get();
      assert.equal(command.exists, false);
    });

    it("ignores reports whose targetType is not feedPost", async () => {
      await setAutomationConfig(firestore, { autoHide: { enabled: true, reportThreshold: 3 } });

      await seedReportAndHandle(firestore, handlers, "user-abuser", "report-1", "user");
      await seedReportAndHandle(firestore, handlers, "user-abuser", "report-2", "user");
      await seedReportAndHandle(firestore, handlers, "user-abuser", "report-3", "user");

      // Deterministic-id assertion for the same cross-file emulator
      // re-delivery reason as the auto-hide-disabled test above.
      const command = await firestore
        .doc("moderationCommands/auto_removeFeedPost_user-abuser")
        .get();
      assert.equal(command.exists, false);
    });

    it("writes exactly one admin notification per report when notifications are enabled, across replay", async () => {
      await setAutomationConfig(firestore, {
        autoHide: { enabled: false, reportThreshold: 3 },
        notifications: { notifyNewReports: true },
      });

      const report = await seedReport(firestore, "post-notify", "report-notify-1");
      await handlers.onReportCreated(report.id, report.data);
      await handlers.onReportCreated(report.id, report.data);

      const notificationRef = firestore.doc(`adminNotifications/report_${report.id}`);
      const notification = await notificationRef.get();
      assert.equal(notification.exists, true);
      assert.equal(notification.get("kind"), "new-report");
      assert.equal(notification.get("status"), "unread");

      const notifications = await firestore.collection("adminNotifications").get();
      assert.equal(notifications.size, 1);
    });

    it("does not write an admin notification when notifications are disabled", async () => {
      await setAutomationConfig(firestore, {
        autoHide: { enabled: false, reportThreshold: 3 },
        notifications: { notifyNewReports: false },
      });

      const report = await seedReport(firestore, "post-no-notify", "report-no-notify-1");
      await handlers.onReportCreated(report.id, report.data);

      const notifications = await firestore.collection("adminNotifications").get();
      assert.equal(notifications.size, 0);
    });
  },
);

async function setAutomationConfig(
  firestore: Firestore,
  overrides: {
    readonly autoHide?: { readonly enabled: boolean; readonly reportThreshold: number };
    readonly notifications?: { readonly notifyNewReports: boolean };
  },
): Promise<void> {
  await firestore.doc("config/automation").set(overrides, { merge: true });
}

async function seedReport(
  firestore: Firestore,
  targetId: string,
  reportId: string,
  targetType = "feedPost",
): Promise<{ readonly id: string; readonly data: Record<string, unknown> }> {
  const data = {
    reporterUid: `reporter-of-${reportId}`,
    targetType,
    targetId,
    reason: "feed_inappropriate",
    description: "",
  };
  await firestore.collection("reports").doc(reportId).set(data);
  return { id: reportId, data };
}

async function seedReportAndHandle(
  firestore: Firestore,
  handlers: ReturnType<typeof createReportAutomationHandlers>,
  targetId: string,
  reportId: string,
  targetType = "feedPost",
): Promise<void> {
  const report = await seedReport(firestore, targetId, reportId, targetType);
  await handlers.onReportCreated(report.id, report.data);
}

async function clearCollections(
  firestore: Firestore,
  collectionNames: readonly string[],
): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    if (snapshot.empty) {
      continue;
    }
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}
