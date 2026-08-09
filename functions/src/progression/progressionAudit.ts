import type { ProgressionConfig } from "../config/configLoader.js";
import type { PersistPlanProgressResult } from "../plan/planProgress.js";
import type { StreakTransition } from "./streakCalculator.js";
import type {
  CompleteRunIds,
  ProgressionDisplay,
  RawCoolDownCompletionPayload,
  RawRunCompletionPayload,
} from "../run/runCompletionTypes.js";
import {
  applyDailyXpCap,
  calculateActivityXp,
  calculateStreakMilestoneBonus,
  resolveLevelProgression,
  type LevelProgression,
  type StreakBonusResult,
} from "./progressionCalculator.js";
import {
  formatXpLabel,
  isPremiumSubscription,
  progressionReason,
  readTotalXp,
  sumDailyXp,
  sumMonthlyXp,
} from "./progressionAuditHelpers.js";

export { planCompletionFromEvent, progressionDisplayFromEvent } from "./progressionDisplayReader.js";

export type ProgressionAudit = {
  readonly progressionDisplay: ProgressionDisplay;
  readonly baseCompletionXp: number;
  readonly distanceXp: number;
  readonly durationXp: number;
  readonly planCompletionBonusXp: number;
  readonly rawXpBeforeActivityCap: number;
  readonly rawXpBeforeDailyCap: number;
  readonly activityCapApplied: boolean;
  readonly dailyCapDate: string;
  readonly monthlyPeriod: string;
  readonly dailyXpBefore: number;
  readonly dailyXpAfter: number;
  readonly monthlyXpBefore: number;
  readonly monthlyXpAfter: number;
  readonly dailyCapApplied: boolean;
  readonly streakBonusXp: number;
  readonly streakMilestoneDays: number | null;
  readonly streakBonusCapped: boolean;
  readonly highestPaidStreakMilestoneDays: number;
  readonly xpDelta: number;
  readonly previousTotalXp: number;
  readonly nextTotalXp: number;
  readonly previousProgression: LevelProgression;
  readonly nextProgression: LevelProgression;
  readonly reason: ProgressionDisplay["reason"];
};

