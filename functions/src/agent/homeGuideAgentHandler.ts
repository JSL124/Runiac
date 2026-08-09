import type { Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { HttpsError } from "firebase-functions/v2/https";
import {
  activePlanMarker,
  HomeGuideContractError,
  parseHomeGuidePlanDisplayContext,
  readTrustedHomeGuideActivities,
} from "./homeGuideContracts.js";
import { buildHomeGuideEvidence } from "./homeGuideEvidence.js";
import {
  assertNever,
  generateHomeGuideBundle,
  type HomeGuideGenerationFallbackCategory,
  type HomeGuideModelProvider,
} from "./homeGuideModel.js";
import {
  createHomeGuideContextFingerprint,
  finalizeHomeGuideAttemptFailure,
  finalizeHomeGuideAttemptReady,
  reserveHomeGuideQuota,
  singaporeDayKey,
  type HomeGuideBundle,
} from "./homeGuideQuotaCache.js";
import { requireCurrentHomeGuideConsent } from "./homeGuideConsent.js";
import { loadFeatureAccessConfig } from "../config/configLoader.js";
import { assertFeatureEntitlement } from "../config/featureEntitlement.js";

/**
 * Feature key in config/featureAccess.features that governs the AI home coach
 * bubble. Mirrors DEFAULT_FEATURE_ACCESS_CONFIG in configLoader.ts.
 */
export const AI_HOME_COACH_FEATURE_KEY = "aiHomeCoach";

const FALLBACK_MESSAGES: HomeGuideBundle = {
  planSummary: "Your plan is ready, superstar! Let's keep today comfy and fun.",
  runningTip: "Tiny trainer tip: Keep the effort relaxed and conversational.",
  progressionCheckIn: "You've got this! One comfy session at a time is plenty.",
};

export type CallableGuideRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

export type HomeGuideAgentResult = {
  readonly source: "agent" | "unavailable";
  readonly delivery: "generated" | "cache" | "fallback";
  readonly messages: HomeGuideBundle;
  readonly message: string;
};

export type HomeGuideAgentDependencies = {
  readonly firestore: () => Firestore;
  readonly now: () => Date;
  readonly providerFactory: () => HomeGuideModelProvider;
};
type HomeGuideDecisionFallbackCategory =
  | "none"
  | HomeGuideGenerationFallbackCategory
  | "lease_active"
  | "quota_unavailable"
  | "finalize_conflict";

export function createHomeGuideAgentHandler(
  dependencies: HomeGuideAgentDependencies,
): (request: CallableGuideRequest) => Promise<HomeGuideAgentResult> {
  return async (request) => {
    const uid = authenticatedUid(request);
    const planContext = parsePlanContext(request.data);
    const now = dependencies.now();
    const firestore = dependencies.firestore();
    await requireCurrentHomeGuideConsent(firestore, uid);
    // Tier owned by config/featureAccess.aiHomeCoach. Denying here is what
    // makes the console switch real: the app's guide adapter already falls
    // back to its offline rule-based copy on any callable error, so a Basic
    // runner keeps a working guide bubble instead of an empty one.
    await requireHomeGuideEntitlement(firestore, uid, now);
    const [activePlan, activities] = await Promise.all([
      firestore.collection("generatedPlans").doc(uid).get(),
      readTrustedHomeGuideActivities(firestore, uid, now),
    ]);
    const evidence = buildHomeGuideEvidence({ now, activities });
    const fingerprint = createHomeGuideContextFingerprint({
      dayKey: singaporeDayKey(now),
      activePlanMarker: activePlanMarker(activePlan.get("planId")),
      planContext,
      latestAcceptedActivityMarker: latestActivityMarker(activities),
      evidence,
    });
    const outcome = await reserveHomeGuideQuota({
      firestore,
      uid,
      now,
      fingerprint,
      fallback: FALLBACK_MESSAGES,
    });

    switch (outcome.kind) {
      case "cache": {
        const result = availableResult("cache", outcome.bundle);
        emitHomeGuideDecisionLog(result, "none");
        return result;
      }
      case "leased":
        return loggedFallbackResult(outcome.fallback, "lease_active");
      case "fallback":
        return loggedFallbackResult(outcome.fallback, "quota_unavailable");
      case "reserved": {
        const generated = await generateHomeGuideBundle({
          provider: dependencies.providerFactory(),
          planContext,
          evidence,
        });
        switch (generated.kind) {
          case "fallback":
            await finalizeHomeGuideAttemptFailure({ firestore, uid, now, reservation: outcome.reservation });
            return loggedFallbackResult(outcome.fallback, generated.fallbackCategory);
          case "generated": {
            switch (generated.copyStatus) {
              case "replaced":
                await finalizeHomeGuideAttemptFailure({ firestore, uid, now, reservation: outcome.reservation });
                return loggedFallbackResult(outcome.fallback, "policy_validation");
              case "preserved":
                break;
              default:
                return assertNever(generated.copyStatus);
            }
            const finalized = await finalizeHomeGuideAttemptReady({
              firestore,
              uid,
              now,
              reservation: outcome.reservation,
              bundle: generated.bundle,
            });
            if (!finalized) return loggedFallbackResult(outcome.fallback, "finalize_conflict");
            const result = availableResult("generated", generated.bundle);
            emitHomeGuideDecisionLog(result, "none");
            return result;
          }
          default:
            return assertNever(generated);
        }
      }
      default:
        return assertNever(outcome);
    }
  };
}

function loggedFallbackResult(
  messages: HomeGuideBundle,
  fallbackCategory: Exclude<HomeGuideDecisionFallbackCategory, "none">,
): HomeGuideAgentResult {
  const result = fallbackResult(messages);
  emitHomeGuideDecisionLog(result, fallbackCategory);
  return result;
}

function emitHomeGuideDecisionLog(
  result: HomeGuideAgentResult,
  fallbackCategory: HomeGuideDecisionFallbackCategory,
): void {
  const fields = {
    event: "home_guide_agent_result",
    delivery: result.delivery,
    source: result.source,
    fallbackCategory,
  } as const;
  if (result.delivery === "fallback") {
    logger.warn(fields);
  } else {
    logger.info(fields);
  }
}

async function requireHomeGuideEntitlement(
  firestore: Firestore,
  uid: string,
  now: Date,
): Promise<void> {
  const [userSnapshot, featureAccess] = await Promise.all([
    firestore.doc(`users/${uid}`).get(),
    loadFeatureAccessConfig(firestore),
  ]);
  assertFeatureEntitlement({
    featureKey: AI_HOME_COACH_FEATURE_KEY,
    userData: userSnapshot.data(),
    featureAccess,
    nowMs: now.getTime(),
    message: "The AI home coach is available on Premium.",
  });
}

function authenticatedUid(request: CallableGuideRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required to use the home guide agent.");
  }
  return uid;
}

function parsePlanContext(data: unknown) {
  try {
    return parseHomeGuidePlanDisplayContext(data);
  } catch (error) {
    if (error instanceof HomeGuideContractError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
}

function latestActivityMarker(activities: readonly { readonly endedAt: string }[]): string {
  return activities.reduce(
    (latest, activity) => activity.endedAt > latest ? activity.endedAt : latest,
    "no-accepted-activity",
  );
}

function availableResult(delivery: "generated" | "cache", messages: HomeGuideBundle): HomeGuideAgentResult {
  return { source: "agent", delivery, messages, message: messages.planSummary };
}

function fallbackResult(messages: HomeGuideBundle): HomeGuideAgentResult {
  return { source: "unavailable", delivery: "fallback", messages, message: messages.planSummary };
}
