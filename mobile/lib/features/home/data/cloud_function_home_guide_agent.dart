import 'package:cloud_functions/cloud_functions.dart';

import '../domain/guide/home_guide_agent.dart';
import '../domain/guide/rule_based_home_guide_agent.dart';

/// Injectable callable boundary used by the adapter and deterministic tests.
typedef HomeGuideCallable =
    Future<Object?> Function(Map<String, Object?> payload);

/// Remote [HomeGuideAgent] backed by the `homeGuideAgent` Cloud Function.
///
/// The callable is expected to run an OpenAI/LangGraph-backed agent whose API
/// key is held server-side only; this client adapter never embeds an API key
/// and never calls OpenAI directly. Every request field is display-only plan
/// copy (see [HomeGuideRequest]) — no backend-owned XP/level/streak/rank/
/// leaderboard value is sent or requested.
///
/// This adapter never throws to its caller: any network failure, callable
/// error, or unusable response is composed into a message by delegating to
/// [fallbackAgent] (the offline, deterministic [RuleBasedHomeGuideAgent] by
/// default), mirroring the fallback behavior expected of the guide seam.
class CloudFunctionHomeGuideAgent implements HomeGuideAgent {
  CloudFunctionHomeGuideAgent({
    FirebaseFunctions? functions,
    HomeGuideCallable? callable,
    this.fallbackAgent = const RuleBasedHomeGuideAgent(),
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
           );

  final HomeGuideCallable _callable;

  /// Local agent used whenever the remote callable is unavailable, errors,
  /// or returns a response this adapter cannot use.
  final HomeGuideAgent fallbackAgent;

  /// True: this adapter sends recent-run-derived plan context to the server,
  /// which forwards it to the AI provider, so the Home surface must not run it
  /// without the runner's personalized-guide consent.
  @override
  bool get requiresDataConsent => true;

  @override
  Future<HomeGuideContent> explainTodayPlan(HomeGuideRequest request) async {
    // Rest days carry no workout copy; the remote callable is built around
    // workout summaries, so compose the rest-day bundle locally instead of
    // sending an empty-workout request to the server.
    if (request.isRestDay) {
      return fallbackAgent.explainTodayPlan(request);
    }
    try {
      final bundle = _bundleFromResponse(
        await _callable(_requestPayload(request)),
      );
      if (bundle != null) {
        return bundle;
      }
    } catch (_) {
      // Network error, callable error, or malformed response: compose a
      // local fallback message instead of surfacing a crash to the UI.
    }
    return fallbackAgent.explainTodayPlan(request);
  }

  static HomeGuideCallable _firebaseCallable(FirebaseFunctions functions) {
    return (payload) async {
      final result = await functions
          .httpsCallable('homeGuideAgent')
          .call(payload);
      return result.data;
    };
  }

  Map<String, Object?> _requestPayload(HomeGuideRequest request) {
    return <String, Object?>{
      'planTitle': _bounded(request.planTitle, 200),
      'weekNumber': request.weekNumber,
      'weekFocus': _bounded(request.weekFocus, 200),
      'dayLabel': _bounded(request.dayLabel, 200),
      'workoutTitle': _bounded(request.workoutTitle, 200),
      'durationMinutes': request.durationMinutes,
      'intensity': _bounded(request.intensityLabel, 200),
      'description': _bounded(request.description, 800),
      'steps': request.steps
          .map((step) => _bounded(step, 200))
          .where((step) => step.isNotEmpty)
          .take(12)
          .toList(growable: false),
      'supportiveNote': _bounded(request.supportiveNote, 200),
    };
  }

  HomeGuideBundle? _bundleFromResponse(Object? data) {
    if (data is! Map<Object?, Object?>) {
      return null;
    }
    final source = data['source'];
    final delivery = data['delivery'];
    final messages = data['messages'];
    final isGenerated =
        source == 'agent' && (delivery == 'generated' || delivery == 'cache');
    final isUnavailableFallback =
        source == 'unavailable' && delivery == 'fallback';
    if ((!isGenerated && !isUnavailableFallback) ||
        messages is! Map<Object?, Object?>) {
      return null;
    }
    final planSummary = messages['planSummary'];
    final runningTip = messages['runningTip'];
    final progressionCheckIn = messages['progressionCheckIn'];
    if (planSummary is! String ||
        runningTip is! String ||
        progressionCheckIn is! String) {
      return null;
    }
    return HomeGuideBundle.tryCreate(
      planSummary: planSummary,
      runningTip: runningTip,
      progressionCheckIn: progressionCheckIn,
      isFromRemoteAgent: isGenerated,
    );
  }

  String _bounded(String value, int maxRunes) {
    final trimmed = value.trim();
    final runes = trimmed.runes;
    return runes.length <= maxRunes
        ? trimmed
        : String.fromCharCodes(runes.take(maxRunes));
  }
}
