// Domain port for the planned-workout AI briefing.
//
// The workout detail screen depends on this interface and nothing else — not on
// Firebase, not on the callable adapter, not on the cache. That is what lets a
// widget test drive the whole surface with a plain stub.

import 'package:flutter/foundation.dart';

/// One metric tile as the detail screen already renders it.
@immutable
class WorkoutBriefingMetric {
  const WorkoutBriefingMetric({required this.label, required this.value});

  final String label;
  final String value;

  Map<String, Object?> toWire() => <String, Object?>{
    'label': label,
    'value': value,
  };
}

/// One session-breakdown row as the detail screen already renders it.
@immutable
class WorkoutBriefingStep {
  const WorkoutBriefingStep({required this.title, required this.detail});

  final String title;
  final String detail;

  Map<String, Object?> toWire() => <String, Object?>{
    'title': title,
    'detail': detail,
  };
}

/// Everything the agent is allowed to know about the planned session.
///
/// Deliberately display copy only. `cacheIdentity` never crosses the wire — it
/// is local cache-key material, which is why the plan id can appear here and
/// still be absent from the request payload.
@immutable
class WorkoutBriefingRequest {
  const WorkoutBriefingRequest({
    required this.dayLabel,
    required this.planTitle,
    required this.effortGuide,
    this.weekNumber,
    this.weekFocus,
    this.metrics = const <WorkoutBriefingMetric>[],
    this.steps = const <WorkoutBriefingStep>[],
    this.coachNotes = const <String>[],
    this.cacheIdentity,
  });

  final String dayLabel;
  final String planTitle;
  final String effortGuide;
  final int? weekNumber;
  final String? weekFocus;
  final List<WorkoutBriefingMetric> metrics;
  final List<WorkoutBriefingStep> steps;
  final List<String> coachNotes;
  final String? cacheIdentity;
}

@immutable
class WorkoutBriefingSections {
  const WorkoutBriefingSections({
    required this.todaySession,
    required this.whyItHelps,
    required this.howItFeels,
    required this.beforeYouStart,
  });

  final String todaySession;
  final String whyItHelps;
  final String howItFeels;
  final String beforeYouStart;

  List<WorkoutBriefingSectionStep> get steps {
    return <WorkoutBriefingSectionStep>[
      WorkoutBriefingSectionStep(title: "Today's session", body: todaySession),
      WorkoutBriefingSectionStep(title: 'Why it helps', body: whyItHelps),
      WorkoutBriefingSectionStep(title: 'How it should feel', body: howItFeels),
      WorkoutBriefingSectionStep(
        title: 'Before you start',
        body: beforeYouStart,
      ),
    ];
  }
}

@immutable
class WorkoutBriefingSectionStep {
  const WorkoutBriefingSectionStep({required this.title, required this.body});

  final String title;
  final String body;
}

@immutable
class WorkoutBriefingBundle {
  const WorkoutBriefingBundle({
    required this.sections,
    required this.source,
    this.retryAfterDate,
  });

  final WorkoutBriefingSections sections;
  final WorkoutBriefingSource source;
  final String? retryAfterDate;

  bool get isGenerated => source == WorkoutBriefingSource.generated;
}

enum WorkoutBriefingSource { generated, fallback, quota }

abstract interface class WorkoutBriefingAgent {
  Future<WorkoutBriefingBundle> explainPlannedWorkout(
    WorkoutBriefingRequest request,
  );
}

/// Stable machine-readable reason the callable attaches to its
/// permission-denied error when a non-premium runner invokes it directly.
/// Mirrors `WORKOUT_BRIEFING_PREMIUM_REQUIRED_REASON` in
/// `functions/src/agent/workoutBriefingAgentHandler.ts`.
const workoutBriefingPremiumRequiredReason = 'premium-required';

/// Defence-in-depth copy for a server-side premium denial. The paywall gate
/// normally intercepts Basic runners before the callable is ever reached.
WorkoutBriefingBundle premiumRequiredWorkoutBriefingBundle() {
  return const WorkoutBriefingBundle(
    source: WorkoutBriefingSource.fallback,
    sections: WorkoutBriefingSections(
      todaySession: "Today's workout explainer is a Premium feature.",
      whyItHelps:
          'Your plan and today’s session are unchanged and ready to start.',
      howItFeels:
          'Runiac Premium unlocks a friendly walkthrough of every planned session.',
      beforeYouStart:
          'Keep following your plan — the explainer is here whenever you upgrade.',
    ),
  );
}

/// Used whenever the callable cannot answer. Deliberately still useful copy:
/// a failed model call should read as a calm coach, not as a broken screen.
WorkoutBriefingBundle fallbackWorkoutBriefingBundle({
  WorkoutBriefingSource source = WorkoutBriefingSource.fallback,
  String? retryAfterDate,
}) {
  return WorkoutBriefingBundle(
    source: source,
    retryAfterDate: retryAfterDate,
    sections: const WorkoutBriefingSections(
      todaySession:
          "Here is today's session as your plan wrote it — the breakdown above lists every step in order.",
      whyItHelps:
          'Every session in a beginner plan is there to build easy, repeatable running rather than one hard day.',
      howItFeels:
          'Keep the effort conversational: you should be able to speak in full sentences the whole way.',
      beforeYouStart:
          'Warm up gently, start slower than feels natural, and walk whenever you need to reset.',
    ),
  );
}
