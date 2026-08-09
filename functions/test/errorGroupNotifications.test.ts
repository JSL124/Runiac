import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type DocumentSnapshot, type Firestore } from "firebase-admin/firestore";
import { createErrorGroupNotificationHandlers } from "../src/errors/errorGroupNotifications.js";

describe(
  "errorGroupNotifications handler",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;
    let handlers: ReturnType<typeof createErrorGroupNotificationHandlers>;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: "demo-runiac-moderation" });
      }
      firestore = getFirestore();
      handlers = createErrorGroupNotificationHandlers({ firestore });
    });

    beforeEach(async () => {
      await clearCollections(firestore, ["adminNotifications"]);
      await firestore.doc("config/automation").delete();
    });

    it("notifies on create-at-critical with no before snapshot, when the minimum is critical", async () => {
      await handlers.onWritten("fp-create-critical", undefined, snap(true, {
        title: "Boom",
        errorType: "TypeError",
        severity: "critical",
      }));

      const doc = await firestore.doc("adminNotifications/error_fp-create-critical").get();
      assert.equal(doc.exists, true);
      assert.equal(doc.get("kind"), "error-group");
      assert.equal(doc.get("severity"), "critical");
      assert.equal(doc.get("title"), "Error group reached critical");
      assert.equal(doc.get("href"), "/admin/errors");
      assert.equal(doc.get("status"), "unread");
      assert.match(String(doc.get("detail")), /fp-create-critical/);
    });

    it("notifies once on a low → critical transition", async () => {
      await handlers.onWritten(
        "fp-low-to-critical",
        snap(true, { severity: "low" }),
        snap(true, { severity: "critical" }),
      );

      const doc = await firestore.doc("adminNotifications/error_fp-low-to-critical").get();
      assert.equal(doc.exists, true);
      assert.equal(doc.get("severity"), "critical");
    });

    it("does not duplicate the notification on a critical → critical re-ingest", async () => {
      await handlers.onWritten(
        "fp-critical-again",
        snap(true, { severity: "low" }),
        snap(true, { severity: "critical" }),
      );
      await handlers.onWritten(
        "fp-critical-again",
        snap(true, { severity: "critical" }),
        snap(true, { severity: "critical" }),
      );

      const snapshot = await firestore
        .collection("adminNotifications")
        .where("kind", "==", "error-group")
        .get();
      assert.equal(snapshot.size, 1);
    });

    it("does not notify at high severity when the minimum is critical", async () => {
      await handlers.onWritten("fp-high-only", undefined, snap(true, { severity: "high" }));

      const doc = await firestore.doc("adminNotifications/error_fp-high-only").get();
      assert.equal(doc.exists, false);
    });

    it("notifies on a medium → high transition when the minimum is high", async () => {
      await firestore.doc("config/automation").set({
        notifications: { notifyErrorGroups: true, minimumErrorSeverity: "high" },
      });

      await handlers.onWritten(
        "fp-medium-to-high",
        snap(true, { severity: "medium" }),
        snap(true, { severity: "high" }),
      );

      const doc = await firestore.doc("adminNotifications/error_fp-medium-to-high").get();
      assert.equal(doc.exists, true);
      assert.equal(doc.get("severity"), "high");
    });

    it("writes nothing when notifyErrorGroups is disabled", async () => {
      await firestore.doc("config/automation").set({
        notifications: { notifyErrorGroups: false, minimumErrorSeverity: "critical" },
      });

      await handlers.onWritten("fp-disabled", undefined, snap(true, { severity: "critical" }));

      const doc = await firestore.doc("adminNotifications/error_fp-disabled").get();
      assert.equal(doc.exists, false);
    });

    it("never throws even when the document data is garbage", async () => {
      await assert.doesNotReject(
        handlers.onWritten(
          "fp-garbage",
          snap(true, { severity: 12345 } as unknown as Record<string, unknown>),
          snap(true, { severity: { nested: true } } as unknown as Record<string, unknown>),
        ),
      );

      await assert.doesNotReject(handlers.onWritten("fp-no-after", snap(true, {}), undefined));

      const missingAfter = snap(false, undefined) as unknown as DocumentSnapshot;
      await assert.doesNotReject(handlers.onWritten("fp-deleted", snap(true, { severity: "critical" }), missingAfter));
    });
  },
);

function snap(exists: boolean, data: Record<string, unknown> | undefined): DocumentSnapshot {
  return {
    exists,
    data: () => data,
  } as unknown as DocumentSnapshot;
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
