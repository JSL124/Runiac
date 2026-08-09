import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { loadProgressionConfig } from "../config/configLoader.js";
import {
  leaderboardContributionId,
  writeLeaderboardContribution,
} from "../leaderboard/monthlyLeaderboard.js";
import {
  coolDownProgressionEventData,
  profileProgressionData,
  progressionDisplayFromEvent,
  readHighestPaidStreakMilestoneDays,
  type ProgressionAudit,
} from "../progression/progressionAudit.js";
import {
  isPremiumSubscription,
  readTotalXp,
  sumDailyXp,
  sumMonthlyXp,
} from "../progression/progressionAuditHelpers.js";
import {
  applyDailyXpCap,
  calculateCoolDownBonus,
  dailyCapDateForCompletedAt,
  monthlyPeriodForCompletedAt,
  resolveLevelProgression,
} from "../progression/progressionCalculator.js";
import {
  coolDownProgressionEventId,
  deterministicIds,
} from "./runCompletionArtifacts.js";
import type { CompleteCoolDownResult, ProgressionDisplay } from "./runCompletionTypes.js";
import { progressionInstantFor } from "./completedAtFreshness.js";
import { parseCoolDownCompletionPayload } from "./validateCoolDownPayload.js";
import { assertAccountNotSuspended } from "../security/accountStatus.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";

type CallableCoolDownRequest = {
  readonly auth?: {
    readonly uid: string;
  };
  readonly data: unknown;
};

if (getApps().length === 0) {
  initializeApp();
}

export const completeCoolDown = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("completeCoolDown", async (request: CallableCoolDownRequest) =>
    completeCoolDownForCallable(request, getFirestore())),
);

