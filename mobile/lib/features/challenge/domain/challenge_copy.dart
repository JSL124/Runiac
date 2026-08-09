/// Canonical English Challenge copy (user-approved 2026-07-13).
///
/// These are the single source of truth for the locked copy strings from the
/// `challenge-distance-system` capsule. Difficulty labels are NOT listed here:
/// they come from the backend catalog verbatim (`ChallengeTier.difficultyLabel`
/// / `ChallengeRulesSnapshot.difficultyLabel`). Widgets reference these
/// constants instead of inlining literals.
abstract final class ChallengeCopy {
  static const startChallenge = 'Start challenge';
  static const timeLeft = 'Time left';

  /// Full settling message (Progress / Result surfaces).
  static const calculatingResults = 'Calculating results…';

  /// Short settling message (Home active control).
  static const calculating = 'Calculating…';

  static const alreadyHaveChallengeInProgress =
      'You already have a challenge in progress';
  static const viewCurrentChallenge = 'View current challenge';
  static const leaveChallenge = 'Leave challenge';
  static const abandonChallenge = 'Abandon challenge';
  static const leftTheChallenge = 'Left the challenge';
  static const soloChallenge = 'Solo challenge';
  static const personalMinimumNotReached = 'Personal minimum not reached';

  /// `Personal minimum X km`, where X is a display-only kilometre figure.
  static String personalMinimum(String kilometresLabel) =>
      'Personal minimum $kilometresLabel km';

  // --- Hub / navigation ---
  static const challengeTitle = 'Challenge';
  static const invitationsTitle = 'Invitations';
  static const historyTitle = 'History';
  static const createChallenge = 'Create challenge';
  static const inProgress = 'In progress';
  static const earned = 'Earned';

  /// Chip/semantics label for a premium-gated tier (display-only lock UI; the
  /// backend `PREMIUM_REQUIRED` gate on lobby creation is the enforcement).
  static const premiumTier = 'Premium';

  // --- Premium-lapse grace window ---
  // Shown while the runner is inside the server's 24h grace window after their
  // subscription lapsed on a premium-only tier. The wording promises nothing
  // the backend does not guarantee: removal is what happens when the window
  // closes, and renewing before then keeps everything.
  static const premiumLapseTitle = 'Premium ended';

  /// `Renew within X to stay in this challenge. …`
  static String premiumLapseBody(String remainingLabel) =>
      'Renew within $remainingLabel to stay in this challenge. '
      'Otherwise you will be removed and stop earning towards this badge.';

  /// Used once less than a minute is left, where a countdown would imply more
  /// precision than the one-minute sweep can honour.
  static const premiumLapseImminentBody =
      'You will be removed from this challenge shortly. '
      'Renew Premium now to stay in it.';
  static const premiumLapseCta = 'Keep Premium';

  // --- Explore / states ---
  static const exploreLoading = 'Loading challenges…';
  static const exploreError = 'Challenges are temporarily unavailable.';
  static const tryAgain = 'Try again';

  // --- Rules card labels ---
  static const ruleTargetDistance = 'Target distance';
  static const ruleDuration = 'Duration';
  static const ruleParticipants = 'Participants';
  static const rulePersonalMinimum = 'Personal minimum';
  static const ruleGroupGoal = 'Group goal';
  static const groupCombinedRule =
      "The team's combined distance must reach the target";

  /// `Up to N runners`.
  static String participantsRule(int maxParticipants) =>
      'Up to $maxParticipants runners';

  /// `1 week` / `N weeks` from a whole-week duration in days.
  static String durationWeeksLabel(int durationDays) {
    final weeks = (durationDays / 7).round();
    return weeks == 1 ? '1 week' : '$weeks weeks';
  }

  /// `Each runner must run at least X km`.
  static String personalMinimumRule(String kilometresLabel) =>
      'Each runner must run at least $kilometresLabel';

  /// `Running solo? You'll run the full X km yourself.`
  static String soloWarning(String kilometresLabel) =>
      "Running solo? You'll run the full $kilometresLabel yourself.";

  // --- Lobby ---
  static String lobbyClosesIn(String hms) => 'Lobby closes in $hms';
  static const lobbyExpiredTitle = 'This lobby expired';
  static const inviteFriends = 'Invite friends';
  static const cancelChallenge = 'Cancel challenge';
  static const leaveLobby = 'Leave lobby';
  static const waitingForOwner = 'Waiting for the owner to start';

  /// Owner subtitle when the current user is themselves the owner.
  static const ownerSelfLabel = 'You · Owner';

  /// Owner subtitle other participants see for the owner's row.
  static const ownerLabel = 'Owner';

  /// Subtitle marking the current user's own (non-owner) row.
  static const youLabel = 'You';
  static const chipPending = 'Pending';
  static const chipAccepted = 'Accepted';
  static const chipDeclined = 'Declined';

  /// `Invited N of M` — used by the friend picker for selection progress.
  static String invitedOf(int count, int cap) => 'Invited $count of $cap';

  /// Roster headcount `count/cap` — current people in the lobby (owner
  /// included) over the maximum the challenge allows.
  static String lobbyHeadcount(int count, int cap) => '$count/$cap';

