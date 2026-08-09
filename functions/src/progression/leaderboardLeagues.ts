// GENERATED FILE. Run: node tools/leaderboard/generate_leaderboard_contracts.mjs
export const leaderboardLeagueDefinitions = [
  {
    "tier": 1,
    "key": "tier_01",
    "name": "Iron",
    "label": "Iron League",
    "minLevel": 1,
    "maxLevel": 10
  },
  {
    "tier": 2,
    "key": "tier_02",
    "name": "Bronze",
    "label": "Bronze League",
    "minLevel": 11,
    "maxLevel": 20
  },
  {
    "tier": 3,
    "key": "tier_03",
    "name": "Silver",
    "label": "Silver League",
    "minLevel": 21,
    "maxLevel": 30
  },
  {
    "tier": 4,
    "key": "tier_04",
    "name": "Gold",
    "label": "Gold League",
    "minLevel": 31,
    "maxLevel": 40
  },
  {
    "tier": 5,
    "key": "tier_05",
    "name": "Platinum",
    "label": "Platinum League",
    "minLevel": 41,
    "maxLevel": 50
  },
  {
    "tier": 6,
    "key": "tier_06",
    "name": "Emerald",
    "label": "Emerald League",
    "minLevel": 51,
    "maxLevel": 60
  },
  {
    "tier": 7,
    "key": "tier_07",
    "name": "Diamond",
    "label": "Diamond League",
    "minLevel": 61,
    "maxLevel": 70
  },
  {
    "tier": 8,
    "key": "tier_08",
    "name": "Master",
    "label": "Master League",
    "minLevel": 71,
    "maxLevel": 80
  },
  {
    "tier": 9,
    "key": "tier_09",
    "name": "Grandmaster",
    "label": "Grandmaster League",
    "minLevel": 81,
    "maxLevel": 90
  },
  {
    "tier": 10,
    "key": "tier_10",
    "name": "Challenger",
    "label": "Challenger League",
    "minLevel": 91,
    "maxLevel": 100
  }
] as const;

export type LeaderboardLeagueDefinition = (typeof leaderboardLeagueDefinitions)[number];

export function leaderboardLeagueForLevel(level: number): LeaderboardLeagueDefinition {
  const boundedLevel = Math.max(1, Math.min(100, Math.floor(level)));
  return (
    leaderboardLeagueDefinitions.find(
      (league) => boundedLevel >= league.minLevel && boundedLevel <= league.maxLevel,
    ) ?? leaderboardLeagueDefinitions[0]
  );
}

export function leaderboardLeagueForKey(
  key: unknown,
): LeaderboardLeagueDefinition | null {
  if (typeof key !== "string") {
    return null;
  }
  return leaderboardLeagueDefinitions.find((league) => league.key === key.trim()) ?? null;
}
