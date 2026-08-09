import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { applyChallengeContribution } from "../challenge/challengeContribution.js";
import { loadProgressionConfig } from "../config/configLoader.js";
import {
  leaderboardContributionId,
  writeLeaderboardContribution,
} from "../leaderboard/monthlyLeaderboard.js";
import { persistAdaptiveEstimateLearning } from "../plan/adaptiveEstimate.js";
import { persistCompletedWorkoutProgress } from "../plan/planProgress.js";
import {
  calculateProgressionAudit,
  noCompletedWorkoutRecorded,
  planCompletionFromEvent,
  profileProgressionData,
  progressionEventData,
  progressionDisplayFromEvent,
} from "../progression/progressionAudit.js";
import {
  dailyCapDateForCompletedAt,
  monthlyPeriodForCompletedAt,
} from "../progression/progressionCalculator.js";
import { deferredProgressionDisplay } from "../progression/progressionEventWriter.js";
import { assertAccountNotSuspended } from "../security/accountStatus.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";
import { readTrustedProtectedRestDates, readTrustedStreakState } from "../progression/planBoundedStreakState.js";
import {
  calculateStreakStateFromRuns,
  calculateStreakTransition,
  type StreakRun,
  type StreakState,
  unchangedStreakTransition,
} from "../progression/streakCalculator.js";
import {
  assertExistingActivityMatchesPayload,
  buildRunSummary,
  deterministicIds,
  fingerprintPayload,
  formatLongestStreakLabel,
  formatTotalDistanceLabel,
} from "./runCompletionArtifacts.js";
import type { CompleteRunResult, PlanCompletionResult, ProgressionDisplay } from "./runCompletionTypes.js";
import { progressionInstantFor } from "./completedAtFreshness.js";
import { parseRunCompletionPayload } from "./validateRunPayload.js";
type CallableRunRequest = {
  readonly auth?: {
    readonly uid: string;
  };
  readonly data: unknown;
};
if (getApps().length === 0) {
  initializeApp();
}
export const completeRun = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("completeRun", async (request: CallableRunRequest) =>
    completeRunForCallable(request, getFirestore())),
);

