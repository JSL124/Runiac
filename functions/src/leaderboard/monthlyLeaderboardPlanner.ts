import {
  leaderboardLeagueForKey,
  type LeaderboardLeagueDefinition,
} from "../progression/leaderboardLeagues.js";
import type { ProfileLevelDisplay } from "../progression/profileLevelDisplay.js";
import {
  singaporePlanningAreaForRegionId,
  type SingaporePlanningArea,
} from "./singaporePlanningAreas.js";
import {
  leaderboardContributionSchemaVersion,
  leaderboardTimezone,
  type LeaderboardContributionDocument,
  type LeaderboardPublicEntry,
  type MonthlyLeaderboardCurrentViewPlan,
  type MonthlyLeaderboardPlan,
  type MonthlyLeaderboardRankPlan,
  type MonthlyLeaderboardSnapshotPlan,
} from "./leaderboardTypes.js";

/**
 * Locally-extended contribution shape used only while planning: carries the
 * tolerantly-parsed `qualifyingRunCount` alongside the stored document
 * fields. `qualifyingRunCount` is `null` for legacy contributions written
 * before the minimum-runs gate existed; those are always grandfathered in.
 */
type ParsedLeaderboardContribution = Omit<
  LeaderboardContributionDocument,
  "qualifyingRunCount"
> & {
  readonly qualifyingRunCount: number | null;
};

