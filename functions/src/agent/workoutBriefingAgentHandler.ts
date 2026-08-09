import type { Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { HttpsError } from "firebase-functions/v2/https";
import {
  WorkoutBriefingContractError,
  parseWorkoutBriefingRequest,
  type WorkoutBriefingAgentResponse,
} from "./workoutBriefingContracts.js";
import { WORKOUT_BRIEFING_FALLBACK_SECTIONS } from "./workoutBriefingModelOutput.js";
import {
  generateWorkoutBriefingSections,
  type WorkoutBriefingGenerationFallbackCategory,
  type WorkoutBriefingModelProvider,
} from "./workoutBriefingModel.js";
import { reserveWorkoutBriefingQuota } from "./workoutBriefingQuota.js";
import { loadFeatureAccessConfig } from "../config/configLoader.js";
import {
  assertFeatureEntitlement,
  FEATURE_PREMIUM_REQUIRED_REASON,
} from "../config/featureEntitlement.js";

/**
 * Feature key in config/featureAccess.features that governs the AI workout
 * briefing agent. Mirrors DEFAULT_FEATURE_ACCESS_CONFIG in configLoader.ts.
 */
export const WORKOUT_BRIEFING_FEATURE_KEY = "workoutBriefing";

/**
 * Stable machine-readable reason attached to the permission-denied error so
 * the client can map it to its paywall instead of a generic failure.
 */
export const WORKOUT_BRIEFING_PREMIUM_REQUIRED_REASON = FEATURE_PREMIUM_REQUIRED_REASON;

export type WorkoutBriefingCallableRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

export type WorkoutBriefingAgentDependencies = {
  readonly firestore: () => Firestore;
  readonly now: () => Date;
  readonly providerFactory: () => WorkoutBriefingModelProvider;
};

type WorkoutBriefingDecisionFallbackCategory =
  | "none"
  | "quota"
  | WorkoutBriefingGenerationFallbackCategory;

/// Pure over its injected dependencies, so the whole auth → entitlement →
/// quota → generate policy chain is unit-testable with neither Firebase nor
/// OpenAI present, and the injected clock makes the quota day boundary
/// deterministic.
export function createWorkoutBriefingAgentHandler(
  dependencies: WorkoutBriefingAgentDependencies,
): (request: WorkoutBriefingCallableRequest) => Promise<WorkoutBriefingAgentResponse> {
  return async (request) => {
    const uid = authenticatedUid(request);
    const briefingRequest = parseRequest(request.data);
    const now = dependencies.now();
    // Tier owned by config/featureAccess.workoutBriefing and enforced here, so
    // the client-side paywall stays a UX layer rather than the access control.
    await requireWorkoutBriefingEntitlement(dependencies.firestore(), uid, now);
    const quota = await reserveWorkoutBriefingQuota({
      firestore: dependencies.firestore(),
      uid,
      now,
    });
    if (quota.kind === "quota") {
      const result: WorkoutBriefingAgentResponse = {
        source: "quota",
        delivery: "quota",
        sections: WORKOUT_BRIEFING_FALLBACK_SECTIONS,
        retryAfterDate: quota.retryAfterDate,
      };
      emitWorkoutBriefingDecisionLog(result, "quota");
      return result;
    }
    const generated = await generateWorkoutBriefingSections({
      provider: dependencies.providerFactory(),
      request: briefingRequest,
    });
    if (generated.kind === "generated") {
      const result: WorkoutBriefingAgentResponse = {
        source: "agent",
        delivery: "generated",
        sections: generated.sections,
      };
      emitWorkoutBriefingDecisionLog(result, "none");
      return result;
    }
    const result: WorkoutBriefingAgentResponse = {
      source: "unavailable",
      delivery: "fallback",
      sections: WORKOUT_BRIEFING_FALLBACK_SECTIONS,
    };
    emitWorkoutBriefingDecisionLog(result, generated.fallbackCategory);
    return result;
  };
}

async function requireWorkoutBriefingEntitlement(
  firestore: Firestore,
  uid: string,
  now: Date,
): Promise<void> {
  const [userSnapshot, featureAccess] = await Promise.all([
    firestore.doc(`users/${uid}`).get(),
    loadFeatureAccessConfig(firestore),
  ]);
  assertFeatureEntitlement({
    featureKey: WORKOUT_BRIEFING_FEATURE_KEY,
    userData: userSnapshot.data(),
    featureAccess,
    nowMs: now.getTime(),
    message: "Today's workout explainer is available on Premium.",
  });
}

function authenticatedUid(request: WorkoutBriefingCallableRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication is required to use the workout briefing agent.",
    );
  }
  return uid;
}

function parseRequest(data: unknown) {
  try {
    return parseWorkoutBriefingRequest(data);
  } catch (error) {
    if (error instanceof WorkoutBriefingContractError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
}

// Decision metadata only. No prompt, no generated copy, no plan text, and no
// uid reaches the log record.
function emitWorkoutBriefingDecisionLog(
  result: WorkoutBriefingAgentResponse,
  fallbackCategory: WorkoutBriefingDecisionFallbackCategory,
): void {
  const fields = {
    event: "workout_briefing_agent_result",
    delivery: result.delivery,
    source: result.source,
    fallbackCategory,
  } as const;
  if (result.delivery === "generated") {
    logger.info(fields);
  } else {
    logger.warn(fields);
  }
}
