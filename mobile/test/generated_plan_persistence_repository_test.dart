import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/plan/data/firestore_generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  test(
    'generated plan persistence round trips workout detail payload',
    () async {
      final writer = _RecordingGeneratedPlanDocumentStore();
      final repository = FirestoreGeneratedPlanPersistenceRepository(
        documentStore: writer,
        updatedAt: () => 1,
      );
      final plan = _withFirstWorkoutSchedule(
        const BeginnerAdaptivePlanGenerator()
            .generate(_draft())
            .withStartsOnDate('2026-07-05'),
      );

      await repository.saveGeneratedPlan(uid: 'runner-1', plan: plan);
      final restored = await repository.loadGeneratedPlan(uid: 'runner-1');

      expect(writer.uid, 'runner-1');
      expect(restored, isNotNull);
      expect(restored!.title, plan.title);
      expect(restored.startsOnDate, '2026-07-05');
      expect(
        restored.weeks.first.workouts.first.detail.metrics.first.value,
        '20 min',
      );
      expect(
        restored.weeks.first.workouts.first.detail.breakdown.first.title,
        plan.weeks.first.workouts.first.detail.breakdown.first.title,
      );
      expect(
        restored.weeks.first.workouts.first.detail.coachNotes,
        plan.weeks.first.workouts.first.detail.coachNotes,
      );
      expect(restored.weeks.first.workouts.first.dayLabel, 'Fri');
      expect(restored.weeks.first.workouts.first.scheduleTimeLabel, '7:01 PM');
    },
  );

  test(
    'generated plan persistence omits backend-owned progress fields',
    () async {
      final writer = _RecordingGeneratedPlanDocumentStore();
      final repository = FirestoreGeneratedPlanPersistenceRepository(
        documentStore: writer,
        updatedAt: () => 1,
      );

      await repository.saveGeneratedPlan(
        uid: 'runner-1',
        plan: const BeginnerAdaptivePlanGenerator().generate(_draft()),
      );

      final documentText = writer.document.toString();
      expect(
        documentText,
        isNot(
          contains(
            RegExp(
              r'\b(xp|level|rank|streak|leaderboardScore|subscriptionStatus|'
              r'userRole|planCompletion|completedRun|remainingRun|validationStatus)\b',
              caseSensitive: false,
            ),
          ),
        ),
      );
    },
  );

  test(
    'generated plan persistence recovers missing start date from createdAt',
    () async {
      final writer = _RecordingGeneratedPlanDocumentStore();
      final repository = FirestoreGeneratedPlanPersistenceRepository(
        documentStore: writer,
        updatedAt: () => Timestamp.fromDate(DateTime(2026, 7, 6, 10, 30)),
      );
      final plan = const BeginnerAdaptivePlanGenerator().generate(_draft());

      await repository.saveGeneratedPlan(uid: 'runner-1', plan: plan);
      writer.document = <String, Object?>{...writer.document}
        ..remove('startsOnDate')
        ..['createdAt'] = Timestamp.fromDate(DateTime(2026, 7, 6, 10, 30));

      final restored = await repository.loadGeneratedPlan(uid: 'runner-1');

      expect(restored, isNotNull);
      expect(restored!.startsOnDate, '2026-07-06');
    },
  );
}

BeginnerAdaptivePlanSnapshot _withFirstWorkoutSchedule(
  BeginnerAdaptivePlanSnapshot plan,
) {
  final firstWeek = plan.weeks.first;
  final firstWorkout = firstWeek.workouts.first;
  return BeginnerAdaptivePlanSnapshot(
    id: plan.id,
    title: plan.title,
    subtitle: plan.subtitle,
    planKind: plan.planKind,
    sourceLabel: plan.sourceLabel,
    startsOnDate: plan.startsOnDate,
    durationWeeks: plan.durationWeeks,
    safetyBand: plan.safetyBand,
    templateKind: plan.templateKind,
    family: plan.family,
    familyCategory: plan.familyCategory,
    familyReason: plan.familyReason,
    supportStyleLabel: plan.supportStyleLabel,
    weeklyFrequencyLabel: plan.weeklyFrequencyLabel,
    preferredScheduleLabel: plan.preferredScheduleLabel,
    sessionDurationLabel: plan.sessionDurationLabel,
    safetyNote: plan.safetyNote,
    clientDisplayStatus: plan.clientDisplayStatus,
    weeks: [
      BeginnerAdaptivePlanWeek(
        weekNumber: firstWeek.weekNumber,
        title: firstWeek.title,
        focus: firstWeek.focus,
        workouts: [
          BeginnerAdaptiveWorkout(
            dayLabel: 'Fri',
            title: firstWorkout.title,
            durationMinutes: firstWorkout.durationMinutes,
            kind: firstWorkout.kind,
            intensity: firstWorkout.intensity,
            description: firstWorkout.description,
            steps: firstWorkout.steps,
            supportiveNote: firstWorkout.supportiveNote,
            detail: firstWorkout.detail,
            scheduleTimeLabel: '7:01 PM',
          ),
          ...firstWeek.workouts.skip(1),
        ],
      ),
      ...plan.weeks.skip(1),
    ],
  );
}

class _RecordingGeneratedPlanDocumentStore
    implements GeneratedPlanDocumentStore {
  String? uid;
  Map<String, Object?> document = const {};

  @override
  Future<Map<String, Object?>?> loadGeneratedPlan({required String uid}) async {
    return document.isEmpty ? null : document;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required Map<String, Object?> data,
    bool resetCreatedAt = false,
  }) async {
    this.uid = uid;
    document = data;
  }
}

LocalOnboardingDraft _draft() {
  return LocalOnboardingDraft(
    goal: OnboardingGoal.habit,
    experience: OnboardingExperience.newRunner,
    availability: OnboardingAvailability.three,
    preferredDays: const [OnboardingPreferredDay.mon],
    preferredTime: OnboardingPreferredTime.morning,
    sessionLength: OnboardingSessionLength.twenty,
    runningPlace: OnboardingRunningPlace.park,
    motivationStyle: OnboardingMotivationStyle.reminders,
    healthComfort: OnboardingHealthComfort.ready,
    activitySymptoms: const [OnboardingActivitySymptom.none],
    planCautiousness: OnboardingPlanCautiousness.balanced,
    recentRunningConsistency: RecentRunningConsistency.none,
    currentWeeklyRunFrequency: CurrentWeeklyRunFrequency.zero,
    continuousRunCapacity: ContinuousRunCapacity.runWalk,
  );
}
