import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import {
  assertShareRouteToFeedEntitlement,
  SHARE_ROUTE_TO_FEED_PREMIUM_REQUIRED_REASON,
} from "../src/feed/publish/entitlement.js";
import type { FeatureAccessConfig } from "../src/config/configLoader.js";

// A small Firestore Timestamp stand-in: isPremiumSubscription only calls
// `.toMillis()` on subscriptionExpiresAt.
function expiresAt(ms: number): { toMillis: () => number } {
  return { toMillis: () => ms };
}

function featureAccess(shareRouteTier: "basic" | "premium"): FeatureAccessConfig {
  return {
    features: {
      shareRouteToFeed: { minimumTier: shareRouteTier, enabled: true },
    },
    version: 1,
  };
}

const NOW_MS = 1_700_000_000_000;

// Captures the HttpsError thrown by the gate, or returns undefined when the
// gate allowed the call through.
function entitlementError(
  userData: Record<string, unknown> | undefined,
  config: FeatureAccessConfig,
): HttpsError | undefined {
  try {
    assertShareRouteToFeedEntitlement(userData, config, NOW_MS);
    return undefined;
  } catch (error) {
    assert.ok(error instanceof HttpsError, `expected HttpsError, got ${String(error)}`);
    return error;
  }
}

describe("assertShareRouteToFeedEntitlement", () => {
  describe("when shareRouteToFeed requires premium", () => {
    const premiumConfig = featureAccess("premium");

    it("rejects a Basic user with permission-denied and the premium reason", () => {
      const error = entitlementError({ subscriptionStatus: "basic" }, premiumConfig);
      assert.ok(error, "a Basic user must be rejected");
      assert.equal(error.code, "permission-denied");
      assert.deepEqual(error.details, { reason: SHARE_ROUTE_TO_FEED_PREMIUM_REQUIRED_REASON });
    });

    it("rejects a user with no subscription field", () => {
      const error = entitlementError({}, premiumConfig);
      assert.ok(error);
      assert.equal(error.code, "permission-denied");
    });

    it("rejects when the user document is absent", () => {
      const error = entitlementError(undefined, premiumConfig);
      assert.ok(error);
      assert.equal(error.code, "permission-denied");
    });

    it("allows an active Premium user", () => {
      assert.equal(entitlementError({ subscriptionStatus: "premium" }, premiumConfig), undefined);
    });

    it("allows the capitalised Premium value", () => {
      assert.equal(entitlementError({ subscriptionStatus: "Premium" }, premiumConfig), undefined);
    });

    it("allows a Premium user whose subscription has not yet expired", () => {
      const userData = { subscriptionStatus: "premium", subscriptionExpiresAt: expiresAt(NOW_MS + 1) };
      assert.equal(entitlementError(userData, premiumConfig), undefined);
    });

    it("rejects a Premium user whose subscription has lapsed", () => {
      const userData = { subscriptionStatus: "premium", subscriptionExpiresAt: expiresAt(NOW_MS - 1) };
      const error = entitlementError(userData, premiumConfig);
      assert.ok(error, "a lapsed Premium subscription must be rejected");
      assert.equal(error.code, "permission-denied");
    });
  });

  describe("when shareRouteToFeed is basic (historical default)", () => {
    const basicConfig = featureAccess("basic");

    it("allows a Basic user (no premium required)", () => {
      assert.equal(entitlementError({ subscriptionStatus: "basic" }, basicConfig), undefined);
    });

    it("allows a Premium user", () => {
      assert.equal(entitlementError({ subscriptionStatus: "premium" }, basicConfig), undefined);
    });
  });

  it("allows everyone when the shareRouteToFeed entry is absent", () => {
    const emptyConfig: FeatureAccessConfig = { features: {}, version: 1 };
    assert.equal(entitlementError({ subscriptionStatus: "basic" }, emptyConfig), undefined);
  });
});