export function planMonthlyLeaderboards(input: {
  readonly periodKey: string;
  readonly contributions: readonly FirebaseFirestore.DocumentData[];
  readonly currentPremiumUids?: ReadonlySet<string>;
  /**
   * Mirrors `LeaderboardConfig.excludePremium` (`config/leaderboard`). Defaults
   * to `false`, matching `DEFAULT_LEADERBOARD_CONFIG`: premium runners earn XP
   * on the same terms as everyone else, so they rank on the same board.
   */
  readonly excludePremium?: boolean;
  /**
   * Mirrors `LeaderboardConfig.minRunsToQualify` (`config/leaderboard`).
   * Defaults to `1`, matching `DEFAULT_LEADERBOARD_CONFIG`. A contribution
   * with a `null` `qualifyingRunCount` (a legacy document written before
   * this field existed) always passes the gate.
   */
  readonly minRunsToQualify?: number;
  /**
   * Per-owner avatar URL, already resolved through `resolveProfileAvatarUrl`
   * by the caller (`monthlyLeaderboardWriter.ts`, from the same `ownerFacts`
   * it loads for the premium re-check — zero extra reads). Optional so every
   * existing planner test keeps compiling unchanged; an owner absent from
   * the map, or an omitted map entirely, resolves to `avatarUrl: ""` on
   * their row, same as "no avatar set".
   */
  readonly avatarUrlByOwner?: ReadonlyMap<string, string>;
  /**
   * Per-owner public alias read live from `userProfiles.nickname` by the caller
   * (`monthlyLeaderboardWriter.ts`, from the same `ownerFacts` — zero extra
   * reads). A contribution only carries the alias captured at the run that
   * wrote it, so a runner who renames after their last run of the period would
   * otherwise stay on the board under the old nickname until they run again.
   * Optional, and an owner absent from the map (or a blank entry) falls back to
   * the contribution's stored alias, so every existing planner test and every
   * caller without profile access keeps its current behaviour.
   */
  readonly publicAliasByOwner?: ReadonlyMap<string, string>;
  /**
   * Per-owner live level display (`levelLabel` + `levelProgressPercent`) read
   * from `userProfiles` by the caller (`monthlyLeaderboardWriter.ts`, from the
   * same `ownerFacts` — zero extra reads), through the shared
   * `resolveProfileLevelDisplay`.
   *
   * Both fields resolve here for the same reason the alias does: a
   * contribution only carries the level captured at the run that wrote it, so
   * a runner who levels up on a run in a DIFFERENT region never updates this
   * board's contribution and keeps its old level until they run here again.
   * Publishing the pair together also keeps them consistent — a live ring next
   * to a frozen `levelLabel` could show Lv.8 on the pill and Lv.9's progress
   * on the ring.
   *
   * Optional, so every existing planner test and every caller without profile
   * access keeps its current behaviour: an owner absent from the map (or a
   * blank label) falls back to the contribution's stored label and to a
   * `levelProgressPercent` of 0.
   */
  readonly levelDisplayByOwner?: ReadonlyMap<string, ProfileLevelDisplay>;
}): MonthlyLeaderboardPlan {
  const premiumUids = input.currentPremiumUids ?? emptyUidSet;
  const excludePremium = input.excludePremium ?? false;
  const minRunsToQualify = input.minRunsToQualify ?? 1;
  const contributionByOwner = new Map<string, ParsedLeaderboardContribution>();
  for (const rawContribution of input.contributions) {
    const contribution = parseContribution(rawContribution, input.periodKey);
    if (contribution === null) {
      continue;
    }
    const existing = contributionByOwner.get(contribution.ownerUid);
    if (
      existing === undefined ||
      contribution.lastProgressionAt >= existing.lastProgressionAt
    ) {
      contributionByOwner.set(contribution.ownerUid, contribution);
    }
  }

  const groups = new Map<string, ParsedLeaderboardContribution[]>();
  const excludedCurrentViews: MonthlyLeaderboardCurrentViewPlan[] = [];
  for (const contribution of contributionByOwner.values()) {
    if (excludePremium && premiumUids.has(contribution.ownerUid)) {
      excludedCurrentViews.push({
        ownerUid: contribution.ownerUid,
        snapshotId: null,
        rankId: null,
        periodKey: input.periodKey,
        regionId: contribution.regionId,
        divisionKey: contribution.divisionKey,
        status: "ineligible_premium",
      });
      continue;
    }
    if (!contribution.eligible || contribution.scoreXp <= 0) {
      continue;
    }
    if (
      contribution.qualifyingRunCount !== null &&
      contribution.qualifyingRunCount < minRunsToQualify
    ) {
      excludedCurrentViews.push({
        ownerUid: contribution.ownerUid,
        snapshotId: null,
        rankId: null,
        periodKey: input.periodKey,
        regionId: contribution.regionId,
        divisionKey: contribution.divisionKey,
        status: "ineligible_min_runs",
      });
      continue;
    }
    const groupKey = `${contribution.regionId}\u0000${contribution.divisionKey}`;
    const group = groups.get(groupKey);
    if (group === undefined) {
      groups.set(groupKey, [contribution]);
    } else {
      group.push(contribution);
    }
  }

  const snapshots: MonthlyLeaderboardSnapshotPlan[] = [];
  const ranks: MonthlyLeaderboardRankPlan[] = [];
  const currentViews: MonthlyLeaderboardCurrentViewPlan[] = [
    ...excludedCurrentViews,
  ];
  const orderedGroups = [...groups.values()].sort(compareGroups);
  for (const group of orderedGroups) {
    const area = singaporePlanningAreaForRegionId(group[0]?.regionId);
    const league = leaderboardLeagueForKey(group[0]?.divisionKey);
    if (area === null || league === null) {
      continue;
    }
    const ranked = [...group].sort(compareContributions);
    const snapshotId = monthlyLeaderboardSnapshotId({
      periodKey: input.periodKey,
      regionId: area.regionId,
      divisionKey: league.key,
    });
    const publicEntries = ranked.map((contribution, index) =>
      publicEntry(
        contribution,
        area,
        league,
        index + 1,
        input.avatarUrlByOwner,
        input.publicAliasByOwner,
        input.levelDisplayByOwner,
      ),
    );
    snapshots.push({
      snapshotId,
      periodKey: input.periodKey,
      regionId: area.regionId,
      divisionKey: league.key,
      regionLabel: area.regionName,
      divisionLabel: league.label,
      entryCount: publicEntries.length,
      topEntries: publicEntries.slice(0, 10),
    });
    for (const [index, contribution] of ranked.entries()) {
      const rankId = monthlyLeaderboardRankId(
        contribution.ownerUid,
        input.periodKey,
      );
      const currentEntry = publicEntries[index];
      if (currentEntry === undefined) {
        continue;
      }
      const nearbyStart = Math.min(
        Math.max(0, index - 2),
        Math.max(0, publicEntries.length - 5),
      );
      ranks.push({
        rankId,
        ownerUid: contribution.ownerUid,
        snapshotId,
        periodKey: input.periodKey,
        regionId: area.regionId,
        divisionKey: league.key,
        rankLabel: currentEntry.rankLabel,
        score: contribution.scoreXp,
        currentEntry,
        nearbyEntries: publicEntries.slice(nearbyStart, nearbyStart + 5),
      });
      currentViews.push({
        ownerUid: contribution.ownerUid,
        snapshotId,
        rankId,
        periodKey: input.periodKey,
        regionId: area.regionId,
        divisionKey: league.key,
        status: "ranked",
      });
    }
  }

  return {
    periodKey: input.periodKey,
    snapshots,
    ranks,
    currentViews,
  };
}

export function monthlyLeaderboardSnapshotId(input: {
  readonly periodKey: string;
  readonly regionId: string;
  readonly divisionKey: string;
}): string {
  return `monthly_${input.regionId}_${input.divisionKey}_${input.periodKey}`;
}

