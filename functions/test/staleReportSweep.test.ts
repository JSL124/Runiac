import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";
import { escalateStaleReportsNow } from "../src/moderation/staleReportSweep.js";

const DAY_MS = 24 * 60 * 60 * 1000;

describe(
  "escalateStaleReportsNow",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: "demo-runiac-moderation" });
      }
      firestore = getFirestore();
    });

    beforeEach(async () => {
      await clearCollections(firestore, ["reports", "adminNotifications", "adminAuditLogs"]);
      await firestore.doc("config/automation").delete();
    });

    it("escalates a pending report older than pendingDays with one notification and one audit entry", async () => {
      const nowMs = Date.now();
      await seedReport(firestore, "report-stale", {
        createdAt: Timestamp.fromMillis(nowMs - 8 * DAY_MS),
      });

      const result = await escalateStaleReportsNow(firestore, nowMs);
      assert.equal(result.escalated, 1);

      const dayKey = new Date(nowMs + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const notification = await firestore.doc(`adminNotifications/staleReports_${dayKey}`).get();
      assert.equal(notification.exists, true);
      assert.equal(notification.get("kind"), "stale-reports");
      assert.equal(notification.get("severity"), "medium");
      assert.equal(notification.get("title"), "Reports pending review");
      assert.equal(
        notification.get("detail"),
        "1 report(s) have been pending longer than 7 day(s).",
      );
      assert.equal(notification.get("href"), "/admin/exceptions");
      assert.equal(notification.get("status"), "unread");
      assert.ok(notification.get("createdAt") !== undefined);

      const auditSnapshot = await firestore
        .collection("adminAuditLogs")
        .where("action", "==", "moderation.stale-reports.escalate")
        .get();
      assert.equal(auditSnapshot.size, 1);
      const audit = auditSnapshot.docs[0]?.data();
      assert.equal(audit?.["actor"], "system");
      assert.equal(audit?.["targetType"], "adminNotification");
      assert.equal(audit?.["targetId"], `staleReports_${dayKey}`);
    });

    it("does not duplicate the notification or audit entry on a same-day re-run", async () => {
      const nowMs = Date.now();
      await seedReport(firestore, "report-stale", {
        createdAt: Timestamp.fromMillis(nowMs - 8 * DAY_MS),
      });

      const first = await escalateStaleReportsNow(firestore, nowMs);
      assert.equal(first.escalated, 1);

      // A few seconds later, same Singapore day.
      const second = await escalateStaleReportsNow(firestore, nowMs + 5_000);
      assert.equal(second.escalated, 1);

      const notificationsSnapshot = await firestore.collection("adminNotifications").get();
      assert.equal(notificationsSnapshot.size, 1);

      const auditSnapshot = await firestore
        .collection("adminAuditLogs")
        .where("action", "==", "moderation.stale-reports.escalate")
        .get();
      assert.equal(auditSnapshot.size, 1);
    });

    it("does not count a resolved report, a dismissed report, or a report younger than pendingDays", async () => {
      const nowMs = Date.now();
      await seedReport(firestore, "report-resolved", {
        createdAt: Timestamp.fromMillis(nowMs - 8 * DAY_MS),
        resolutionStatus: "resolved",
      });
      await seedReport(firestore, "report-dismissed", {
        createdAt: Timestamp.fromMillis(nowMs - 8 * DAY_MS),
        resolutionStatus: "dismissed",
      });
      await seedReport(firestore, "report-young", {
        createdAt: Timestamp.fromMillis(nowMs - 1 * DAY_MS),
      });

      const result = await escalateStaleReportsNow(firestore, nowMs);
      assert.equal(result.escalated, 0);

      const notificationsSnapshot = await firestore.collection("adminNotifications").get();
      assert.equal(notificationsSnapshot.empty, true);
    });

    it("counts a report still in 'reviewing' past pendingDays as unresolved and stale", async () => {
      // "reviewing" is a non-terminal console status (website
      // ReportResolutionStatus = "pending" | "reviewing" | "resolved" |
      // "dismissed") — only "resolved"/"dismissed" stop the clock.
      const nowMs = Date.now();
      await seedReport(firestore, "report-reviewing", {
        createdAt: Timestamp.fromMillis(nowMs - 8 * DAY_MS),
        resolutionStatus: "reviewing",
      });

      const result = await escalateStaleReportsNow(firestore, nowMs);
      assert.equal(result.escalated, 1);

      const dayKey = new Date(nowMs + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const notification = await firestore.doc(`adminNotifications/staleReports_${dayKey}`).get();
      assert.equal(notification.exists, true);
    });

    it("makes no writes when staleReportEscalation is disabled", async () => {
      const nowMs = Date.now();
      await firestore.doc("config/automation").set({
        staleReportEscalation: { enabled: false, pendingDays: 7 },
      });
      await seedReport(firestore, "report-stale", {
        createdAt: Timestamp.fromMillis(nowMs - 30 * DAY_MS),
      });

      const result = await escalateStaleReportsNow(firestore, nowMs);
      assert.equal(result.escalated, 0);

      const notificationsSnapshot = await firestore.collection("adminNotifications").get();
      assert.equal(notificationsSnapshot.empty, true);
      const auditSnapshot = await firestore.collection("adminAuditLogs").get();
      assert.equal(auditSnapshot.empty, true);
    });

    it("skips a report with an unparseable createdAt instead of throwing", async () => {
      const nowMs = Date.now();
      await seedReport(firestore, "report-garbage-createdat", {
        createdAt: { nested: "not a timestamp" },
      });

      const result = await escalateStaleReportsNow(firestore, nowMs);
      assert.equal(result.escalated, 0);

      const notificationsSnapshot = await firestore.collection("adminNotifications").get();
      assert.equal(notificationsSnapshot.empty, true);
    });
  },
);

async function seedReport(
  firestore: Firestore,
  reportId: string,
  fields: Record<string, unknown>,
): Promise<void> {
  await firestore.doc(`reports/${reportId}`).set({
    reporterUid: "reporter-a",
    targetType: "user",
    targetId: "target-a",
    reason: "harassment",
    description: "",
    ...fields,
  });
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
