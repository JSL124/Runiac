import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import {
  assertFeatureEntitlement,
  FEATURE_PREMIUM_REQUIRED_REASON,
  isPremiumGatedFeature,
} from "../src/config/featureEntitlement.js";
import { DEFAULT_FEATURE_ACCESS_CONFIG, type FeatureAccessConfig } from "../src/config/configLoader.js";
import { ACTIVITY_FEEDBACK_FEATURE_KEY } from "../src/agent/activityFeedbackAgentHandler.js";
import { AI_HOME_COACH_FEATURE_KEY } from "../src/agent/homeGuideAgentHandler.js";
import { SHARE_ROUTE_TO_FEED_FEATURE_KEY } from "../src/feed/publish/entitlement.js";

const NOW_MS = 1_700_000_000_000;

function config(
  entries: Record<string, { minimumTier: "basic" | "premium"; enabled: boolean }>,
): FeatureAccessConfig {
  return { features: entries, version: 1 };
}

// Captures the HttpsError thrown by the gate, or undefined when it allowed
// the call through.
function entitlementError(input: {
  featureKey: string;
  userData: Record<string, unknown> | undefined;
  featureAccess: FeatureAccessConfig;
}): HttpsError | undefined {
  try {
    assertFeatureEntitlement({ ...input, nowMs: NOW_MS, message: "Premium required." });
    return undefined;
  } catch (error) {
    assert.ok(error instanceof HttpsError, `expected HttpsError, got ${String(error)}`);
    return error;
  }
}

describe("isPremiumGatedFeature", () => {
  it("gates a feature the admin set to premium", () => {
    const featureAccess = config({ shareCards: { minimumTier: "premium", enabled: true } });
    assert.equal(isPremiumGatedFeature(featureAccess, "shareCards"), true);
  });

  it("does not gate a feature the admin set to basic", () => {
    const featureAccess = config({ shareCards: { minimumTier: "basic", enabled: true } });
    assert.equal(isPremiumGatedFeature(featureAccess, "shareCards"), false);
  });

  it("does not gate a feature that is absent from the catalog", () => {
    assert.equal(isPremiumGatedFeature(config({}), "somethingNewerThanThisDeployment"), false);
  });

  it("treats a disabled premium entry as ungated so the client and server agree", () => {
    // `enabled` means "this tier rule is active", not "this feature exists" —
    // the app's FeatureAccessReadModel drops disabled entries from its premium
    // list, so the server must not keep denying what the client lets through.
    const featureAccess = config({ shareCards: { minimumTier: "premium", enabled: false } });
    assert.equal(isPremiumGatedFeature(featureAccess, "shareCards"), false);
  });
});

describe("assertFeatureEntitlement", () => {
  const gated = config({ shareCards: { minimumTier: "premium", enabled: true } });

  it("rejects a Basic runner with permission-denied and the shared reason code", () => {
    const error = entitlementError({
      featureKey: "shareCards",
      userData: { subscriptionStatus: "basic" },
      featureAccess: gated,
    });
    assert.ok(error, "a Basic runner must be rejected");
    assert.equal(error.code, "permission-denied");
    assert.deepEqual(error.details, { reason: FEATURE_PREMIUM_REQUIRED_REASON });
  });

  it("rejects when the user document is absent", () => {
    const error = entitlementError({ featureKey: "shareCards", userData: undefined, featureAccess: gated });
    assert.ok(error);
    assert.equal(error.code, "permission-denied");
  });

  it("allows an active Premium runner", () => {
    const error = entitlementError({
      featureKey: "shareCards",
      userData: { subscriptionStatus: "premium" },
      featureAccess: gated,
    });
    assert.equal(error, undefined);
  });

  it("rejects a Premium runner whose subscription has lapsed", () => {
    const error = entitlementError({
      featureKey: "shareCards",
      userData: {
        subscriptionStatus: "premium",
        subscriptionExpiresAt: { toMillis: () => NOW_MS - 1 },
      },
      featureAccess: gated,
    });
    assert.ok(error);
    assert.equal(error.code, "permission-denied");
  });

  it("lets a Basic runner through once the admin moves the feature to basic", () => {
    const opened = config({ shareCards: { minimumTier: "basic", enabled: true } });
    const error = entitlementError({
      featureKey: "shareCards",
      userData: { subscriptionStatus: "basic" },
      featureAccess: opened,
    });
    assert.equal(error, undefined, "the console switch must reach the server without a redeploy");
  });
});

describe("server-gated feature keys", () => {
  // Every key a callable enforces must exist in the shipped catalog, or the
  // admin console would have no switch for a gate that is running in
  // production.
  for (const featureKey of [
    ACTIVITY_FEEDBACK_FEATURE_KEY,
    AI_HOME_COACH_FEATURE_KEY,
    SHARE_ROUTE_TO_FEED_FEATURE_KEY,
  ]) {
    it(`${featureKey} is present in DEFAULT_FEATURE_ACCESS_CONFIG`, () => {
      assert.ok(featureKey in DEFAULT_FEATURE_ACCESS_CONFIG.features);
    });
  }

  it("keeps activity feedback premium by default", () => {
    // The callable used to hardcode this check; the default records that
    // intent so replacing the hardcode did not silently open a paid AI
    // feature to every Basic runner.
    assert.equal(
      DEFAULT_FEATURE_ACCESS_CONFIG.features[ACTIVITY_FEEDBACK_FEATURE_KEY]?.minimumTier,
      "premium",
    );
  });
});
