/// Names and verbs reserved for backend-owned Runiac values.
///
/// Flutter may display these outputs after approved read paths exist, but the
/// client must not become the source of truth for them.
class BackendOwnedValueContract {
  const BackendOwnedValueContract._();

  static const protectedFieldNames = <String>[
    'xp',
    'totalXp',
    'totalXP',
    'level',
    'divisionTier',
    'divisionKey',
    'divisionLabel',
    'levelLabel',
    'totalXpLabel',
    'nextLevelXp',
    'xpToNextLevel',
    'levelProgressPercent',
    'previousLevelProgressPercent',
    'nextLevelProgressPercent',
    'nextLevelXpTarget',
    'nextXpToNextLevel',
    'progressionUpdatedAt',
    'rank',
    'streak',
    'streakCount',
    'lastStreakRunDate',
    'streakUpdatedAt',
    'longestStreak',
    'longestStreakLabel',
    'totalDistanceMeters',
    'totalDistanceLabel',
    'leaderboardScore',
    'weeklyXp',
    'weeklyXP',
    'monthlyXp',
    'monthlyXP',
    'monthlyXpLabel',
    'monthlyPeriod',
    'monthlyXpBefore',
    'monthlyXpAfter',
    'subscriptionPrivilegeState',
    'validatedActivityContributionState',
    'countsTowardProgression',
  ];

  static const forbiddenClientMutationVerbs = <String>[
    'calculate',
    'derive',
    'aggregate',
    'validate',
    'award',
    'increment',
    'publish',
    'approve',
    'reject',
    'suspend',
  ];
}
