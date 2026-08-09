import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import { getFirestore } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { leaderboardLeagueForKey } from "../progression/leaderboardLeagues.js";
import {
  singaporePlanningAreaForLocationLabel,
  singaporePlanningAreaForRegionId,
} from "./singaporePlanningAreas.js";
import {
  leaderboardContributionSchemaVersion,
  leaderboardTimezone,
  type LeaderboardContributionDocument,
} from "./leaderboardTypes.js";
import {
  currentSingaporeMonthKey,
  nextSingaporeMonthStart,
  refreshMonthlyLeaderboardSnapshots,
  singaporeMonthLabel,
} from "./monthlyLeaderboardWriter.js";
import { withScheduledErrorReporting } from "../errors/withErrorReporting.js";
import { scheduledAutomationEnabled } from "../config/automationGate.js";
import { avatarUrlContextFromEnvironment } from "../profile/avatar/context.js";

if (getApps().length === 0) {
  initializeApp();
}

export {
  monthlyLeaderboardRankId,
  monthlyLeaderboardSnapshotId,
  planMonthlyLeaderboards,
} from "./monthlyLeaderboardPlanner.js";
export {
  currentSingaporeMonthKey,
  nextSingaporeMonthStart,
  refreshMonthlyLeaderboardSnapshots,
  singaporeMonthLabel,
} from "./monthlyLeaderboardWriter.js";
export {
  leaderboardContributionSchemaVersion,
  leaderboardTimezone,
} from "./leaderboardTypes.js";
export type {
  LeaderboardContributionDocument,
  LeaderboardCurrentViewStatus,
  LeaderboardPublicEntry,
  MonthlyLeaderboardCurrentViewPlan,
  MonthlyLeaderboardPlan,
  MonthlyLeaderboardRankPlan,
  MonthlyLeaderboardSnapshotPlan,
} from "./leaderboardTypes.js";

export const refreshLeaderboardSnapshots = onSchedule(
  {
    schedule: "every 60 minutes",
    region: "asia-southeast1",
    timeZone: leaderboardTimezone,
  },
  withScheduledErrorReporting("refreshLeaderboardSnapshots", async () => {
    const firestore = getFirestore();
    // Gate the schedule wrapper only — the leaderboard admin recalculation
    // command (leaderboardAdminCommandCreated) and refreshMonthlyLeaderboardSnapshots
    // itself stay reachable while this sweep is paused, so an admin can
    // always force a refresh manually.
    if (
      !(await scheduledAutomationEnabled(
        firestore,
        "leaderboardSnapshotRefresh",
        "refreshLeaderboardSnapshots",
      ))
    ) {
      return;
    }
    await refreshMonthlyLeaderboardSnapshots(
      firestore,
      currentSingaporeMonthKey(new Date()),
      {},
      avatarUrlContextFromEnvironment(),
    );
  }),
);

export function leaderboardContributionId(
  uid: string,
  periodKey: string,
): string {
  return `${uid}_monthly_${periodKey}`;
}

