import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Firestore } from "firebase-admin/firestore";
import { scheduledAutomationEnabled } from "../src/config/automationGate.js";

type FakeSnapshot = {
  readonly exists: boolean;
  data(): unknown;
};

function fakeDb(docPath: string, snapshot: FakeSnapshot): Firestore {
  return {
    doc(path: string) {
      return {
        async get() {
          if (path !== docPath) {
            return { exists: false, data: () => undefined };
          }

          return snapshot;
        },
      };
    },
  } as unknown as Firestore;
}

function rejectingDb(docPath: string): Firestore {
  return {
    doc(path: string) {
      return {
        async get() {
          if (path !== docPath) {
            return { exists: false, data: () => undefined };
          }

          throw new Error("simulated firestore read failure");
        },
      };
    },
  } as unknown as Firestore;
}

describe("scheduledAutomationEnabled", () => {
  it("returns false when the flag is disabled in config/automation", async () => {
    const db = fakeDb("config/automation", {
      exists: true,
      data: () => ({ scheduled: { subscriptionExpirySweep: false } }),
    });

    const enabled = await scheduledAutomationEnabled(db, "subscriptionExpirySweep", "testFunction");
    assert.equal(enabled, false);
  });

  it("returns true when the flag is enabled in config/automation", async () => {
    const db = fakeDb("config/automation", {
      exists: true,
      data: () => ({ scheduled: { subscriptionExpirySweep: true } }),
    });

    const enabled = await scheduledAutomationEnabled(db, "subscriptionExpirySweep", "testFunction");
    assert.equal(enabled, true);
  });

  it("fails open to true when config/automation does not exist", async () => {
    const db = fakeDb("config/automation", { exists: false, data: () => undefined });

    const enabled = await scheduledAutomationEnabled(db, "leaderboardSnapshotRefresh", "testFunction");
    assert.equal(enabled, true);
  });

  it("fails open to true when config/automation is malformed", async () => {
    const db = fakeDb("config/automation", {
      exists: true,
      data: () => ({ scheduled: { pushNotificationDispatch: "false" } }),
    });

    const enabled = await scheduledAutomationEnabled(db, "pushNotificationDispatch", "testFunction");
    assert.equal(enabled, true);
  });

  it("fails open to true when the read rejects", async () => {
    const db = rejectingDb("config/automation");

    const enabled = await scheduledAutomationEnabled(db, "pushNotificationDispatch", "testFunction");
    assert.equal(enabled, true);
  });
});
