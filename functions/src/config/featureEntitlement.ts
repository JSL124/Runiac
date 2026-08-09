import { HttpsError } from "firebase-functions/v2/https";
import type { FeatureAccessConfig } from "./configLoader.js";
import { isPremiumSubscription } from "../progression/progressionAuditHelpers.js";

// Stable, client-inspectable reason code returned in the HttpsError details so
// the app can distinguish "you need Premium" from other failures and map it to
// the paywall instead of a generic error toast. Shared by every
// feature-access-gated callable.
export const FEATURE_PREMIUM_REQUIRED_REASON = "premium-required";

/**
 * Whether `config/featureAccess` puts [featureKey] behind Premium.
 *
 * An absent entry reads as Basic: a key this deployment's catalog does not
 * know about must not invent a gate. `enabled: false` also reads as Basic —
 * the flag means "this tier rule is active", not "this feature exists", so
 * clearing it releases the gate rather than switching the feature off for
 * everyone. The client's `FeatureAccessReadModel` applies the identical rule,
 * so UX interception and server enforcement never disagree.
 */
export function isPremiumGatedFeature(
  featureAccess: FeatureAccessConfig,
  featureKey: string,
): boolean {
  const entry = featureAccess.features[featureKey];
  if (entry === undefined || entry.minimumTier !== "premium") {
    return false;
  }
  return entry.enabled !== false;
}

/**
 * Server-side entitlement gate for a `config/featureAccess` feature.
 *
 * Config-driven by design: the Platform Administrator's console switch is what
 * decides, so a feature moved to Basic stops being denied here without a
 * redeploy, and one moved to Premium starts being denied immediately. This is
 * the real access control — the app's paywall interception is a UX layer that
 * reads the same document.
 *
 * Pure over its inputs so it unit-tests without Firestore: callers pass the
 * `users/{uid}` document they have already fetched, the loaded config, and a
 * clock reading.
 */
export function assertFeatureEntitlement(input: {
  readonly featureKey: string;
  readonly userData: FirebaseFirestore.DocumentData | undefined;
  readonly featureAccess: FeatureAccessConfig;
  readonly nowMs: number;
  readonly message: string;
}): void {
  if (!isPremiumGatedFeature(input.featureAccess, input.featureKey)) {
    return;
  }
  if (isPremiumSubscription(input.userData, input.nowMs)) {
    return;
  }
  throw new HttpsError("permission-denied", input.message, {
    reason: FEATURE_PREMIUM_REQUIRED_REASON,
  });
}
