// Pure helper reproducing the backend XP -> level curve for direct per-user
// progression corrections made from the admin console.
//
// This mirrors the shape of `config.levelIncrements` / `config.maxLevel`
// (see ./config-validation.ts, itself a field-for-field mirror of
// functions/src/config/configLoader.ts): the ten `levelIncrements` entries are
// grouped into ten-level bands (levels 2-10 use levelIncrements[0], levels
// 11-20 use levelIncrements[1], and so on), cumulative XP thresholds are built
// from those banded increments, and the level is the highest threshold
// reached by `totalXp`, capped at `maxLevel`. This is the single shared
// derivation used whenever an admin sets or adjusts a user's totalXp so the
// corrected level always matches the current progression curve.
//
// Has no Firebase/Next dependency so it can be unit tested in isolation, same
// as config-validation.ts.

import {
  DEFAULT_PROGRESSION_CONFIG,
  type ProgressionConfig,
} from "@/lib/admin/config-validation";

// Current progression snapshot for a single user, read from userProfiles/{uid}.
// `null` fields mean the value has never been persisted for this user yet.
export type UserProgressionFields = {
  readonly totalXp: number | null;
  readonly level: number | null;
  readonly monthlyXp: number | null;
};

// Must stay identical to incrementForLevel() in
// functions/src/progression/progressionCalculator.ts. It previously used
// `ceil((level - 1) / 10) - 1`, which agrees with the backend everywhere
// EXCEPT the first level of each band (11, 21, 31, ...): the backend charges
// level 11 levelIncrements[1] while this charged levelIncrements[0], so every
// console-derived level above 10 drifted from the level the next completed run
// would recompute.
function incrementForLevel(
  level: number,
  increments: readonly number[],
): number {
  const bandIndex = Math.min(
    Math.floor((level - 1) / 10),
    increments.length - 1,
  );

  return increments[bandIndex] ?? increments[increments.length - 1] ?? 0;
}

export function levelForTotalXp(
  totalXp: number,
  config: ProgressionConfig = DEFAULT_PROGRESSION_CONFIG,
): number {
  const boundedTotalXp = Math.max(0, Math.floor(totalXp));
  const maxLevel = Math.max(1, Math.floor(config.maxLevel));
  const increments = config.levelIncrements;

  if (!Array.isArray(increments) || increments.length === 0) {
    return 1;
  }

  let level = 1;
  let cumulative = 0;

  for (let candidate = 2; candidate <= maxLevel; candidate += 1) {
    cumulative += incrementForLevel(candidate, increments);

    if (boundedTotalXp >= cumulative) {
      level = candidate;
    } else {
      break;
    }
  }

  return Math.min(level, maxLevel);
}

// Inverse of levelForTotalXp: the minimum totalXp that reaches `level` on the
// current curve. Used by the "Set Level" override so it can also backfill a
// consistent totalXp, since Cloud Functions treats totalXp as the sole source
// of truth and will otherwise recompute (and silently discard) a level-only
// override on the user's next completed run.
export function xpForLevel(
  level: number,
  config: ProgressionConfig = DEFAULT_PROGRESSION_CONFIG,
): number {
  const maxLevel = Math.max(1, Math.floor(config.maxLevel));
  const boundedLevel = Math.min(Math.max(1, Math.floor(level)), maxLevel);
  const increments = config.levelIncrements;

  if (!Array.isArray(increments) || increments.length === 0 || boundedLevel <= 1) {
    return 0;
  }

  let cumulative = 0;
  for (let candidate = 2; candidate <= boundedLevel; candidate += 1) {
    cumulative += incrementForLevel(candidate, increments);
  }

  return cumulative;
}