export function calculateProgressionAudit(input: {
  readonly payload: RawRunCompletionPayload;
  readonly profileData: FirebaseFirestore.DocumentData | undefined;
  readonly subscriptionData: FirebaseFirestore.DocumentData | undefined;
  readonly dailyCapDate: string;
  readonly monthlyPeriod: string;
  readonly sameDayProgressionEventDocuments: readonly FirebaseFirestore.DocumentData[];
  readonly sameMonthProgressionEventDocuments: readonly FirebaseFirestore.DocumentData[];
  readonly planProgressResult: PersistPlanProgressResult;
  readonly config: ProgressionConfig;
  readonly nowMs: number;
  readonly streakTransition: StreakTransition;
}): ProgressionAudit {
  const previousTotalXp = readTotalXp(input.profileData);
  const previousProgression = resolveLevelProgression(previousTotalXp, input.config);
  const isPremium =
    isPremiumSubscription(input.subscriptionData, input.nowMs) ||
    isPremiumSubscription(input.profileData, input.nowMs);
  const activityXp = calculateActivityXp(
    {
      distanceMeters: input.payload.distanceMeters,
      activeDurationSeconds: input.payload.activeDurationSeconds,
      lowDataConfirmed: input.payload.userConfirmedLowDataSave === true,
      planCompletionBonusEligible: input.planProgressResult.completedWorkoutRecorded,
    },
    input.config,
  );
  const dailyXpBefore = sumDailyXp(input.sameDayProgressionEventDocuments, input.dailyCapDate);
  const monthlyXpBefore = sumMonthlyXp(
    input.sameMonthProgressionEventDocuments,
    input.monthlyPeriod,
  );
  const suppress = isPremium && !input.config.premiumEarnsXp;
  const capped = suppress
    ? { xpDelta: 0, dailyXpAfter: dailyXpBefore, dailyCapApplied: false }
    : applyDailyXpCap(
        {
          xpDeltaBeforeDailyCap: activityXp.xpDeltaBeforeDailyCap,
          dailyXpBefore,
        },
        input.config,
      );

  // Streak milestone bonus: deliberately EXEMPT from BOTH `activityXpCap` (that
  // cap is applied above, to the base activity XP only) and `dailyXpCap`.
  //
  // The daily cap exemption is required for the reward table to mean anything:
  // with dailyXpCap 200, the shipped 14-day (220) and 30-day (600) rewards
  // could never pay in full — a runner who crossed day 30 after an ordinary
  // 80 XP run received 120 of 600, and the remaining 480 was silently dropped
  // and never paid back. Capping a once-in-a-lifetime milestone against a
  // per-day budget conflates two different things.
  //
  // It is safe to exempt because the milestone is paid at most once per owner,
  // ever (`highestPaidStreakMilestoneDays`), so it cannot be farmed the way an
  // uncapped per-run reward could.
  //
  // A `suppress`ed run (premium && !premiumEarnsXp) or a low-data-confirmed run
  // earns zero base XP by design, so the bonus is withheld too — otherwise a
  // run that earns nothing could still unlock streak bonus XP as a side door.
  const highestPaidMilestoneDays = readHighestPaidStreakMilestoneDays(input.profileData);
  const streakBonus: StreakBonusResult =
    suppress || activityXp.reason === "low_data_no_xp"
      ? { bonusXp: 0, milestoneDays: null }
      : calculateStreakMilestoneBonus(
          { ...input.streakTransition, highestPaidMilestoneDays },
          input.config,
        );
  const streakBonusXp = streakBonus.bonusXp;
  // Retained in the contract and always false now that the bonus is exempt.
  // Kept rather than removed so stored progression events written before the
  // exemption stay readable, and so the field has a stable meaning: "the daily
  // cap trimmed this milestone".
  const streakBonusCapped = false;
  const streakMilestoneDays = streakBonus.milestoneDays;

  const xpDelta = capped.xpDelta + streakBonusXp;
  const dailyXpAfter = capped.dailyXpAfter + streakBonusXp;
  // Must report whether ANY portion — base activity XP or the streak bonus —
  // was trimmed by the daily cap, not just the base.
  const dailyCapApplied = capped.dailyCapApplied || streakBonusCapped;

  // `xpDelta` here is the final COMBINED amount, and `xpDeltaBeforeDailyCap`
  // stays base-only, so the "daily_cap_reached" branch fires only when the run
  // as a whole earned nothing.
  //
  // Known gap: when the cap trims the base to zero but an exempt milestone
  // still pays, the run reports "run_completion_xp_awarded" and the user sees
  // no cap notice, while the stored `dailyCapApplied: true` says the opposite.
  // Passing the base-only amount here does NOT fix that — it only rewrites the
  // stored reason. The Flutter mapper gates the reason message on
  // `awarded = status == 'awarded' && xpDelta > 0`
  // (xp_update_display_model_mapper.dart), which is true whenever the milestone
  // paid, so the message is never reached either way. Closing this needs a
  // coordinated mapper change that surfaces the cap note independently of
  // `awarded`; doing it backend-only would give `daily_cap_reached` two
  // meanings for no user-visible benefit.
  const reason = progressionReason({
    premiumXpSuppressed: suppress,
    activityReason: activityXp.reason,
    xpDeltaBeforeDailyCap: activityXp.xpDeltaBeforeDailyCap,
    xpDelta,
  });
  const nextTotalXp = previousTotalXp + xpDelta;
  const monthlyXpAfter = monthlyXpBefore + xpDelta;
  const nextProgression = resolveLevelProgression(nextTotalXp, input.config);

  return {
    progressionDisplay: {
      xpDelta,
      // Awarded XP always counts toward leaderboard scoring. Whether a premium
      // runner is *shown* on the board is `config/leaderboard.excludePremium`,
      // owned by the aggregator — not a second, silent rule here.
      countsTowardLeaderboard: xpDelta > 0,
      status: xpDelta > 0 ? "awarded" : "not_awarded",
      reason,
      totalXp: nextTotalXp,
      level: nextProgression.level,
      divisionKey: nextProgression.divisionKey,
      previousTotalXp,
      previousLevel: previousProgression.level,
      previousLevelProgressPercent: previousProgression.levelProgressPercent,
      levelProgressPercent: nextProgression.levelProgressPercent,
      nextLevelXp: nextProgression.nextLevelXp,
      xpToNextLevel: nextProgression.xpToNextLevel,
    },
    baseCompletionXp: activityXp.baseCompletionXp,
    distanceXp: activityXp.distanceXp,
    durationXp: activityXp.durationXp,
    planCompletionBonusXp: activityXp.planCompletionBonusXp,
    rawXpBeforeActivityCap: activityXp.rawXpBeforeActivityCap,
    rawXpBeforeDailyCap: activityXp.xpDeltaBeforeDailyCap,
    activityCapApplied: activityXp.activityCapApplied,
    dailyCapDate: input.dailyCapDate,
    monthlyPeriod: input.monthlyPeriod,
    dailyXpBefore,
    dailyXpAfter,
    monthlyXpBefore,
    monthlyXpAfter,
    dailyCapApplied,
    streakBonusXp,
    streakMilestoneDays,
    streakBonusCapped,
    // Advance the mark only when the milestone actually paid something. A
    // crossing whose bonus the daily cap trimmed to zero earned nothing, so
    // banking it would silently forfeit that milestone forever.
    highestPaidStreakMilestoneDays:
      streakMilestoneDays !== null && streakBonusXp > 0
        ? Math.max(highestPaidMilestoneDays, streakMilestoneDays)
        : highestPaidMilestoneDays,
    xpDelta,
    previousTotalXp,
    nextTotalXp,
    previousProgression,
    nextProgression,
    reason,
  };
}

