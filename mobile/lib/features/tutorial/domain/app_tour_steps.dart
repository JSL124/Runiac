import '../../../core/characters/runner_character.dart';
import 'models/tutorial_step.dart';

/// The one-time, character-led app tour shown to a brand-new user after
/// onboarding. Steps run in this exact order and walk Home, Feed,
/// Leaderboard, and You. The Run button (bottom-nav index 2) is highlighted
/// from Home rather than by navigating to a `tabIndex` of 2, since Run is a
/// pushed route, not a tab.
const List<TutorialStep> runiacAppTourSteps = [
  TutorialStep(
    id: 'welcome',
    tabIndex: 0,
    message:
        "Hi, I'm {guide} — your running buddy. Give me 30 seconds and I'll "
        'show you around.',
  ),
  TutorialStep(
    id: 'home-today-stone',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.homeTodayStone],
    message:
        "This is today's stone — where you are in your plan right now.",
    fallbackMessage:
        "Your plan appears here as a path of stones once it's ready.",
    restDayMessage:
        "This is today's stone — your plan has you resting today, and "
        "that's on purpose.",
    holeShape: TutorialHoleShape.circle,
  ),
  TutorialStep(
    id: 'home-stone-days',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.homeStoneCluster],
    message:
        'Each stone is one day of your plan — running days and rest days '
        "in the order you'll do them.",
    fallbackMessage:
        'Your plan lays out one stone per day — some for running, some '
        'for resting.',
    restDayMessage:
        "Each stone is one day of your plan. Today's is a rest day; your "
        'running days sit further along the path.',
  ),
  TutorialStep(
    id: 'home-rest-streak',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.homeStoneCluster],
    message:
        'Rest days are part of the plan, not a break from it. They '
        "won't break your streak — only skipping a running day does.",
    fallbackMessage:
        'Rest days are planned, not lost days. Only skipping a running '
        'day resets your streak.',
    restDayMessage:
        'Today is one of those rest days. It won\'t break your streak — '
        'only skipping a running day does.',
  ),
  TutorialStep(
    id: 'home-stone-detail',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.homeTodayStone],
    message:
        "Tap today's stone to open your workout and see what it asks "
        'of you before you start.',
    fallbackMessage:
        "Once your plan is ready, today's running stone opens that day's "
        'workout.',
    restDayMessage:
        'Nothing to open today — when a running day comes round, its '
        "stone opens that day's workout.",
    holeShape: TutorialHoleShape.circle,
  ),
  TutorialStep(
    id: 'home-level-avatar',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.homeLevelAvatar],
    message:
        'Your level ring and photo sit up here. The ring fills up as your '
        'finished runs earn XP.',
    holeShape: TutorialHoleShape.circle,
  ),
  TutorialStep(
    id: 'home-menu',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.homeMenuTrigger],
    message:
        'Menu keeps your streak, notifications, friends and challenges '
        'together. Everything social starts here.',
  ),
  TutorialStep(
    id: 'run-button',
    tabIndex: 0,
    anchorCandidates: [TutorialAnchorId.bottomNavBar],
    bottomNavItemIndex: 2,
    message:
        "This is the Run button — your one tap to start a run. I won't "
        'start one right now, so keep exploring.',
    fallbackMessage:
        'The middle button on the bar below starts a run whenever '
        "you're ready.",
    holeShape: TutorialHoleShape.circle,
    preferredSide: TutorialCharacterSide.right,
  ),
  TutorialStep(
    id: 'feed',
    tabIndex: 1,
    anchorCandidates: [
      TutorialAnchorId.feedFirstPost,
      TutorialAnchorId.feedPostList,
    ],
    message:
        "Feed is where your finished runs show up next to your friends'. "
        'Drop them a cheer when they post.',
  ),
  TutorialStep(
    id: 'leaderboard',
    tabIndex: 3,
    anchorCandidates: [
      TutorialAnchorId.leaderboardMap,
      TutorialAnchorId.leaderboardStateMessage,
    ],
    message:
        'Every month, runners near you are ranked here by the XP you earn. '
        'Your league badge sits at the top.',
    fallbackMessage:
        "Pick your planning area in your profile and you'll join your "
        "city's monthly XP ranking.",
    preferredSide: TutorialCharacterSide.right,
  ),
  TutorialStep(
    id: 'you',
    tabIndex: 4,
    anchorCandidates: [TutorialAnchorId.youSegmentedControl],
    message:
        "You holds everything about you — Progress for what you've run, "
        "Plans for what's next.",
  ),
  TutorialStep(
    id: 'finish',
    tabIndex: 0,
    message:
        "That's the whole app. The first run is the hardest one — I'll be "
        'waiting on the map.',
  ),
];

/// Substitutes every `{guide}` occurrence in [template] with
/// [character]'s display name.
String resolveTutorialCopy(String template, RunnerCharacter character) {
  return template.replaceAll('{guide}', character.displayName);
}
