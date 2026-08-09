import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import { assertAccountNotSuspended, isSuspendedAccount } from "../src/security/accountStatus.js";

describe("isSuspendedAccount", () => {
  it("blocks the two canonical blocking statuses the admin console writes", () => {
    assert.equal(isSuspendedAccount({ accountStatus: "suspended" }), true);
    assert.equal(isSuspendedAccount({ accountStatus: "banned" }), true);
  });

  it("treats a missing users/{uid} document as NOT suspended", () => {
    assert.equal(isSuspendedAccount(undefined), false);
  });

  it("treats a document with no accountStatus field as NOT suspended, preserving existing document behaviour", () => {
    assert.equal(isSuspendedAccount({}), false);
    assert.equal(isSuspendedAccount({ subscriptionStatus: "premium", userRole: "Basic User" }), false);
  });

  it("treats any other/unrecognised accountStatus value as NOT suspended", () => {
    assert.equal(isSuspendedAccount({ accountStatus: "active" }), false);
    assert.equal(isSuspendedAccount({ accountStatus: "" }), false);
    assert.equal(isSuspendedAccount({ accountStatus: 42 }), false);
  });
});

describe("assertAccountNotSuspended", () => {
  it("throws permission-denied for a suspended or banned account", () => {
    assert.throws(
      () => assertAccountNotSuspended({ accountStatus: "suspended" }),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );
    assert.throws(
      () => assertAccountNotSuspended({ accountStatus: "banned" }),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );
  });

  it("does not throw for an unsuspended account, a missing document, or a document with no accountStatus field", () => {
    assert.doesNotThrow(() => assertAccountNotSuspended({ accountStatus: "active" }));
    assert.doesNotThrow(() => assertAccountNotSuspended(undefined));
    assert.doesNotThrow(() => assertAccountNotSuspended({}));
  });
});
