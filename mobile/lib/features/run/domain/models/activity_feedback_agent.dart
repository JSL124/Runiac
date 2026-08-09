import 'advanced_analysis_snapshot.dart';
import 'run_summary_snapshot.dart';

class ActivityFeedbackRequest {
  const ActivityFeedbackRequest({
    required this.summary,
    required this.analysis,
    this.cacheIdentity,
  });

  final RunSummarySnapshot summary;
  final AdvancedAnalysisSnapshot analysis;
  final String? cacheIdentity;
}

class ActivityFeedbackSections {
  const ActivityFeedbackSections({
    required this.summary,
    required this.wentWell,
    required this.improve,
    required this.nextFocus,
  });

  final String summary;
  final String wentWell;
  final String improve;
  final String nextFocus;

  List<ActivityFeedbackSectionStep> get steps {
    return <ActivityFeedbackSectionStep>[
      ActivityFeedbackSectionStep(title: 'Summary', body: summary),
      ActivityFeedbackSectionStep(title: 'Went well', body: wentWell),
      ActivityFeedbackSectionStep(title: 'Improve', body: improve),
      ActivityFeedbackSectionStep(title: 'Next focus', body: nextFocus),
    ];
  }
}

class ActivityFeedbackSectionStep {
  const ActivityFeedbackSectionStep({required this.title, required this.body});

  final String title;
  final String body;
}

class ActivityFeedbackBundle {
  const ActivityFeedbackBundle({
    required this.sections,
    required this.source,
    this.retryAfterDate,
  });

  final ActivityFeedbackSections sections;
  final ActivityFeedbackSource source;
  final String? retryAfterDate;

  bool get isGenerated => source == ActivityFeedbackSource.generated;
}

enum ActivityFeedbackSource { generated, fallback, quota }

abstract interface class ActivityFeedbackAgent {
  Future<ActivityFeedbackBundle> explainRun(ActivityFeedbackRequest request);
}

/// Stable machine-readable reason the callable attaches to its
/// permission-denied error when a non-premium runner invokes it directly.
/// Mirrors `ACTIVITY_FEEDBACK_PREMIUM_REQUIRED_REASON` in
/// `functions/src/agent/activityFeedbackAgentHandler.ts`.
const activityFeedbackPremiumRequiredReason = 'premium-required';

/// Defence-in-depth copy for a server-side premium denial. The paywall gate
/// normally intercepts Basic runners before the callable is ever reached.
ActivityFeedbackBundle premiumRequiredActivityFeedbackBundle() {
  return const ActivityFeedbackBundle(
    source: ActivityFeedbackSource.fallback,
    sections: ActivityFeedbackSections(
      summary: 'Activity feedback is a Premium feature.',
      wentWell: 'Your run and its summary are saved as usual.',
      improve: 'Runiac Premium unlocks personalised post-run feedback.',
      nextFocus: 'Keep running — your data is ready whenever you upgrade.',
    ),
  );
}

ActivityFeedbackBundle fallbackActivityFeedbackBundle({
  ActivityFeedbackSource source = ActivityFeedbackSource.fallback,
  String? retryAfterDate,
}) {
  return ActivityFeedbackBundle(
    source: source,
    retryAfterDate: retryAfterDate,
    sections: const ActivityFeedbackSections(
      summary:
          'Your run summary is ready, but personalised feedback is temporarily unavailable.',
      wentWell: 'You completed the run and captured useful derived metrics.',
      improve:
          'Keep the next effort comfortable and notice what feels repeatable.',
      nextFocus: 'Aim for one calm, steady session when you feel ready.',
    ),
  );
}
