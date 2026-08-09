/// Identifiers for the widgets the app tour can spotlight.
///
/// Each id corresponds to a `GlobalKey`/anchor registered by the widget it
/// names. This module has no widget dependency: it only names candidates for
/// the overlay layer to resolve at render time.
enum TutorialAnchorId {
  homeTodayStone,
  homeStoneCluster,
  homeLevelAvatar,
  homeMenuTrigger,
  bottomNavBar,
  feedPostList,
  feedFirstPost,
  leaderboardMap,
  leaderboardStateMessage,
  youSegmentedControl,
}

/// Shape of the cut-out spotlight hole around a resolved anchor.
enum TutorialHoleShape { rounded, circle }

/// Which side of the spotlight hole the character/speech bubble prefers.
enum TutorialCharacterSide { left, right }

/// A single step of the one-time, character-led app tour.
///
/// [tabIndex] refers to the shell's bottom-nav index, where 0=Home, 1=Feed,
/// 3=Leaderboard, 4=You. Index 2 (Run) is a pushed route, not a tab, so it is
/// never a valid [tabIndex] — the tour points at the Run button while staying
/// on Home.
class TutorialStep {
  const TutorialStep({
    required this.id,
    required this.tabIndex,
    required this.message,
    this.anchorCandidates = const [],
    this.bottomNavItemIndex,
    this.fallbackMessage = '',
    this.restDayMessage = '',
    this.holeShape = TutorialHoleShape.rounded,
    this.holePadding = 8,
    this.preferredSide = TutorialCharacterSide.left,
  });

  /// Stable, unique identifier for this step.
  final String id;

  /// Bottom-nav tab index this step should be shown on. Never 2 (Run).
  final int tabIndex;

  /// Primary narration copy shown by the character.
  final String message;

  /// Ordered list of anchors to try resolving against the live widget tree.
  /// The first one that resolves wins.
  final List<TutorialAnchorId> anchorCandidates;

  /// When set, this step also highlights a specific bottom-nav item (e.g. the
  /// Run button) rather than (or in addition to) an anchor above the bar.
  final int? bottomNavItemIndex;

  /// Copy to show when none of [anchorCandidates] resolve. Empty means reuse
  /// [message].
  final String fallbackMessage;

  /// Copy to show instead of [message] when today is a scheduled rest day.
  /// Empty means this step has no rest-day variant, so [message] is always
  /// used regardless of whether today is a rest day. Never branches
  /// [fallbackMessage]: an unresolved anchor already has its own generic,
  /// rest/run-agnostic copy, so a rest day never changes which fallback
  /// string is shown.
  final String restDayMessage;

  /// Shape of the cut-out spotlight hole.
  final TutorialHoleShape holeShape;

  /// Padding, in logical pixels, added around the resolved anchor bounds
  /// before cutting the spotlight hole.
  final double holePadding;

  /// Preferred side for the character/speech bubble relative to the hole.
  final TutorialCharacterSide preferredSide;

  /// Copy to actually render: [fallbackMessage] when non-empty, else
  /// [message].
  String get effectiveFallbackMessage =>
      fallbackMessage.isEmpty ? message : fallbackMessage;

  /// Copy to render when an anchor resolved (i.e. [effectiveFallbackMessage]
  /// is not in play): [restDayMessage] when [isRestDay] is true and this step
  /// defines one, else [message] unchanged. `isRestDay` is a tri-state signal
  /// upstream (null means "unknown"), so callers pass `false` for both "not a
  /// rest day" and "unknown" — a step never guesses at rest-day copy from an
  /// unresolved signal.
  String effectiveMessage({required bool isRestDay}) {
    return isRestDay && restDayMessage.isNotEmpty ? restDayMessage : message;
  }
}