export function monthlyLeaderboardRankId(
  ownerUid: string,
  periodKey: string,
): string {
  return `${ownerUid}_monthly_${periodKey}`;
}

function parseContribution(
  contribution: FirebaseFirestore.DocumentData,
  periodKey: string,
): ParsedLeaderboardContribution | null {
  const ownerUid = readRequiredString(contribution["ownerUid"]);
  const scoreXp = contribution["scoreXp"];
  const area = singaporePlanningAreaForRegionId(contribution["regionId"]);
  const league = leaderboardLeagueForKey(contribution["divisionKey"]);
  if (
    contribution["schemaVersion"] !== leaderboardContributionSchemaVersion ||
    ownerUid === null ||
    contribution["periodType"] !== "monthly" ||
    contribution["periodKey"] !== periodKey ||
    contribution["timezone"] !== leaderboardTimezone ||
    typeof scoreXp !== "number" ||
    !Number.isFinite(scoreXp) ||
    scoreXp < 0 ||
    area === null ||
    league === null
  ) {
    return null;
  }
  return {
    schemaVersion: leaderboardContributionSchemaVersion,
    ownerUid,
    publicAlias: readPublicAlias(contribution["publicAlias"]),
    regionId: area.regionId,
    regionLabel: area.regionName,
    planningAreaName: area.planningAreaName,
    planningAreaCode: area.planningAreaCode,
    planningRegionCode: area.planningRegionCode,
    divisionKey: league.key,
    divisionLabel: league.label,
    levelLabel: readRequiredString(contribution["levelLabel"]) ?? "",
    periodType: "monthly",
    periodKey,
    timezone: leaderboardTimezone,
    scoreXp: Math.floor(scoreXp),
    eligible: contribution["eligible"] === true,
    eligibilityReason:
      readRequiredString(contribution["eligibilityReason"]) ?? "not_eligible",
    lastProgressionAt:
      readRequiredString(contribution["lastProgressionAt"]) ?? "",
    sourceProgressionEventIds: readStringArray(
      contribution["sourceProgressionEventIds"],
    ),
    qualifyingRunCount: readOptionalNonNegativeInteger(
      contribution["qualifyingRunCount"],
    ),
  };
}

function readOptionalNonNegativeInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : null;
}

function publicEntry(
  contribution: ParsedLeaderboardContribution,
  area: SingaporePlanningArea,
  league: LeaderboardLeagueDefinition,
  rank: number,
  avatarUrlByOwner: ReadonlyMap<string, string> | undefined,
  publicAliasByOwner: ReadonlyMap<string, string> | undefined,
  levelDisplayByOwner: ReadonlyMap<string, ProfileLevelDisplay> | undefined,
): LeaderboardPublicEntry {
  const levelDisplay = levelDisplayByOwner?.get(contribution.ownerUid);
  return {
    // Live profile nickname wins over the alias frozen into the contribution
    // at the last run; a blank or missing live value keeps the stored one.
    publicAlias:
      readRequiredString(publicAliasByOwner?.get(contribution.ownerUid)) ??
      contribution.publicAlias,
    rankLabel: `#${rank}`,
    scoreLabel: `${contribution.scoreXp.toLocaleString("en-US")} XP`,
    // Live profile level wins over the label frozen into the contribution,
    // same rule as the alias above, and stays paired with the percent below.
    levelLabel:
      readRequiredString(levelDisplay?.levelLabel) ?? contribution.levelLabel,
    divisionLabel: league.label,
    regionLabel: area.regionName,
    score: contribution.scoreXp,
    avatarUrl: avatarUrlByOwner?.get(contribution.ownerUid) ?? "",
    levelProgressPercent: levelDisplay?.levelProgressPercent ?? 0,
  };
}

function compareGroups(
  left: readonly ParsedLeaderboardContribution[],
  right: readonly ParsedLeaderboardContribution[],
): number {
  const leftKey = `${left[0]?.regionId ?? ""}\u0000${left[0]?.divisionKey ?? ""}`;
  const rightKey = `${right[0]?.regionId ?? ""}\u0000${right[0]?.divisionKey ?? ""}`;
  return leftKey.localeCompare(rightKey);
}

function compareContributions(
  left: ParsedLeaderboardContribution,
  right: ParsedLeaderboardContribution,
): number {
  if (left.scoreXp !== right.scoreXp) {
    return right.scoreXp - left.scoreXp;
  }
  return left.ownerUid.localeCompare(right.ownerUid);
}

function readRequiredString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function readPublicAlias(value: unknown): string {
  return readRequiredString(value) ?? "Runiac Runner";
}

function readStringArray(value: unknown): readonly string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : emptyStringList;
}

const emptyUidSet: ReadonlySet<string> = new Set();
const emptyStringList: readonly string[] = [];