export async function completeRunForCallable(
  request: CallableRunRequest,
  firestore: Firestore,
): Promise<CompleteRunResult> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required to complete a run.");
  }

  const payload = parseRunCompletionPayload(request.data);
  const ids = deterministicIds(uid, payload.clientRunSessionId);
  const payloadFingerprint = fingerprintPayload(payload);
  const runSummary = buildRunSummary(payload);
  // Period keys come from a server-clamped instant, never straight from the
  // payload: a completedAt inside the accepted future allowance must not get
  // to pick which day's cap and which month's board the run lands in.
  const progressionInstant = progressionInstantFor(payload.completedAt);
  const dailyCapDate = dailyCapDateForCompletedAt(progressionInstant);
  const monthlyPeriod = monthlyPeriodForCompletedAt(progressionInstant);
  let progressionDisplay: ProgressionDisplay = deferredProgressionDisplay();
  let planCompletion: PlanCompletionResult = { completed: false };
  const progressionConfig = await loadProgressionConfig(firestore);

  await firestore.runTransaction(async (transaction) => {
    const activityRef = firestore.collection("activities").doc(ids.activityId);
    const summaryRef = firestore.collection("runSummaries").doc(ids.summaryId);
    const progressionRef = firestore.collection("progressionEvents").doc(ids.progressionEventId);
    const userRef = firestore.collection("users").doc(uid);
    const profileRef = firestore.collection("userProfiles").doc(uid);
    const generatedPlanRef = firestore.collection("generatedPlans").doc(uid);
    const planProgressRef = firestore.collection("planProgress").doc(uid);
    const adaptiveEstimateRef = firestore.collection("adaptivePlanEstimates").doc(uid);
    const leaderboardContributionRef = firestore
      .collection("leaderboardContributions")
      .doc(leaderboardContributionId(uid, monthlyPeriod));
    const activitiesQuery = firestore.collection("activities").where("ownerUid", "==", uid);
    const progressionEventsQuery = firestore
      .collection("progressionEvents")
      .where("ownerUid", "==", uid)
      .where("dailyCapDate", "==", dailyCapDate);
    const monthlyProgressionEventsQuery = firestore
      .collection("progressionEvents")
      .where("ownerUid", "==", uid)
      .where("monthlyPeriod", "==", monthlyPeriod);
    const [
      activitySnapshot,
      summarySnapshot,
      progressionSnapshot,
      userSnapshot,
      profileSnapshot,
      generatedPlanSnapshot,
      planProgressSnapshot,
      adaptiveEstimateSnapshot,
      leaderboardContributionSnapshot,
      activitySnapshots,
      progressionEventSnapshots,
      monthlyProgressionEventSnapshots,
    ] = await Promise.all([
        transaction.get(activityRef),
        transaction.get(summaryRef),
        transaction.get(progressionRef),
        transaction.get(userRef),
        transaction.get(profileRef),
        transaction.get(generatedPlanRef),
        transaction.get(planProgressRef),
        transaction.get(adaptiveEstimateRef),
        transaction.get(leaderboardContributionRef),
        transaction.get(activitiesQuery),
        transaction.get(progressionEventsQuery),
        transaction.get(monthlyProgressionEventsQuery),
      ]);

    // Defence-in-depth (see accountStatus.ts): reuses this transaction's own
    // users/{uid} read (userSnapshot), so a suspended caller is rejected
    // before this transaction performs its first write.
    assertAccountNotSuspended(userSnapshot.data());

    if (activitySnapshot.exists) {
      assertExistingActivityMatchesPayload(activitySnapshot.data(), payloadFingerprint);
    }

    // Challenge contribution seam (Todo 5). Runs after payload validation and
    // replay matching, and strictly BEFORE this transaction's first write (its
    // internal reads must precede every write). It never throws for challenge
    // state reasons and never touches XP/streak/level/leaderboard outputs;
    // non-participants pay at most one extra read.
    const nowMs = Date.now();
    await applyChallengeContribution({
      transaction,
      firestore,
      uid,
      activityId: ids.activityId,
      activityAlreadyExists: activitySnapshot.exists,
      distanceMeters: payload.distanceMeters,
      completedAtMs: Date.parse(payload.completedAt),
      nowMs,
    });

    const shouldPersistProgression = !activitySnapshot.exists;
    let planProgressResult = noCompletedWorkoutRecorded();
    if (shouldPersistProgression) {
      planProgressResult = persistCompletedWorkoutProgress({
        transaction,
        progressRef: planProgressRef,
        uid,
        ids,
        payload,
        generatedPlanData: generatedPlanSnapshot.data(),
        progressData: planProgressSnapshot.data(),
      });
    }

    const currentStreakState = readTrustedStreakState({
      profileState: readStreakState(profileSnapshot.data()),
      generatedPlanData: generatedPlanSnapshot.data(),
      activityDocuments: activitySnapshots.docs.map((document) => document.data()),
    });
    const countsTowardStreak =
      !planProgressResult.matchedPlanWorkout || planProgressResult.completedWorkoutRecorded;
    const streakTransition = shouldPersistProgression
      ? countsTowardStreak
        ? calculateStreakTransition({
            currentState: currentStreakState,
            completedAt: payload.completedAt,
            protectedRestDates: readTrustedProtectedRestDates(generatedPlanSnapshot.data()),
          })
        : unchangedStreakTransition(currentStreakState, payload.completedAt)
      : undefined;

    // shouldPersistProgression implies streakTransition is defined (see the
    // ternary above); the explicit undefined check is a type-narrowing guard
    // only, not a behaviour change — the false branch is unreachable in
    // practice.
    const xpAudit = shouldPersistProgression && streakTransition !== undefined
      ? calculateProgressionAudit({
          payload,
          profileData: profileSnapshot.data(),
          subscriptionData: userSnapshot.data(),
          dailyCapDate,
          monthlyPeriod,
          sameDayProgressionEventDocuments: progressionEventSnapshots.docs.map((document) => document.data()),
          sameMonthProgressionEventDocuments: monthlyProgressionEventSnapshots.docs.map((document) => document.data()),
          planProgressResult,
          config: progressionConfig,
          nowMs,
          streakTransition,
        })
      : null;

    if (!activitySnapshot.exists) {
      transaction.set(activityRef, {
        ownerUid: uid,
        status: "validated",
        source: payload.source,
        activityType: "run",
        startedAt: payload.startedAt,
        endedAt: payload.completedAt,
        durationSeconds: payload.durationSeconds,
        activeDurationSeconds: payload.activeDurationSeconds,
        elapsedWallSeconds: payload.elapsedWallSeconds,
        pausedDurationSeconds: payload.pausedDurationSeconds,
        distanceMeters: payload.distanceMeters,
        averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm,
        routePrivacy: payload.routePrivacy,
        clientRunSessionId: payload.clientRunSessionId,
        payloadFingerprint,
        createdAt: payload.completedAt,
        updatedAt: payload.completedAt,
        processedAt: payload.completedAt,
        validationStatus: "validated",
        validatedActivityContributionState: xpAudit?.xpDelta === 0 ? "not_awarded" : "awarded",
        countsTowardProgression: (xpAudit?.xpDelta ?? 0) > 0,
        countsTowardStreak,
        plannedWorkoutRecorded: planProgressResult.completedWorkoutRecorded,
        validationReason: xpAudit?.reason ?? "progression_formula_deferred",
        ...(payload.cadenceAnalysisSeries === undefined
          ? {}
          : { cadenceAnalysisSeries: payload.cadenceAnalysisSeries }),
      });
    }

    if (!summarySnapshot.exists) {
      transaction.set(summaryRef, {
        ownerUid: uid,
        activityId: ids.activityId,
        clientRunSessionId: payload.clientRunSessionId,
        ...runSummary,
        createdAt: payload.completedAt,
      });
    }

    if (!progressionSnapshot.exists) {
      if (streakTransition === undefined) {
        throw new HttpsError("already-exists", "Existing run completion progression state is unreadable.");
      }
      if (xpAudit === null) {
        throw new HttpsError("already-exists", "Existing run completion XP state is unreadable.");
      }

      progressionDisplay = {
        ...xpAudit.progressionDisplay,
        previousStreak: streakTransition.previousStreak,
        streak: streakTransition.nextStreak,
      };
      planCompletion = planProgressResult.completedWorkoutRecorded
        ? {
            completed: true,
            ...(planProgressResult.planEnrollmentId === null
              ? {}
              : { planEnrollmentId: planProgressResult.planEnrollmentId }),
            ...(planProgressResult.scheduledWorkoutId === null
              ? {}
              : { scheduledWorkoutId: planProgressResult.scheduledWorkoutId }),
          }
        : { completed: false };
      transaction.set(
        progressionRef,
        progressionEventData({ uid, ids, payload, audit: xpAudit, streakTransition, planProgressResult }),
      );
      // Definition: validated runs completed within the monthly period — the
      // admin-facing meaning of "runs to qualify" (`config/leaderboard.minRunsToQualify`).
      // Recomputed as an absolute value from the full validated activity
      // history already fetched in this transaction (no extra reads), so a
      // legacy contribution with an under-counted or missing
      // `qualifyingRunCount` self-heals on the user's very next run. The
      // current run is written earlier in this transaction and so is not yet
      // present in `activitySnapshots`; fold it in explicitly, guarded by
      // `!activitySnapshot.exists` so a replay (activity already present in
      // the query result) is never double-counted.
      let qualifyingRunCount = activitySnapshot.exists ? 0 : 1;
      for (const activityDocument of activitySnapshots.docs) {
        const data = activityDocument.data();
        if (data["activityType"] !== "run" || data["validationStatus"] !== "validated") {
          continue;
        }
        const completedAt = readActivityCompletedAt(data);
        if (completedAt !== null && monthlyPeriodForCompletedAt(completedAt) === xpAudit.monthlyPeriod) {
          qualifyingRunCount += 1;
        }
      }
      writeLeaderboardContribution({
        transaction,
        firestore,
        uid,
        progressionEventId: ids.progressionEventId,
        completedAt: payload.completedAt,
        periodKey: xpAudit.monthlyPeriod,
        scoreXp: xpAudit.xpDelta,
        divisionKey: xpAudit.nextProgression.divisionKey,
        divisionLabel: xpAudit.nextProgression.divisionLabel,
        levelLabel: xpAudit.nextProgression.levelLabel,
        profileData: profileSnapshot.data(),
        existingContributionData: leaderboardContributionSnapshot.data(),
        qualifyingRunCount,
      });
    } else {
      progressionDisplay = progressionDisplayFromEvent(progressionSnapshot.data());
      planCompletion = planCompletionFromEvent(progressionSnapshot.data());
    }

    if (streakTransition?.shouldUpdateProfile === true) {
      transaction.set(
        profileRef,
        {
          streakCount: streakTransition.nextStreak,
          lastStreakRunDate: streakTransition.nextStreakRunDate,
          streakUpdatedAt: streakTransition.streakUpdatedAt,
        },
        { merge: true },
      );
    }

    // Backend-owned lifetime stats for the profile page, recomputed from the
    // full validated activity history already fetched in this transaction (no
    // extra reads). Self-healing: it reflects every recorded run — including
    // any that predate this field — and is naturally idempotent, so replays
    // never double-count. Runs on genuinely new completions only.
    if (shouldPersistProgression) {
      const streakRuns: StreakRun[] = [];
      let totalDistanceMeters = 0;
      for (const activityDocument of activitySnapshots.docs) {
        const data = activityDocument.data();
        if (data["activityType"] !== "run" || data["validationStatus"] !== "validated") {
          continue;
        }
        const distanceMeters = data["distanceMeters"];
        if (typeof distanceMeters === "number" && Number.isFinite(distanceMeters) && distanceMeters > 0) {
          totalDistanceMeters += distanceMeters;
        }
        if (data["countsTowardStreak"] !== false) {
          const completedAt = readActivityCompletedAt(data);
          if (completedAt !== null) {
            streakRuns.push({ completedAt });
          }
        }
      }
      // The current run is written earlier in this transaction, so it is not yet
      // in the fetched snapshot — fold it in explicitly.
      if (payload.distanceMeters > 0) {
        totalDistanceMeters += payload.distanceMeters;
      }
      if (countsTowardStreak) {
        streakRuns.push({ completedAt: payload.completedAt });
      }

      const recomputedLongestStreak = longestStreakFromRuns(
        streakRuns,
        readTrustedProtectedRestDates(generatedPlanSnapshot.data()),
      );
      // "Max streak ever" must never regress, e.g. if historical rest-day
      // context is unavailable to bridge an old gap.
      const longestStreak = Math.max(
        readNonNegativeInteger(profileSnapshot.data()?.["longestStreak"]),
        recomputedLongestStreak,
      );
      transaction.set(
        profileRef,
        {
          longestStreak,
          longestStreakLabel: formatLongestStreakLabel(longestStreak),
          totalDistanceMeters,
          totalDistanceLabel: formatTotalDistanceLabel(totalDistanceMeters),
        },
        { merge: true },
      );
    }

    if (shouldPersistProgression && xpAudit !== null) {
      transaction.set(profileRef, profileProgressionData(xpAudit, payload.completedAt), { merge: true });
    }

    if (shouldPersistProgression) {
      persistAdaptiveEstimateLearning({
        transaction,
        estimateRef: adaptiveEstimateRef,
        uid,
        ids,
        payload,
        estimateData: adaptiveEstimateSnapshot.data(),
      });
    }
  });

  return {
    ...ids,
    validationStatus: "validated",
    runSummary,
    progressionDisplay,
    planCompletion,
    message: "Run completion accepted by emulator backend skeleton.",
  };
}

