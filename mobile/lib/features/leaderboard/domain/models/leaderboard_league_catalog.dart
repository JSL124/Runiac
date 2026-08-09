// GENERATED FILE. Run: node tools/leaderboard/generate_leaderboard_contracts.mjs
class LeaderboardLeagueDefinition {
  const LeaderboardLeagueDefinition({
    required this.tier,
    required this.key,
    required this.name,
    required this.label,
    required this.minLevel,
    required this.maxLevel,
  });

  final int tier;
  final String key;
  final String name;
  final String label;
  final int minLevel;
  final int maxLevel;

  String get levelRangeLabel => 'Lv.$minLevel - Lv.$maxLevel';
}

const leaderboardLeagueDefinitions = <LeaderboardLeagueDefinition>[
  LeaderboardLeagueDefinition(
    tier: 1,
    key: 'tier_01',
    name: 'Iron',
    label: 'Iron League',
    minLevel: 1,
    maxLevel: 10,
  ),
  LeaderboardLeagueDefinition(
    tier: 2,
    key: 'tier_02',
    name: 'Bronze',
    label: 'Bronze League',
    minLevel: 11,
    maxLevel: 20,
  ),
  LeaderboardLeagueDefinition(
    tier: 3,
    key: 'tier_03',
    name: 'Silver',
    label: 'Silver League',
    minLevel: 21,
    maxLevel: 30,
  ),
  LeaderboardLeagueDefinition(
    tier: 4,
    key: 'tier_04',
    name: 'Gold',
    label: 'Gold League',
    minLevel: 31,
    maxLevel: 40,
  ),
  LeaderboardLeagueDefinition(
    tier: 5,
    key: 'tier_05',
    name: 'Platinum',
    label: 'Platinum League',
    minLevel: 41,
    maxLevel: 50,
  ),
  LeaderboardLeagueDefinition(
    tier: 6,
    key: 'tier_06',
    name: 'Emerald',
    label: 'Emerald League',
    minLevel: 51,
    maxLevel: 60,
  ),
  LeaderboardLeagueDefinition(
    tier: 7,
    key: 'tier_07',
    name: 'Diamond',
    label: 'Diamond League',
    minLevel: 61,
    maxLevel: 70,
  ),
  LeaderboardLeagueDefinition(
    tier: 8,
    key: 'tier_08',
    name: 'Master',
    label: 'Master League',
    minLevel: 71,
    maxLevel: 80,
  ),
  LeaderboardLeagueDefinition(
    tier: 9,
    key: 'tier_09',
    name: 'Grandmaster',
    label: 'Grandmaster League',
    minLevel: 81,
    maxLevel: 90,
  ),
  LeaderboardLeagueDefinition(
    tier: 10,
    key: 'tier_10',
    name: 'Challenger',
    label: 'Challenger League',
    minLevel: 91,
    maxLevel: 100,
  ),
];

LeaderboardLeagueDefinition? leaderboardLeagueForKey(String value) {
  final key = value.trim();
  for (final league in leaderboardLeagueDefinitions) {
    if (league.key == key) {
      return league;
    }
  }
  return null;
}