export function writeLeaderboardContribution(input: {
  readonly transaction: Transaction;
  readonly firestore: Firestore;
  readonly uid: string;
  readonly progressionEventId: string;
  readonly completedAt: string;
  readonly periodKey: string;
  readonly scoreXp: number;
  readonly divisionKey: string;
  readonly divisionLabel: string;
  readonly levelLabel: string;
  readonly profileData: FirebaseFirestore.DocumentData | undefined;
  readonly existingContributionData:
    | FirebaseFirestore.DocumentData
    | undefined;
  /**
   * The caller's authoritative recompute of the qualifying-run count used to
   * gate `config/leaderboard.minRunsToQualify` — NOT an accumulator.
   * `completeRun` derives this from the full validated activity history it
   * already reads inside its transaction (validated runs completed within
   * the same monthly period), so every write is a correct absolute value and
   * self-heals any prior under-count. It is written as a plain value (never
   * `FieldValue.increment`), floored and clamped to `>= 0`. `completeCoolDown`
   * does not fetch activity history and passes `null`, which leaves the
   * stored `qualifyingRunCount` untouched.
   */
  readonly qualifyingRunCount: number | null;
}): LeaderboardContributionDocument | null {
  const contribution = leaderboardContributionFields(input);
  if (contribution === null) {
    // No contribution to create or add score to — a zero-XP run (daily cap
    // exhausted, low-data, suppressed premium) or an unresolvable region.
    //
    // The qualifying-run count still has to land: it counts VALIDATED RUNS in
    // the period, not XP-awarding ones. Dropping it here left a user who
    // exhausted the daily cap on their qualifying run stuck below
    // minRunsToQualify for the rest of the month, because the caller's
    // absolute recompute only reaches the document on the next XP-awarding
    // run.
    //
    // Only when the document already exists. A merge-set would otherwise MINT
    // a contribution carrying nothing but a run count — no score, no region,
    // no schema version — which the planner would then have to parse and
    // reject, and which the seed fixtures treat as a distinct state.
    //
    // And only when it already carries a count. The planner grandfathers a
    // contribution whose `qualifyingRunCount` is absent, so stamping a first
    // count here would END that grandfathering on a run that awarded nothing —
    // strictly earlier than before this path existed. If the recomputed count
    // is below `minRunsToQualify` (the recompute reads validated activity
    // history, which need not reproduce a legacy contribution's real run
    // count) a currently-ranked runner would drop to `ineligible_min_runs`
    // because of a zero-XP run. Refreshing an existing count is safe;
    // introducing one is not, so that is left to the next XP-awarding run,
    // which writes the full contribution anyway.
    if (
      input.qualifyingRunCount !== null &&
      input.existingContributionData !== undefined &&
      typeof input.existingContributionData["qualifyingRunCount"] === "number"
    ) {
      input.transaction.set(
        input.firestore
          .collection("leaderboardContributions")
          .doc(leaderboardContributionId(input.uid, input.periodKey)),
        { qualifyingRunCount: Math.max(0, Math.floor(input.qualifyingRunCount)) },
        { merge: true },
      );
    }
    return null;
  }
  input.transaction.set(
    input.firestore
      .collection("leaderboardContributions")
      .doc(leaderboardContributionId(input.uid, input.periodKey)),
    {
      ...contribution,
      scoreXp: FieldValue.increment(contribution.scoreXp),
      sourceProgressionEventIds: FieldValue.arrayUnion(
        input.progressionEventId,
      ),
      ...(input.qualifyingRunCount === null
        ? {}
        : { qualifyingRunCount: Math.max(0, Math.floor(input.qualifyingRunCount)) }),
    },
    { merge: true },
  );
  return contribution;
}

export function leaderboardContributionFields(input: {
  readonly uid: string;
  readonly progressionEventId: string;
  readonly completedAt: string;
  readonly periodKey: string;
  readonly scoreXp: number;
  readonly divisionKey: string;
  readonly divisionLabel: string;
  readonly levelLabel: string;
  readonly profileData: FirebaseFirestore.DocumentData | undefined;
  readonly existingContributionData?:
    | FirebaseFirestore.DocumentData
    | undefined;
}): LeaderboardContributionDocument | null {
  if (!Number.isFinite(input.scoreXp) || input.scoreXp <= 0) {
    return null;
  }
  const existingArea =
    input.existingContributionData?.["schemaVersion"] ===
      leaderboardContributionSchemaVersion &&
    input.existingContributionData?.["periodKey"] === input.periodKey
      ? singaporePlanningAreaForRegionId(
          input.existingContributionData["regionId"],
        )
      : null;
  const selectedArea = singaporePlanningAreaForLocationLabel(
    input.profileData?.["locationLabel"],
  );
  const area = existingArea ?? selectedArea;
  const league = leaderboardLeagueForKey(input.divisionKey);
  if (area === null || league === null) {
    return null;
  }
  return {
    schemaVersion: leaderboardContributionSchemaVersion,
    ownerUid: input.uid,
    publicAlias: publicAliasFromProfile(input.profileData),
    regionId: area.regionId,
    regionLabel: area.regionName,
    planningAreaName: area.planningAreaName,
    planningAreaCode: area.planningAreaCode,
    planningRegionCode: area.planningRegionCode,
    divisionKey: league.key,
    divisionLabel: league.label,
    levelLabel: input.levelLabel.trim(),
    periodType: "monthly",
    periodKey: input.periodKey,
    timezone: leaderboardTimezone,
    scoreXp: Math.floor(input.scoreXp),
    eligible: true,
    eligibilityReason: "eligible_basic_awarded_xp",
    lastProgressionAt: input.completedAt,
    sourceProgressionEventIds: [input.progressionEventId],
  };
}

function publicAliasFromProfile(
  profileData: FirebaseFirestore.DocumentData | undefined,
): string {
  const nickname = profileData?.["nickname"];
  return typeof nickname === "string" && nickname.trim().length > 0
    ? nickname.trim()
    : "Runiac Runner";
}
