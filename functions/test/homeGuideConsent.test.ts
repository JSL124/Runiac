import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  HOME_GUIDE_DISCLOSURE_VERSION,
  createHomeGuideConsentHandler,
  requireCurrentHomeGuideConsent,
} from "../src/agent/homeGuideConsent.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "consent-runner";
let firestore: Firestore;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  await firestore.doc(`homeGuideConsents/${USER_UID}`).delete();
});

describe(
  "home guide consent",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    it("requires authentication for reads and updates", async () => {
      const handler = createHomeGuideConsentHandler({
        firestore: () => firestore,
        now: () => new Date("2026-07-15T00:00:00.000Z"),
      });

      await assert.rejects(
        () => handler({ data: { action: "read" } }),
        (error: unknown) =>
          error instanceof HttpsError && error.code === "unauthenticated",
      );
    });

    it("stores only the exact current versioned consent schema", async () => {
      const handler = createHomeGuideConsentHandler({
        firestore: () => firestore,
        now: () => new Date("2026-07-15T00:00:00.000Z"),
      });

      const result = await handler({
        auth: { uid: USER_UID },
        data: {
          action: "update",
          granted: true,
          disclosureVersion: HOME_GUIDE_DISCLOSURE_VERSION,
        },
      });
      const document = await firestore.doc(`homeGuideConsents/${USER_UID}`).get();

      assert.deepEqual(result, {
        granted: true,
        disclosureVersion: HOME_GUIDE_DISCLOSURE_VERSION,
      });
      assert.deepEqual(Object.keys(document.data() ?? {}).sort(), [
        "disclosureVersion",
        "granted",
        "grantedAt",
        "ownerUid",
        "revokedAt",
        "schemaVersion",
        "updatedAt",
      ]);
      assert.equal(document.get("ownerUid"), USER_UID);
      assert.equal(document.get("schemaVersion"), 1);
      assert.equal(document.get("granted"), true);
      assert.equal(document.get("revokedAt"), null);
    });

    it("fails closed when consent is absent, revoked, or stale", async () => {
      await assert.rejects(
        () => requireCurrentHomeGuideConsent(firestore, USER_UID),
        (error: unknown) =>
          error instanceof HttpsError && error.code === "failed-precondition",
      );

      await firestore.doc(`homeGuideConsents/${USER_UID}`).set({
        ownerUid: USER_UID,
        schemaVersion: 1,
        disclosureVersion: HOME_GUIDE_DISCLOSURE_VERSION,
        granted: false,
      });
      await assert.rejects(
        () => requireCurrentHomeGuideConsent(firestore, USER_UID),
        (error: unknown) =>
          error instanceof HttpsError && error.code === "failed-precondition",
      );

      await firestore.doc(`homeGuideConsents/${USER_UID}`).set({
        ownerUid: USER_UID,
        schemaVersion: 1,
        disclosureVersion: 0,
        granted: true,
      });
      await assert.rejects(
        () => requireCurrentHomeGuideConsent(firestore, USER_UID),
        (error: unknown) =>
          error instanceof HttpsError && error.code === "failed-precondition",
      );
    });
  },
);
