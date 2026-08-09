// Versioned nine-tier Challenge distance catalog (`challenge-distance-v1`).
//
// Pure data module: no firebase imports, no UI copy beyond the fixed English
// difficulty labels that are part of each tier's contract. The catalog is keyed
// by tier id (never a positional array). All numeric values are integers:
// distances in metres, durations in exact days and their millisecond
// equivalent. There is no future/disabled/enabled flag anywhere — all nine
// tiers are active launch scope.

import { CHALLENGE_CATALOG_VERSION } from "./challengeTypes.js";
import type {
  ChallengeCatalogEntry,
  ChallengeRulesSnapshot,
  ChallengeTierId,
} from "./challengeTypes.js";

const MS_PER_DAY = 86_400_000;
const DAYS_PER_WEEK = 7;

function weeksToDays(weeks: number): number {
  return weeks * DAYS_PER_WEEK;
}

function entry(
  tierId: ChallengeTierId,
  difficultyLabel: string,
  durationWeeks: number,
  maxParticipants: number,
  maxInvitedFriends: number,
  soloTargetMeters: number,
  personalMinimumMeters: number,
): ChallengeCatalogEntry {
  const durationDays = weeksToDays(durationWeeks);
  return {
    tierId,
    difficultyLabel,
    durationDays,
    durationMs: durationDays * MS_PER_DAY,
    maxParticipants,
    maxInvitedFriends,
    soloTargetMeters,
    personalMinimumMeters,
  };
}

// Display order only. Iteration order for hubs/grids; not the catalog storage.
export const CHALLENGE_TIER_IDS: readonly ChallengeTierId[] = [
  "10K",
  "20K",
  "42K",
  "100K",
  "200K",
  "250K",
  "300K",
  "500K",
  "1000K",
];

// Tier-keyed immutable catalog record.
export const CHALLENGE_CATALOG: Readonly<Record<ChallengeTierId, ChallengeCatalogEntry>> = {
  "10K": entry("10K", "Beginner", 1, 2, 1, 10_000, 3_000),
  "20K": entry("20K", "Easy", 2, 2, 1, 20_000, 5_000),
  "42K": entry("42K", "Normal", 3, 3, 2, 42_000, 7_000),
  "100K": entry("100K", "Challenging", 4, 4, 3, 100_000, 13_000),
  "200K": entry("200K", "Hard", 6, 5, 4, 200_000, 20_000),
  "250K": entry("250K", "Hard+", 7, 5, 4, 250_000, 25_000),
  "300K": entry("300K", "Very Hard", 8, 5, 4, 300_000, 30_000),
  "500K": entry("500K", "Extreme", 9, 7, 6, 500_000, 36_000),
  "1000K": entry("1000K", "Legend", 14, 8, 7, 1_000_000, 63_000),
};

export function getChallengeCatalogEntry(tierId: ChallengeTierId): ChallengeCatalogEntry {
  return CHALLENGE_CATALOG[tierId];
}

export function isChallengeTierId(value: string): value is ChallengeTierId {
  return Object.prototype.hasOwnProperty.call(CHALLENGE_CATALOG, value);
}

// Build the immutable rules snapshot recorded onto an instance at start. The
// team target is the tier's full distance target; the personal minimum applies
// to group members at settlement.
export function buildChallengeRulesSnapshot(tierId: ChallengeTierId): ChallengeRulesSnapshot {
  const catalogEntry = CHALLENGE_CATALOG[tierId];
  return {
    tierId: catalogEntry.tierId,
    catalogVersion: CHALLENGE_CATALOG_VERSION,
    difficultyLabel: catalogEntry.difficultyLabel,
    durationDays: catalogEntry.durationDays,
    durationMs: catalogEntry.durationMs,
    maxParticipants: catalogEntry.maxParticipants,
    maxInvitedFriends: catalogEntry.maxInvitedFriends,
    targetMeters: catalogEntry.soloTargetMeters,
    personalMinimumMeters: catalogEntry.personalMinimumMeters,
  };
}