// League bands, mirroring the generated
// functions/src/progression/leaderboardLeagues.ts (regenerate that file with
// tools/leaderboard/generate_leaderboard_contracts.mjs; never hand-edit it).
// Only the fields a progression correction has to write are mirrored here.
const LEAGUE_BANDS: readonly {
  readonly tier: number;
  readonly key: string;
  readonly label: string;
  readonly minLevel: number;
  readonly maxLevel: number;
}[] = [
  { tier: 1, key: "tier_01", label: "Iron League", minLevel: 1, maxLevel: 10 },
  { tier: 2, key: "tier_02", label: "Bronze League", minLevel: 11, maxLevel: 20 },
  { tier: 3, key: "tier_03", label: "Silver League", minLevel: 21, maxLevel: 30 },
  { tier: 4, key: "tier_04", label: "Gold League", minLevel: 31, maxLevel: 40 },
  { tier: 5, key: "tier_05", label: "Platinum League", minLevel: 41, maxLevel: 50 },
  { tier: 6, key: "tier_06", label: "Emerald League", minLevel: 51, maxLevel: 60 },
  { tier: 7, key: "tier_07", label: "Diamond League", minLevel: 61, maxLevel: 70 },
  { tier: 8, key: "tier_08", label: "Master League", minLevel: 71, maxLevel: 80 },
  { tier: 9, key: "tier_09", label: "Grandmaster League", minLevel: 81, maxLevel: 90 },
  { tier: 10, key: "tier_10", label: "Challenger League", minLevel: 91, maxLevel: 100 },
];

function leagueForLevel(level: number) {
  const boundedLevel = Math.max(1, Math.min(100, Math.floor(level)));

  return (
    LEAGUE_BANDS.find(
      (league) => boundedLevel >= league.minLevel && boundedLevel <= league.maxLevel,
    ) ?? LEAGUE_BANDS[0]!
  );
}

// The display-only fields Cloud Functions recomputes on every completed run in
// profileProgressionData() (functions/src/progression/progressionAudit.ts).
// They are derived from totalXp, never authored independently.
export type ProgressionDisplayFields = {
  readonly divisionTier: number;
  readonly divisionKey: string;
  readonly divisionLabel: string;
  readonly levelLabel: string;
  readonly totalXpLabel: string;
  readonly monthlyXpLabel: string;
  readonly nextLevelXp: number | null;
  readonly xpToNextLevel: number | null;
  readonly levelProgressPercent: number;
};

// An admin correction that writes only totalXp/level/monthlyXp leaves the
// profile internally inconsistent — the app renders the *labels*, so a user
// corrected to 450 XP keeps showing "Level 4" and "350 XP" until their next
// completed run recomputes them. Deriving the same fields the backend derives,
// from the same curve, keeps the corrected profile coherent immediately.
//
// Mirrors resolveLevelProgression() field for field, including its two
// deliberate quirks: totalXpLabel is unseparated (`450 XP`) while monthlyXpLabel
// is locale-formatted (`1,200 XP`), and a maxed-out level reports null targets
// with 100% progress.
export function deriveProgressionDisplayFields(
  input: {
    readonly totalXp: number;
    readonly level: number;
    readonly monthlyXp: number;
  },
  config: ProgressionConfig = DEFAULT_PROGRESSION_CONFIG,
): ProgressionDisplayFields {
  const boundedTotalXp = Math.max(0, Math.floor(input.totalXp));
  const maxLevel = Math.max(1, Math.floor(config.maxLevel));
  const level = Math.min(Math.max(1, Math.floor(input.level)), maxLevel);
  const league = leagueForLevel(level);

  const currentLevelXp = xpForLevel(level, config);
  const nextLevelXp = level >= maxLevel ? null : xpForLevel(level + 1, config);
  const xpToNextLevel = nextLevelXp === null ? null : nextLevelXp - boundedTotalXp;
  const levelProgressPercent =
    nextLevelXp === null || nextLevelXp === currentLevelXp
      ? 100
      : Math.max(
          0,
          Math.min(
            100,
            Math.floor(
              ((boundedTotalXp - currentLevelXp) / (nextLevelXp - currentLevelXp)) * 100,
            ),
          ),
        );

  return {
    divisionTier: league.tier,
    divisionKey: league.key,
    divisionLabel: league.label,
    levelLabel: `Level ${level}`,
    totalXpLabel: `${boundedTotalXp} XP`,
    monthlyXpLabel: `${Math.max(0, Math.floor(input.monthlyXp)).toLocaleString("en-US")} XP`,
    nextLevelXp,
    xpToNextLevel,
    levelProgressPercent,
  };
}