function readStreakState(profileData: FirebaseFirestore.DocumentData | undefined): StreakState {
  if (profileData === undefined) {
    return { streakCount: 0, lastStreakRunDate: null };
  }

  const streakCount = profileData["streakCount"];
  const lastStreakRunDate = profileData["lastStreakRunDate"];
  const hasPersistedStreak = typeof streakCount === "number" && Number.isInteger(streakCount) && streakCount > 0;

  return {
    streakCount: hasPersistedStreak ? streakCount : 0,
    lastStreakRunDate: hasPersistedStreak && typeof lastStreakRunDate === "string" ? lastStreakRunDate : null,
  };
}

function readNonNegativeInteger(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : 0;
}

function readActivityCompletedAt(activityData: FirebaseFirestore.DocumentData): string | null {
  const endedAt = activityData["endedAt"];
  if (typeof endedAt === "string") {
    return endedAt;
  }
  const completedAt = activityData["completedAt"];
  return typeof completedAt === "string" ? completedAt : null;
}

// Highest streak ever reached across the given runs. Reuses the canonical
// streak reducer over each date-ordered prefix, so the streak height on every
// run day is evaluated and the maximum retained — no duplication of the
// day-transition rules (consecutive day, same-day, rest-day bridge, gap reset).
function longestStreakFromRuns(
  runs: readonly StreakRun[],
  protectedRestDates: readonly string[],
): number {
  const orderedRuns = [...runs].sort((left, right) =>
    dailyCapDateForCompletedAt(left.completedAt).localeCompare(
      dailyCapDateForCompletedAt(right.completedAt),
    ),
  );
  let peak = 0;
  for (let length = 1; length <= orderedRuns.length; length += 1) {
    const { streakCount } = calculateStreakStateFromRuns(
      orderedRuns.slice(0, length),
      protectedRestDates,
    );
    if (streakCount > peak) {
      peak = streakCount;
    }
  }
  return peak;
}
