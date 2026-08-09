// Display-only leaderboard status copy. These strings describe empty,
// unranked, updating, and ineligible states for the UI. They never encode
// backend-owned rank, XP, or score values and must not be used for logic.

const String leaderboardEmptyStateTitle = 'No runners ranked here yet';

String leaderboardEmptyStateBody(String regionName) =>
    'Complete a run to be the first on the $regionName leaderboard!';

const String leaderboardUnrankedBody =
    'You are not ranked yet — finish a run this month to appear here.';

const String leaderboardUpdatingBody = "Preparing this month's leaderboard…";

const String leaderboardIneligibleBody =
    'Monthly ranking is not available for this account yet.';

const String leaderboardIneligibleMinRunsBody =
    'Complete more runs this month to join the monthly leaderboard.';
