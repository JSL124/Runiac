// Mirrors the level-up math in
// functions/src/progression/progressionCalculator.ts:159-172 (levelThresholds /
// incrementForLevel) so the admin console shows the SAME level curve the
// backend actually computes. Each entry of `levelIncrements` governs a
// LEVELS_PER_BAND-level band, not a single level-up: `incrementForLevel`
// picks the increment for `floor((level - 1) / LEVELS_PER_BAND)`, clamped to
// the last available increment once `maxLevel` needs more bands than there
// are increments. Pure module — no React/Firebase imports — so both the
// GamificationRules UI and the server-side live-data mapper can share it.

export const LEVELS_PER_BAND = 10;

// Guards the level-threshold loop below against a pathological `maxLevel`
// (NaN, Infinity, a huge admin-entered number) turning it into an unbounded
// or extremely slow loop. Real configs never approach this.
const MAX_SAFE_LEVEL = 100_000;

export type BandRange = {
  readonly index: number; // position in levelIncrements
  readonly firstLevel: number; // first level REACHED using this band's increment
  readonly lastLevel: number; // last level reached using it (clamped to maxLevel)
  readonly increment: number;
  readonly levelUpCount: number; // how many level-ups this band actually funds
  readonly thresholdAtLastLevel: number; // cumulative XP to reach lastLevel
};

function sanitizeMaxLevel(maxLevel: number): number {
  if (!Number.isFinite(maxLevel) || maxLevel < 1) {
    return 1;
  }
  return Math.min(Math.floor(maxLevel), MAX_SAFE_LEVEL);
}

// Exact mirror of incrementForLevel() in progressionCalculator.ts. An empty
// (or otherwise degenerate) increments array falls through the `??` chain to
// 0 rather than throwing, same as the backend's array-index-out-of-range
// behaviour in JS.
export function incrementForLevel(level: number, increments: readonly number[]): number {
  const bandIndex = Math.min(Math.floor((level - 1) / LEVELS_PER_BAND), increments.length - 1);
  return increments[bandIndex] ?? increments[increments.length - 1] ?? 0;
}

// Exact mirror of levelThresholds() in progressionCalculator.ts. Returns an
// array indexed by level - 1 (index 0 = level 1 = 0 XP), length = sanitized
// maxLevel. `maxLevel` is bounded defensively; `increments` values are used
// as-is (including any non-finite/non-positive entries) to stay faithful to
// what the backend would actually compute for the same stored config.
export function levelThresholds(increments: readonly number[], maxLevel: number): number[] {
  const safeMaxLevel = sanitizeMaxLevel(maxLevel);
  const thresholds: number[] = [0];

  for (let nextLevel = 2; nextLevel <= safeMaxLevel; nextLevel += 1) {
    const previousThreshold = thresholds[nextLevel - 2] ?? 0;
    thresholds.push(previousThreshold + incrementForLevel(nextLevel, increments));
  }

  return thresholds;
}

// Derives one display row per element of `levelIncrements`, describing the
// level range each increment actually funds once incrementForLevel's
// clamping is taken into account. Bands `maxLevel` never reaches are
// dropped; the last visible band absorbs every level up to `maxLevel`, even
// beyond its "natural" 10-level span, because that is the increment the
// backend keeps reusing once bandIndex clamps to the final entry.
export function bandRanges(increments: readonly number[], maxLevel: number): BandRange[] {
  const safeMaxLevel = sanitizeMaxLevel(maxLevel);

  if (increments.length === 0 || safeMaxLevel < 2) {
    return [];
  }

  const thresholds = levelThresholds(increments, safeMaxLevel);
  // Same clamped band index incrementForLevel(maxLevel, config) would use —
  // the last band an admin-visible level actually reaches.
  const finalBandIndex = Math.min(
    Math.floor((safeMaxLevel - 1) / LEVELS_PER_BAND),
    increments.length - 1,
  );

  const ranges: BandRange[] = [];

  for (let index = 0; index <= finalBandIndex; index += 1) {
    const naturalFirstLevel = index === 0 ? 2 : index * LEVELS_PER_BAND + 1;
    const naturalLastLevel = index * LEVELS_PER_BAND + LEVELS_PER_BAND;
    // The final visible band keeps applying through maxLevel regardless of
    // its natural 10-level span (that is the clamping behaviour itself);
    // earlier bands are capped at their natural end or maxLevel, whichever
    // is smaller.
    const lastLevel = index === finalBandIndex ? safeMaxLevel : Math.min(naturalLastLevel, safeMaxLevel);
    const firstLevel = Math.min(naturalFirstLevel, lastLevel);
    const levelUpCount = Math.max(0, lastLevel - firstLevel + 1);
    const increment = increments[index] ?? increments[increments.length - 1] ?? 0;
    const thresholdAtLastLevel = thresholds[lastLevel - 1] ?? 0;

    ranges.push({
      index,
      firstLevel,
      lastLevel,
      increment,
      levelUpCount,
      thresholdAtLastLevel,
    });
  }

  return ranges;
}
