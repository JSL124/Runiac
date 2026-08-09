import 'package:flutter/foundation.dart';

/// Immutable, display-only description of today's workout, used to ask the
/// Home guide character to explain the plan in friendly copy.
///
/// Every field here is read back from a plan the client already rendered
/// (title, duration, steps, coach copy); nothing is backend-owned progression
/// data (no XP, level, rank, streak, or leaderboard value is carried here or
/// derivable from it).
///
/// When [isRestDay] is true the request describes a scheduled rest day rather
/// than a workout: the workout fields ([workoutTitle], [durationMinutes],
/// [intensityLabel], [description], [steps], [supportiveNote]) are empty and
/// the guide composes rest-day encouragement instead of a workout summary.
@immutable
class HomeGuideRequest {
  const HomeGuideRequest({
    required this.planTitle,
    required this.weekNumber,
    required this.weekFocus,
    required this.dayLabel,
    required this.workoutTitle,
    required this.durationMinutes,
    required this.intensityLabel,
    required this.description,
    this.steps = const <String>[],
    this.supportiveNote = '',
    this.isRestDay = false,
  });

  /// Title of the active generated plan (e.g. `'First 10K Preparation'`).
  final String planTitle;

  /// 1-based plan week number today's workout belongs to.
  final int weekNumber;

  /// Short focus line for the active week (e.g. `'Build a steady habit'`).
  final String weekFocus;

  /// Weekday or positional day caption for today's stage (e.g. `'Mon'`).
  final String dayLabel;

  /// Title of today's workout (e.g. `'Easy Run'`).
  final String workoutTitle;

  /// Planned duration of today's workout, in minutes.
  final int durationMinutes;

  /// Human-readable effort label (e.g. `'Gentle'`, `'Balanced'`).
  final String intensityLabel;

  /// Short description of the workout.
  final String description;

  /// Ordered breakdown steps for the workout, when available.
  final List<String> steps;

  /// Encouraging coach note attached to the workout, when available.
  final String supportiveNote;

  /// True when today is a scheduled rest day (no run session). The guide
  /// composes rest-day encouragement instead of a workout summary; the
  /// workout fields are empty in this case.
  final bool isRestDay;
}

/// The named messages the guide can present.
///
/// These values deliberately describe presentation purpose, not progression
/// state. The client receives already-rendered copy and never calculates any
/// activity, XP, rank, streak, or other protected value.
///
/// [planSummary], [runningTip], and [progressionCheckIn] are the three slots of
/// the AI guide's tap-to-advance cycle. [planBrief] is the single, complete
/// plan read-out composed on-device by [PlanBriefHomeGuideAgent]; it is one
/// message rather than a slot in a cycle, so it carries newlines and is not
/// advanced past.
enum HomeGuideMessageKind {
  planSummary,
  runningTip,
  progressionCheckIn,
  planBrief,
}

/// A short, friendly guide message explaining one part of today's plan.
@immutable
class HomeGuideMessage {
  const HomeGuideMessage({
    required this.kind,
    required this.text,
    this.isFromRemoteAgent = false,
  });

  /// The fixed purpose of this message in the three-message guide bundle.
  final HomeGuideMessageKind kind;

  /// Beginner-friendly copy to render inside the guide character's speech
  /// bubble.
  final String text;

  /// True when [text] came from the remote Cloud Function-backed agent
  /// rather than the local rule-based fallback. Display/debug metadata only.
  final bool isFromRemoteAgent;
}

/// Everything the speech bubble needs to present one Home guide answer.
///
/// The bubble presents [messages] in order, one at a time, and only offers a
/// tap-to-advance affordance when there is more than one. That is the whole
/// contract: a three-slot AI cycle ([HomeGuideBundle]) and a single-message
/// on-device plan read-out ([HomeGuidePlanBrief]) are both valid content, and
/// the presentation layer does not care which it received.
abstract interface class HomeGuideContent {
  /// The ordered presentation sequence. Never empty, never mutable.
  List<HomeGuideMessage> get messages;
}

/// Immutable, complete guide content for one Home request.
///
/// [HomeGuideBundle] extends [HomeGuideMessage] temporarily so the existing
/// stage-map seam can render [planSummary] until its dedicated cycle migration
/// consumes [messages]. The named fields remain the only source of content
/// for new callers.
@immutable
class HomeGuideBundle extends HomeGuideMessage implements HomeGuideContent {
  HomeGuideBundle({
    required this.planSummary,
    required this.runningTip,
    required this.progressionCheckIn,
    required super.isFromRemoteAgent,
  }) : assert(planSummary.kind == HomeGuideMessageKind.planSummary),
       assert(runningTip.kind == HomeGuideMessageKind.runningTip),
       assert(
         progressionCheckIn.kind == HomeGuideMessageKind.progressionCheckIn,
       ),
       super(kind: HomeGuideMessageKind.planSummary, text: planSummary.text);

