import 'home_guide_agent.dart';

/// On-device [HomeGuideAgent] that reads today's plan back and nothing else.
///
/// This is the guide a runner without the AI entitlement sees. It performs no
/// network I/O of any kind — no callable, no model, no OpenAI request — and is
/// deterministic for a given [HomeGuideRequest]: every line is composed from
/// plan copy the client already rendered on the stage map.
///
/// It deliberately does not coach, encourage, or interpret. The AI guide's
/// running tip and progression check-in are the paid part; what stays free is
/// the plan the runner already owns, stated plainly.
class PlanBriefHomeGuideAgent implements HomeGuideAgent {
  const PlanBriefHomeGuideAgent();

  /// How many plan steps the bubble lists. The speech bubble sits above the
  /// character in a bounded strip of the stage map, so a long interval session
  /// is truncated rather than allowed to grow the bubble without limit.
  static const int maxSteps = 6;

  /// Per-line and per-field bounds. Plan copy is already display-safe (it is
  /// rendered elsewhere on Home), so these only stop a pathological plan from
  /// overflowing the bubble.
  static const int _maxTitleRunes = 54;
  static const int _maxDayLabelRunes = 24;
  static const int _maxStepRunes = 80;

  @override
  bool get requiresDataConsent => false;

  @override
  Future<HomeGuideContent> explainTodayPlan(HomeGuideRequest request) async {
    return HomeGuidePlanBrief(text: _briefText(request));
  }

  String _briefText(HomeGuideRequest request) {
    if (request.isRestDay) {
      return _restDayLine(request);
    }
    final lines = <String>[_summaryLine(request), ..._stepLines(request)];
    return lines.join('\n');
  }

  /// Rest days state the fact and stop: no steps exist to list, and the copy
  /// stays factual rather than encouraging.
  String _restDayLine(HomeGuideRequest request) {
    final day = _label(request.dayLabel, _maxDayLabelRunes);
    return day.isEmpty
        ? 'Today is a rest day. No session is scheduled.'
        : "Today's $day is a rest day. No session is scheduled.";
  }

  String _summaryLine(HomeGuideRequest request) {
    final day = _label(request.dayLabel, _maxDayLabelRunes);
    final title = _label(request.workoutTitle, _maxTitleRunes, fallback: 'run');
    final durationPart = request.durationMinutes > 0
        ? ' for about ${request.durationMinutes} minutes'
        : '';
    final dayPart = day.isEmpty ? 'Today' : "Today's $day session";
    return '$dayPart is $title$durationPart.';
  }

  /// The plan's own breakdown, numbered and capped at [maxSteps]. A plan
  /// without steps yields none, leaving the summary line alone in the bubble.
  List<String> _stepLines(HomeGuideRequest request) {
    final steps = request.steps
        .map((step) => _bounded(step, _maxStepRunes))
        .where((step) => step.isNotEmpty)
        .take(maxSteps)
        .toList(growable: false);
    return <String>[
      for (var index = 0; index < steps.length; index += 1)
        '${index + 1}. ${steps[index]}',
    ];
  }

  String _bounded(String value, int maxRunes, {String fallback = ''}) {
    final trimmed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    final runes = trimmed.runes;
    return runes.length <= maxRunes
        ? trimmed
        : String.fromCharCodes(runes.take(maxRunes));
  }

  /// Strips sentence punctuation so an interpolated label cannot end the
  /// summary line early.
  String _label(String value, int maxRunes, {String fallback = ''}) {
    return _bounded(
      value.replaceAll(RegExp(r'[.!?。！？]'), ' '),
      maxRunes,
      fallback: fallback,
    );
  }
}