  static const startSoloConfirm = 'Start solo — no one has joined yet.';
  static String startGroupConfirm(int runners) =>
      'Start with $runners runners — unanswered invitations will expire.';
  static const cancelChallengeConfirm =
      'Cancel this challenge for everyone? This cannot be undone.';

  // --- Friend picker ---
  static const inviteLimitReached = 'Invite limit reached';
  static const addFriendsToInvite = 'Add friends to invite them';

  // --- Invitations ---
  static String expiresIn(String hms) => 'Expires in $hms';
  static const invitationsEmpty = 'No invitations right now';
  static const accept = 'Accept';
  static const decline = 'Decline';

  // --- Results (full-screen, five variants) ---
  static const resultDone = 'Done';
  static const resultViewBadgeCollection = 'View badge collection';

  /// SUCCEEDED — `You earned the 10K badge!` (tier title verbatim).
  static String badgeEarnedHeadline(String tierTitle) =>
      'You earned the $tierTitle badge!';
  static const badgeEarnedSubtitle =
      'Your badge is now in your collection.';

  /// INELIGIBLE — team reached the target but the caller missed the personal
  /// minimum. All km figures are display-only labels (already `X.X km`).
  static const minimumMissedTitle = 'Team goal reached';
  static String minimumMissedBody({
    required String targetLabel,
    required String mineLabel,
    required String minimumLabel,
  }) =>
      'The team reached $targetLabel — but your $mineLabel '
      "didn't reach the $minimumLabel personal minimum, so no badge this time.";
  static String stillAddedSupport(String mineLabel) =>
      'You still added $mineLabel to the team.';

  /// FAILED — deadline passed without the target.
  static const deadlineFailedTitle = 'Time ran out';
  static String deadlineFailedBody({
    required String teamLabel,
    required String targetLabel,
  }) =>
      'Time ran out at $teamLabel of $targetLabel. No badges this time.';

  /// CANCELLED — owner abandoned the challenge for everyone.
  static const resultCancelledTitle = 'Challenge cancelled';
  static const resultCancelledBody =
      'The owner cancelled this challenge before it finished. '
      'No badges this time.';

  /// LEFT — the caller left; their metres stayed with the team.
  static const resultLeftTitle = 'You left the challenge';
  static String resultLeftBody(String mineLabel) =>
      'You left the challenge. Your $mineLabel stayed with the team, '
      'and no badge was awarded.';

  // --- History ---
  static const historyEmpty = 'No finished challenges yet';
  static const historyLoading = 'Loading history…';
  static const historyError = 'History is temporarily unavailable.';
  static const outcomeBadgeEarned = 'Badge earned';
  static const outcomeMinimumMissed = 'Minimum missed';
  static const outcomeFailed = 'Failed';
  static const outcomeCancelled = 'Cancelled';
  static const outcomeLeft = 'Left';

  /// Maps a backend `CHALLENGE_REASON` code (or transport code) to friendly
  /// user copy. Unknown codes fall through to a generic retry message so a
  /// new server reason never surfaces a raw code to the user.
  static String failureMessage(String reason) {
    return switch (reason) {
      'ALREADY_HOLDS_SLOT' => alreadyHaveChallengeInProgress,
      'LOBBY_FULL' => 'This lobby is full.',
      'LOBBY_EXPIRED' => 'This lobby has expired.',
      'LOBBY_NOT_RECRUITING' => 'This lobby is no longer open.',
      'NOT_RECIPROCAL_FRIEND' ||
      'INVITEE_NOT_RECIPROCAL_FRIEND' =>
        'You can only invite friends who added you back.',
      'NOT_CHALLENGE_OWNER' ||
      'NOT_LOBBY_OWNER' =>
        'Only the challenge owner can do that.',
      'OWNER_CANNOT_LEAVE' =>
        'Owners cannot leave — abandon the challenge instead.',
      'INVITE_CAPACITY_EXCEEDED' =>
        'You have reached the invite limit for this challenge.',
      'INVITEE_ALREADY_PARTICIPANT' => 'That runner is already in the lobby.',
      'INVITEE_BLOCKED' => 'You cannot invite that runner.',
      'CANNOT_INVITE_SELF' => 'You cannot invite yourself.',
      'CHALLENGE_NOT_FOUND' => 'This challenge is no longer available.',
      'CHALLENGE_NOT_ACTIVE' => 'This challenge is no longer active.',
      'INVITATION_NOT_FOUND' => 'This invitation is no longer available.',
      'NOT_INVITATION_RECIPIENT' => 'This invitation is not addressed to you.',
      'INVITATION_NOT_PENDING' => 'This invitation has already been answered.',
      'UNKNOWN_TIER' => 'This challenge tier is unavailable.',
      'PREMIUM_REQUIRED' => 'This challenge tier is part of Runiac Premium.',
      'UNAUTHENTICATED' => 'Please sign in to continue.',
      'CHALLENGE_UNAVAILABLE' => 'Challenge is temporarily unavailable.',
      _ => 'Something went wrong. Please try again.',
    };
  }
}