export async function completeCoolDownForCallable(
  request: CallableCoolDownRequest,
  firestore: Firestore,
): Promise<CompleteCoolDownResult> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required to complete a cool-down stretch.");
  }

  const payload = parseCoolDownCompletionPayload(request.data);
  const ids = deterministicIds(uid, payload.clientRunSessionId);
  if (payload.activityId !== ids.activityId) {
    throw new HttpsError("invalid-argument", "activityId does not match the completed run session.");
  }

  const coolDownEventId = coolDownProgressionEventId(uid, payload.clientRunSessionId);
  // Same clamp as completeRun: an accepted future completedAt must not choose
  // the cap date or the leaderboard period.
  const progressionInstant = progressionInstantFor(payload.completedAt);
  const dailyCapDate = dailyCapDateForCompletedAt(progressionInstant);
  const monthlyPeriod = monthlyPeriodForCompletedAt(progressionInstant);

  let progressionDisplay: ProgressionDisplay | undefined;
  let alreadyAwarded = false;
  const progressionConfig = await loadProgressionConfig(firestore);
  const nowMs = Date.now();

  await firestore.runTransaction(async (transaction) => {
    const activityRef = firestore.collection("activities").doc(ids.activityId);
    const baseProgressionRef = firestore.collection("progressionEvents").doc(ids.progressionEventId);
    const coolDownProgressionRef = firestore.collection("progressionEvents").doc(coolDownEventId);
    const userRef = firestore.collection("users").doc(uid);
    const profileRef = firestore.collection("userProfiles").doc(uid);
    const leaderboardContributionRef = firestore
      .collection("leaderboardContributions")
      .doc(leaderboardContributionId(uid, monthlyPeriod));
    const sameDayProgressionEventsQuery = firestore
      .collection("progressionEvents")
      .where("ownerUid", "==", uid)
      .where("dailyCapDate", "==", dailyCapDate);
    const sameMonthProgressionEventsQuery = firestore
      .collection("progressionEvents")
      .where("ownerUid", "==", uid)
      .where("monthlyPeriod", "==", monthlyPeriod);

    const [
      activitySnapshot,
      baseProgressionSnapshot,
      coolDownProgressionSnapshot,
      userSnapshot,
      profileSnapshot,
      leaderboardContributionSnapshot,
      sameDayProgressionEventSnapshots,
      sameMonthProgressionEventSnapshots,
    ] = await Promise.all([
      transaction.get(activityRef),
      transaction.get(baseProgressionRef),
      transaction.get(coolDownProgressionRef),
      transaction.get(userRef),
      transaction.get(profileRef),
      transaction.get(leaderboardContributionRef),
      transaction.get(sameDayProgressionEventsQuery),
      transaction.get(sameMonthProgressionEventsQuery),
    ]);

    // Defence-in-depth (see accountStatus.ts): reuses this transaction's own
    // users/{uid} read (userSnapshot), so a suspended caller is rejected
    // before this transaction performs its first write.
    assertAccountNotSuspended(userSnapshot.data());

    const activityData = activitySnapshot.data();
    if (activityData === undefined) {
      throw new HttpsError("not-found", "No validated run was found for this cool-down completion.");
    }
    if (activityData["ownerUid"] !== uid) {
      throw new HttpsError("permission-denied", "This run does not belong to the authenticated user.");
    }
    if (activityData["validationStatus"] !== "validated") {
      throw new HttpsError(
        "failed-precondition",
        "The run must be validated before a cool-down bonus can be awarded.",
      );
    }

    if (activityData["coolDownXpAwarded"] === true || coolDownProgressionSnapshot.exists) {
      progressionDisplay = progressionDisplayFromEvent(coolDownProgressionSnapshot.data());
      alreadyAwarded = true;
      return;
    }

    const baseEventData = baseProgressionSnapshot.data();
    const runXpDelta = baseEventData?.["xpDelta"];
    if (baseEventData === undefined || typeof runXpDelta !== "number") {
      throw new HttpsError("failed-precondition", "The completed run's XP could not be read.");
    }
    // `xpDelta` is the run's TOTAL award, which since the milestone exemption
    // can include a streak bonus of up to 600. calculateCoolDownBonus() ends
    // with `min(bonus, activityXpCap - baseEarnedXp)`, so feeding it the total
    // makes that term negative on any milestone run and silently zeroes the
    // stretch bonus — and the reason ladder below then reports
    // "low_data_no_xp" on a full-GPS run. The cool-down bonus is a percentage
    // of the ACTIVITY's XP, so net the milestone back out.
    const streakBonusXp = baseEventData["streakBonusXp"];
    const baseEarnedXp =
      typeof streakBonusXp === "number" && streakBonusXp > 0
        ? Math.max(0, runXpDelta - streakBonusXp)
        : runXpDelta;

    const isPremium =
      isPremiumSubscription(userSnapshot.data(), nowMs) || isPremiumSubscription(profileSnapshot.data(), nowMs);
    // Mirrors calculateProgressionAudit(): the tier alone withholds nothing —
    // only `config/progression.premiumEarnsXp: false` does. This path used to
    // branch on `isPremium` directly and so ignored the config plane entirely,
    // suppressing the stretch bonus even when premium runners earn XP.
    const premiumXpSuppressed = isPremium && !progressionConfig.premiumEarnsXp;
    const bonusBeforeDailyCap = premiumXpSuppressed
      ? 0
      : calculateCoolDownBonus(baseEarnedXp, progressionConfig);
    const dailyXpBefore = sumDailyXp(
      sameDayProgressionEventSnapshots.docs.map((document) => document.data()),
      dailyCapDate,
    );
    const capped = applyDailyXpCap(
      { xpDeltaBeforeDailyCap: bonusBeforeDailyCap, dailyXpBefore },
      progressionConfig,
    );
    const monthlyXpBefore = sumMonthlyXp(
      sameMonthProgressionEventSnapshots.docs.map((document) => document.data()),
      monthlyPeriod,
    );

    const previousTotalXp = readTotalXp(profileSnapshot.data());
    const previousProgression = resolveLevelProgression(previousTotalXp, progressionConfig);
    const nextTotalXp = previousTotalXp + capped.xpDelta;
    const nextProgression = resolveLevelProgression(nextTotalXp, progressionConfig);
    const monthlyXpAfter = monthlyXpBefore + capped.xpDelta;

    const reason: ProgressionDisplay["reason"] =
      capped.xpDelta > 0
        ? "cool_down_stretch_bonus_awarded"
        : premiumXpSuppressed
          ? "premium_no_progression"
          : bonusBeforeDailyCap > 0
            ? "cool_down_daily_cap_reached"
            : "low_data_no_xp";
    const status: ProgressionDisplay["status"] = capped.xpDelta > 0 ? "awarded" : "not_awarded";
    const countsTowardLeaderboard = capped.xpDelta > 0;

    progressionDisplay = {
      xpDelta: capped.xpDelta,
      countsTowardLeaderboard,
      status,
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
    };

    transaction.set(
      coolDownProgressionRef,
      coolDownProgressionEventData({
        uid,
        activityId: ids.activityId,
        payload,
        baseEarnedXp,
        bonusBeforeDailyCap,
        dailyCapDate,
        monthlyPeriod,
        dailyXpBefore,
        dailyXpAfter: capped.dailyXpAfter,
        dailyCapApplied: capped.dailyCapApplied,
        monthlyXpBefore,
        monthlyXpAfter,
        previousTotalXp,
        nextTotalXp,
        previousProgression,
        nextProgression,
        countsTowardLeaderboard,
        reason,
        status,
        xpDelta: capped.xpDelta,
      }),
    );

    const audit: ProgressionAudit = {
      progressionDisplay,
      baseCompletionXp: 0,
      distanceXp: 0,
      durationXp: 0,
      planCompletionBonusXp: 0,
      rawXpBeforeActivityCap: bonusBeforeDailyCap,
      rawXpBeforeDailyCap: bonusBeforeDailyCap,
      activityCapApplied: false,
      dailyCapDate,
      monthlyPeriod,
      dailyXpBefore,
      dailyXpAfter: capped.dailyXpAfter,
      monthlyXpBefore,
      monthlyXpAfter,
      dailyCapApplied: capped.dailyCapApplied,
      // Contract: the cool-down path has no streak transition of its own and
      // must NEVER award a streak milestone bonus — mirrors baseCompletionXp:
      // 0 / planCompletionBonusXp: 0 above.
      streakBonusXp: 0,
      streakMilestoneDays: null,
      streakBonusCapped: false,
      // Pass the stored mark through unchanged. This path pays no milestone,
      // so it must neither advance the mark nor reset it to 0 — the profile
      // write below would otherwise erase the owner's payment history and make
      // every milestone re-earnable.
      highestPaidStreakMilestoneDays: readHighestPaidStreakMilestoneDays(
        profileSnapshot.data(),
      ),
      xpDelta: capped.xpDelta,
      previousTotalXp,
      nextTotalXp,
      previousProgression,
      nextProgression,
      reason,
    };
    transaction.set(profileRef, profileProgressionData(audit, payload.completedAt), { merge: true });

    writeLeaderboardContribution({
      transaction,
      firestore,
      uid,
      progressionEventId: coolDownEventId,
      completedAt: payload.completedAt,
      periodKey: monthlyPeriod,
      scoreXp: capped.xpDelta,
      divisionKey: nextProgression.divisionKey,
      divisionLabel: nextProgression.divisionLabel,
      levelLabel: nextProgression.levelLabel,
      profileData: profileSnapshot.data(),
      existingContributionData: leaderboardContributionSnapshot.data(),
      // Cool-down does not read the user's activity history in this
      // transaction, so it must never overwrite the recomputed count.
      qualifyingRunCount: null,
    });

    transaction.set(
      activityRef,
      {
        coolDownXpAwarded: true,
        coolDownXpAwardedAt: payload.completedAt,
        coolDownProgressionEventId: coolDownEventId,
      },
      { merge: true },
    );
  });

  if (progressionDisplay === undefined) {
    throw new HttpsError("internal", "Cool-down completion did not produce a progression display.");
  }

  return {
    activityId: ids.activityId,
    coolDownProgressionEventId: coolDownEventId,
    alreadyAwarded,
    progressionDisplay,
  };
}
