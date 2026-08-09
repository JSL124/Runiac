import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app.dart';
import '../../../onboarding/domain/models/local_onboarding_draft.dart';
import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../../plan/domain/services/beginner_adaptive_plan_generator.dart';
import '../../../plan/presentation/current_session_generated_plan.dart';
import '../../domain/app_tour_seen_store.dart';

const appTourQaSurfaceName = 'app_tour';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');

/// Debug-only surface that drops straight into the shell with the first-run
/// app tour already armed, so the tour can be reviewed without walking a fresh
/// signup through onboarding first.
Widget? buildAppTourQaAppFromEnvironment() {
  return buildAppTourQaApp(releaseMode: kReleaseMode, surface: _qaSurface);
}

@visibleForTesting
Widget? buildAppTourQaApp({
  required bool releaseMode,
  required String surface,
}) {
  if (releaseMode || surface != appTourQaSurfaceName) {
    return null;
  }

  return RuniacApp(
    showSplash: false,
    showAuth: false,
    showOnboarding: false,
    enableForegroundGps: false,
    appTourSeenStore: const _QaArmedAppTourSeenStore(),
    currentSessionGeneratedPlanStore: buildAppTourQaGeneratedPlanStore(),
  );
}

/// A plausible beginner onboarding draft used only to seed the app-tour QA
/// surface's demo plan. Three running days a week (Mon/Wed/Fri) with the
/// rest of the week resting is enough for
/// `BeginnerAdaptivePlanGenerator` to resolve a multi-week
/// (`PlanFamilyCategory.developing`, 6-week) plan family with a genuine mix
/// of running and rest stones.
LocalOnboardingDraft _qaBeginnerOnboardingDraft() {
  return LocalOnboardingDraft(
    goal: OnboardingGoal.habit,
    experience: OnboardingExperience.run30,
    availability: OnboardingAvailability.three,
    preferredDays: const [
      OnboardingPreferredDay.mon,
      OnboardingPreferredDay.wed,
      OnboardingPreferredDay.fri,
    ],
    preferredTime: OnboardingPreferredTime.morning,
    sessionLength: OnboardingSessionLength.thirty,
    runningPlace: OnboardingRunningPlace.park,
    motivationStyle: OnboardingMotivationStyle.plan,
    healthComfort: OnboardingHealthComfort.ready,
    activitySymptoms: const [OnboardingActivitySymptom.none],
    recentRunningConsistency: RecentRunningConsistency.oneToThreeMonths,
    currentWeeklyRunFrequency: CurrentWeeklyRunFrequency.three,
    continuousRunCapacity: ContinuousRunCapacity.twentyToThirtyMinutes,
    planCautiousness: OnboardingPlanCautiousness.balanced,
  );
}

/// Builds a [CurrentSessionGeneratedPlanStore] pre-loaded with an active
/// multi-week plan, so the Home stage map renders real stones instead of its
/// empty state ("Your journey map is waiting"). Without this, the three
/// tour steps targeting `homeTodayStone`/`homeStoneCluster`
/// (`home-today-stone`, `home-stone-days`, `home-rest-streak`,
/// `home-stone-detail`) all degrade to fallback copy with no spotlight,
/// because those anchors only render when a stage stone is marked current.
///
/// Reuses the production `BeginnerAdaptivePlanGenerator` — the same
/// generator `RuniacApp._completeOnboarding` calls on real onboarding
/// completion — fed a plausible beginner draft, rather than hand-authoring a
/// plan snapshot literal. `withStartsOnDate` is set to today (as production
/// onboarding completion does), which always lands the plan's active week on
/// week 1 and marks whichever stone matches today's real weekday as current,
/// regardless of what day of the week the QA build happens to run on.
///
/// This seeds the plan only. No XP, level, rank, streak, or leaderboard
/// value is computed or displayed here — those stay backend-owned.
@visibleForTesting
CurrentSessionGeneratedPlanStore buildAppTourQaGeneratedPlanStore() {
  final snapshot = const BeginnerAdaptivePlanGenerator()
      .generate(_qaBeginnerOnboardingDraft())
      .withStartsOnDate(generatedPlanDateLabel(DateTime.now()));
  final store = CurrentSessionGeneratedPlanStore();
  store.setActivePlan(snapshot);
  return store;
}

/// Reports the tour as permanently armed and never completed, so a hot restart
/// replays it. QA only — the real app uses the uid-scoped
/// `SharedPreferencesAppTourSeenStore`.
class _QaArmedAppTourSeenStore implements AppTourSeenStore {
  const _QaArmedAppTourSeenStore();

  @override
  Future<bool> isArmed({required String? uid}) async => true;

  @override
  Future<void> setArmed({required String? uid, required bool armed}) async {}

  @override
  Future<bool> isCompleted({required String? uid}) async => false;

  @override
  Future<void> markCompleted({required String? uid}) async {}
}