export function progressionEventData(input: {
  readonly uid: string;
  readonly ids: CompleteRunIds;
  readonly payload: RawRunCompletionPayload;
  readonly audit: ProgressionAudit;
  readonly streakTransition: StreakTransition;
  readonly planProgressResult: PersistPlanProgressResult;
}): FirebaseFirestore.DocumentData {
  const display = input.audit.progressionDisplay;
  return {
    ownerUid: input.uid,
    activityId: input.ids.activityId,
    eventType: "run_completion_xp",
    status: display.status,
    createdAt: input.payload.completedAt,
    xpDelta: input.audit.xpDelta,
    rawXpBeforeDailyCap: input.audit.rawXpBeforeDailyCap,
    rawXpBeforeActivityCap: input.audit.rawXpBeforeActivityCap,
    baseCompletionXp: input.audit.baseCompletionXp,
    distanceXp: input.audit.distanceXp,
    durationXp: input.audit.durationXp,
    planCompletionBonusXp: input.audit.planCompletionBonusXp,
    activityCapApplied: input.audit.activityCapApplied,
    dailyCapDate: input.audit.dailyCapDate,
    monthlyPeriod: input.audit.monthlyPeriod,
    dailyXpBefore: input.audit.dailyXpBefore,
    dailyXpAfter: input.audit.dailyXpAfter,
    monthlyXpBefore: input.audit.monthlyXpBefore,
    monthlyXpAfter: input.audit.monthlyXpAfter,
    dailyCapApplied: input.audit.dailyCapApplied,
    streakBonusXp: input.audit.streakBonusXp,
    streakMilestoneDays: input.audit.streakMilestoneDays,
    streakBonusCapped: input.audit.streakBonusCapped,
    previousTotalXp: input.audit.previousTotalXp,
    nextTotalXp: input.audit.nextTotalXp,
    previousLevel: input.audit.previousProgression.level,
    nextLevel: input.audit.nextProgression.level,
    previousDivisionKey: input.audit.previousProgression.divisionKey,
    nextDivisionKey: input.audit.nextProgression.divisionKey,
    previousLevelProgressPercent: input.audit.previousProgression.levelProgressPercent,
    nextLevelProgressPercent: input.audit.nextProgression.levelProgressPercent,
    nextLevelXpTarget: input.audit.nextProgression.nextLevelXp,
    nextXpToNextLevel: input.audit.nextProgression.xpToNextLevel,
    previousStreak: input.streakTransition.previousStreak,
    nextStreak: input.streakTransition.nextStreak,
    previousStreakRunDate: input.streakTransition.previousStreakRunDate,
    nextStreakRunDate: input.streakTransition.nextStreakRunDate,
    countsTowardLeaderboard: display.countsTowardLeaderboard,
    reason: display.reason,
    plannedWorkoutBonusApplied: input.audit.planCompletionBonusXp > 0,
    plannedWorkoutMatched: input.planProgressResult.matchedPlanWorkout,
    plannedWorkoutRecorded: input.planProgressResult.completedWorkoutRecorded,
    planEnrollmentId: input.planProgressResult.planEnrollmentId,
    plannedWorkoutId: input.planProgressResult.scheduledWorkoutId,
    plannedWorkoutMatchedBy: input.planProgressResult.matchedBy,
  };
}

