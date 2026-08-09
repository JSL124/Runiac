import '../../../core/assets/runiac_assets.dart';

/// Resolves the trusted league (division) tier key (`tier_01`..`tier_10`) to its
/// badge asset. Display-only: the tier itself is always backend-owned; this only
/// maps a value the client already received to the artwork that represents it.
String leagueAssetPathForTierKey(String key) {
  return switch (key) {
    'tier_01' => RuniacAssets.leaderboardLeagueIron,
    'tier_02' => RuniacAssets.leaderboardLeagueBronze,
    'tier_03' => RuniacAssets.leaderboardLeagueSilver,
    'tier_04' => RuniacAssets.leaderboardLeagueGold,
    'tier_05' => RuniacAssets.leaderboardLeaguePlatinum,
    'tier_06' => RuniacAssets.leaderboardLeagueEmerald,
    'tier_07' => RuniacAssets.leaderboardLeagueDiamond,
    'tier_08' => RuniacAssets.leaderboardLeagueMaster,
    'tier_09' => RuniacAssets.leaderboardLeagueGrandmaster,
    'tier_10' => RuniacAssets.leaderboardLeagueChallenger,
    _ => RuniacAssets.leaderboardLeagueIron,
  };
}
