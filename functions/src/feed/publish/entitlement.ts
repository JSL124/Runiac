import type { FeatureAccessConfig } from "../../config/configLoader.js";
import {
  assertFeatureEntitlement,
  FEATURE_PREMIUM_REQUIRED_REASON,
} from "../../config/featureEntitlement.js";

// Feature key in config/featureAccess.features that governs publishing a run
// to the Feed. Mirrors DEFAULT_FEATURE_ACCESS_CONFIG in configLoader.ts.
export const SHARE_ROUTE_TO_FEED_FEATURE_KEY = "shareRouteToFeed";

// Kept as a named re-export so feed callers and their tests keep a single
// import site for the reason contract, which is now shared by every
// feature-access-gated callable.
export const SHARE_ROUTE_TO_FEED_PREMIUM_REQUIRED_REASON =
  FEATURE_PREMIUM_REQUIRED_REASON;

/**
 * Server-side entitlement gate for publishing a run to the Feed.
 *
 * Thin wrapper over the shared `assertFeatureEntitlement` so sharing a run,
 * activity feedback, and the AI home coach all resolve their tier through one
 * code path against the same admin-owned document. Behaviour is unchanged:
 * `minimumTier: "premium"` restricts publishing to premium subscribers, and
 * anything else lets every authenticated owner publish.
 */
export function assertShareRouteToFeedEntitlement(
  userData: FirebaseFirestore.DocumentData | undefined,
  featureAccess: FeatureAccessConfig,
  nowMs: number,
): void {
  assertFeatureEntitlement({
    featureKey: SHARE_ROUTE_TO_FEED_FEATURE_KEY,
    userData,
    featureAccess,
    nowMs,
    message: "Sharing routes to Feed is available on Premium.",
  });
}