export function coolDownProgressionEventData(input: {
  readonly uid: string;
  readonly activityId: string;
  readonly payload: RawCoolDownCompletionPayload;
  readonly baseEarnedXp: number;
  readonly bonusBeforeDailyCap: number;
  readonly dailyCapDate: string;
  readonly monthlyPeriod: string;
  readonly dailyXpBefore: number;
  readonly dailyXpAfter: number;
  readonly dailyCapApplied: boolean;
  readonly monthlyXpBefore: number;
  readonly monthlyXpAfter: number;
  readonly previousTotalXp: number;
  readonly nextTotalXp: number;
  readonly previousProgression: LevelProgression;
  readonly nextProgression: LevelProgression;
  readonly countsTowardLeaderboard: boolean;
  readonly reason: ProgressionDisplay["reason"];
  readonly status: ProgressionDisplay["status"];
  readonly xpDelta: number;
}): FirebaseFirestore.DocumentData {
  return {
    ownerUid: input.uid,
    activityId: input.activityId,
    eventType: "cool_down_stretch_bonus",
    status: input.status,
    createdAt: input.payload.completedAt,
    xpDelta: input.xpDelta,
    rawXpBeforeDailyCap: input.bonusBeforeDailyCap,
    baseEarnedXp: input.baseEarnedXp,
    completedStretchCount: input.payload.completedStretchCount,
    dailyCapDate: input.dailyCapDate,
    monthlyPeriod: input.monthlyPeriod,
    dailyXpBefore: input.dailyXpBefore,
    dailyXpAfter: input.dailyXpAfter,
    dailyCapApplied: input.dailyCapApplied,
    monthlyXpBefore: input.monthlyXpBefore,
    monthlyXpAfter: input.monthlyXpAfter,
    // Contract: the cool-down path has no streak transition of its own and
    // must NEVER award a streak milestone bonus — these are pinned, not
    // computed, mirroring the baseCompletionXp: 0 / planCompletionBonusXp: 0
    // pattern in completeCoolDown.ts's ProgressionAudit construction.
    streakBonusXp: 0,
    streakMilestoneDays: null,
    streakBonusCapped: false,
    previousTotalXp: input.previousTotalXp,
    nextTotalXp: input.nextTotalXp,
    previousLevel: input.previousProgression.level,
    nextLevel: input.nextProgression.level,
    previousDivisionKey: input.previousProgression.divisionKey,
    nextDivisionKey: input.nextProgression.divisionKey,
    previousLevelProgressPercent: input.previousProgression.levelProgressPercent,
    nextLevelProgressPercent: input.nextProgression.levelProgressPercent,
    nextLevelXpTarget: input.nextProgression.nextLevelXp,
    nextXpToNextLevel: input.nextProgression.xpToNextLevel,
    countsTowardLeaderboard: input.countsTowardLeaderboard,
    reason: input.reason,
  };
}

export function profileProgressionData(audit: ProgressionAudit, updatedAt: string): FirebaseFirestore.DocumentData {
  return {
    totalXp: audit.nextTotalXp,
    level: audit.nextProgression.level,
    divisionTier: audit.nextProgression.divisionTier,
    divisionKey: audit.nextProgression.divisionKey,
    divisionLabel: audit.nextProgression.divisionLabel,
    levelLabel: audit.nextProgression.levelLabel,
    totalXpLabel: audit.nextProgression.totalXpLabel,
    monthlyXp: audit.monthlyXpAfter,
    monthlyXpLabel: formatXpLabel(audit.monthlyXpAfter),
    nextLevelXp: audit.nextProgression.nextLevelXp,
    xpToNextLevel: audit.nextProgression.xpToNextLevel,
    levelProgressPercent: audit.nextProgression.levelProgressPercent,
    // Never regresses: the mark is what makes a milestone payable exactly once,
    // so a later run with a collapsed streak baseline must not lower it.
    highestPaidStreakMilestoneDays: audit.highestPaidStreakMilestoneDays,
    progressionUpdatedAt: updatedAt,
  };
}

/**
 * Reads the owner's streak-milestone high-water mark from `userProfiles`.
 * Absent (every profile written before this field existed) reads as 0, which
 * grandfathers those owners into being able to earn each milestone once more —
 * the conservative direction, since the alternative would be to guess a mark
 * from a streak history that is itself plan-bounded and therefore untrusted.
 */
export function readHighestPaidStreakMilestoneDays(
  profileData: FirebaseFirestore.DocumentData | undefined,
): number {
  const stored = profileData?.["highestPaidStreakMilestoneDays"];
  return typeof stored === "number" && Number.isFinite(stored) && stored > 0
    ? Math.floor(stored)
    : 0;
}

export function noCompletedWorkoutRecorded(): PersistPlanProgressResult {
  return {
    matchedPlanWorkout: false,
    completedWorkoutRecorded: false,
    planEnrollmentId: null,
    scheduledWorkoutId: null,
    matchedBy: null,
  };
}