  /// Strict constructor used at the network boundary. It rejects, rather than
  /// truncates, copy that would overflow the approved compact bubble contract.
  static HomeGuideBundle? tryCreate({
    required String planSummary,
    required String runningTip,
    required String progressionCheckIn,
    required bool isFromRemoteAgent,
  }) {
    // The progression line may carry server-computed comparison figures (e.g.
    // "+2.5 km, +50% vs last week"), so it is allowed a little more length and
    // an extra clause than the plan-summary and running-tip lines.
    if (!_isDisplaySafe(planSummary) ||
        !_isDisplaySafe(runningTip) ||
        !_isDisplaySafe(
          progressionCheckIn,
          maxRunes: _progressionMaxRunes,
          maxSentences: _progressionMaxSentences,
        )) {
      return null;
    }
    final normalizedPlanSummary = _normalizedPurpose(planSummary);
    final normalizedRunningTip = _normalizedPurpose(runningTip);
    final normalizedProgressionCheckIn = _normalizedPurpose(progressionCheckIn);
    if (normalizedPlanSummary == normalizedRunningTip ||
        normalizedPlanSummary == normalizedProgressionCheckIn ||
        normalizedRunningTip == normalizedProgressionCheckIn) {
      return null;
    }
    return HomeGuideBundle(
      planSummary: HomeGuideMessage(
        kind: HomeGuideMessageKind.planSummary,
        text: planSummary,
        isFromRemoteAgent: isFromRemoteAgent,
      ),
      runningTip: HomeGuideMessage(
        kind: HomeGuideMessageKind.runningTip,
        text: runningTip,
        isFromRemoteAgent: isFromRemoteAgent,
      ),
      progressionCheckIn: HomeGuideMessage(
        kind: HomeGuideMessageKind.progressionCheckIn,
        text: progressionCheckIn,
        isFromRemoteAgent: isFromRemoteAgent,
      ),
      isFromRemoteAgent: isFromRemoteAgent,
    );
  }

  /// Summary copy, shown first when the character guide opens.
  final HomeGuideMessage planSummary;

  /// A single actionable running cue, shown second.
  final HomeGuideMessage runningTip;

  /// A calm evidence-backed or baseline check-in, shown third.
  final HomeGuideMessage progressionCheckIn;

  /// The ordered presentation sequence. The returned list cannot be mutated.
  @override
  List<HomeGuideMessage> get messages => List<HomeGuideMessage>.unmodifiable(
    <HomeGuideMessage>[planSummary, runningTip, progressionCheckIn],
  );

  /// Default compact bubble limits for the plan-summary and running-tip lines.
  static const int _defaultMaxRunes = 160;
  static const int _defaultMaxSentences = 2;

  /// Relaxed limits for the progression line, which may include comparison
  /// figures and a short "what to improve" clause.
  static const int _progressionMaxRunes = 220;
  static const int _progressionMaxSentences = 3;

  static bool _isDisplaySafe(
    String text, {
    int maxRunes = _defaultMaxRunes,
    int maxSentences = _defaultMaxSentences,
  }) {
    if (text.isEmpty || text != text.trim() || text.contains('\n')) {
      return false;
    }
    if (text.runes.length > maxRunes) {
      return false;
    }
    return _sentenceEndingPattern.allMatches(text).length <= maxSentences;
  }

  static final RegExp _sentenceEndingPattern = RegExp(r'[.!?。！？]+');

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static String _normalizedPurpose(String text) =>
      text.toLowerCase().replaceAll(_whitespacePattern, ' ');
}

/// A single message that reads today's plan back to the runner.
///
/// One message, not a cycle: the summary line and the plan's own steps are
/// presented together, so the bubble shows everything at once and offers no
/// tap-to-advance affordance. [text] therefore contains newlines, which the
/// strict [HomeGuideBundle.tryCreate] contract forbids for cycle copy.
///
/// Every character is composed on-device from [HomeGuideRequest] display copy
/// the client already rendered. Nothing is sent anywhere, so this content
/// needs no data-use consent and no model call.
@immutable
class HomeGuidePlanBrief implements HomeGuideContent {
  HomeGuidePlanBrief({required String text})
    : _message = HomeGuideMessage(
        kind: HomeGuideMessageKind.planBrief,
        text: text,
      );

  final HomeGuideMessage _message;

  /// The composed plan read-out, summary line first.
  HomeGuideMessage get brief => _message;

  @override
  List<HomeGuideMessage> get messages =>
      List<HomeGuideMessage>.unmodifiable(<HomeGuideMessage>[_message]);
}

/// Seam for the Home guide "brain" that explains today's plan.
///
/// The API is [Future]-based so a remote implementation fits without
/// changing callers. [CloudFunctionHomeGuideAgent] (see
/// `cloud_function_home_guide_agent.dart`) calls a Cloud Function proxy that
/// holds the OpenAI API key server-side only; the client must never embed an
/// API key or call the OpenAI API directly. [RuleBasedHomeGuideAgent] is the
/// offline, deterministic default and the fallback whenever the remote agent
/// is unavailable, errors, or returns an unusable response.
/// [PlanBriefHomeGuideAgent] is the on-device plan read-out shown to runners
/// who are not entitled to the AI guide.
abstract interface class HomeGuideAgent {
  /// Produces the complete guide content for the workout described by
  /// [request].
  Future<HomeGuideContent> explainTodayPlan(HomeGuideRequest request);

  /// Whether this guide sends run data to the AI provider and therefore needs
  /// the runner's personalized-guide data-use consent before it may run.
  ///
  /// False for every on-device guide. The Home surface reads this instead of
  /// gating the bubble on consent unconditionally, so a runner who never
  /// granted consent still sees a locally composed plan read-out — the
  /// consent decision governs the AI guide only, which is what its disclosure
  /// describes.
  bool get requiresDataConsent;
}
