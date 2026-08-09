import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/plan/domain/models/adaptive_plan_estimate_read_model.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/repositories/adaptive_plan_estimate_repository.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/run/presentation/models/planned_run_context.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';

BeginnerAdaptivePlanSnapshot _tenKPerformancePlan() {
  return const BeginnerAdaptivePlanGenerator().generate(
    planFamilyPerformanceDraft(
      goal: OnboardingGoal.tenK,
      style: OnboardingPlanStyle.performanceFocused,
      days: const [
        OnboardingPreferredDay.mon,
        OnboardingPreferredDay.tue,
        OnboardingPreferredDay.wed,
        OnboardingPreferredDay.thu,
      ],
    ),
  );
}

DateTime _weekdayDate(int weekday) {
  return DateTime(2026, 6, 21 + weekday);
}

AdaptivePlanEstimateReadModel _usableEstimate() {
  return AdaptivePlanEstimateReadModel.fromBackend(const {
    'averageRecentPaceSecondsPerKm': 469,
    'completedRunCount': 2,
    'positivePaceRunCount': 2,
    'readinessBand': 'learning',
  });
}

void main() {
  test('generated planned run consumes adaptive estimate as distance copy', () {
    // Given: Tuesday is today's generated 25 minute workout and backend pace is usable.
    final context = todayPlannedRunContextFromSnapshot(
      _tenKPerformancePlan(),
      currentDate: _weekdayDate(DateTime.tuesday),
      adaptiveEstimate: _usableEstimate(),
    );

    // Then: the planned run uses personalized display-only distance context.
    expect(context, isNotNull);
    expect(context!.estimatedDistanceLabel, '~3.2 km');
    expect(context.estimateConfidence, PlannedRunEstimateConfidence.medium);
    expect(context.targetDistanceMeters, 3198);
    expect(context.supportLabel, 'Balanced effort · About ~3.2 km estimate');
  });

  test(
    'conservative adaptive estimate keeps generated planned run distance hidden',
    () {
      // Given: backend adaptive state is conservative.
      final conservative = AdaptivePlanEstimateReadModel.fromBackend(const {
        'averageRecentPaceSecondsPerKm': 469,
        'positivePaceRunCount': 2,
        'readinessBand': 'conservative',
      });

      // When: the generated planned context is built.
      final context = todayPlannedRunContextFromSnapshot(
        _tenKPerformancePlan(),
        currentDate: _weekdayDate(DateTime.tuesday),
        adaptiveEstimate: conservative,
      );

      // Then: the existing no-distance-target fallback remains unchanged.
      expect(context, isNotNull);
      expect(context!.estimatedDistanceLabel, isNull);
      expect(context.estimateConfidence, PlannedRunEstimateConfidence.none);
      expect(context.targetDistanceMeters, isNull);
      expect(context.supportLabel, contains('no distance target'));
    },
  );

  testWidgets(
    'RuniacApp Run launch hydrates adaptive estimate into generated planned run',
    (tester) async {
      // Given: generatedPlans owns today's run and adaptivePlanEstimates owns pace.
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');
      addTearDown(authRepository.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          generatedPlanPersistenceRepository: _LoadedGeneratedPlanRepository(
            _tenKPerformancePlan(),
          ),
          adaptivePlanEstimateRepository: _LoadedAdaptivePlanEstimateRepository(
            _usableEstimate(),
          ),
          youProgressToday: _weekdayDate(DateTime.tuesday),
        ),
      );
      await tester.pumpAndSettle();

      // When: the Run tab opens from the hydrated app shell.
      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();

      // Then: Run launch displays personalized estimate copy from backend state.
      expect(find.text('CONTROLLED STEADY RUN'), findsOneWidget);
      expect(
        find.text('Balanced effort · About ~3.2 km estimate'),
        findsOneWidget,
      );
      expect(find.textContaining('no distance target'), findsNothing);
      expect(find.text('4.5'), findsNothing);
      expect(find.text('km easy run'), findsNothing);
    },
  );

  testWidgets(
    'RuniacApp missing adaptive estimate keeps generated planned run fallback copy',
    (tester) async {
      // Given: generatedPlans owns today's run but adaptive estimate is empty.
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');
      addTearDown(authRepository.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          generatedPlanPersistenceRepository: _LoadedGeneratedPlanRepository(
            _tenKPerformancePlan(),
          ),
          adaptivePlanEstimateRepository:
              const NoopAdaptivePlanEstimateRepository(),
          youProgressToday: _weekdayDate(DateTime.tuesday),
        ),
      );
      await tester.pumpAndSettle();

      // When: the Run tab opens from the hydrated app shell.
      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();

      // Then: generated planned run fallback copy remains safe.
      expect(find.text('CONTROLLED STEADY RUN'), findsOneWidget);
      expect(find.textContaining('no distance target'), findsOneWidget);
      expect(find.textContaining('About ~3.2 km estimate'), findsNothing);
    },
  );

  testWidgets('RuniacApp ignores stale adaptive estimate owner loads', (
    tester,
  ) async {
    // Given: the first owner adaptive estimate load is still pending.
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-1');
    final adaptiveRepository = _DelayedAdaptivePlanEstimateRepository();
    addTearDown(authRepository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        generatedPlanPersistenceRepository: _LoadedGeneratedPlanRepository(
          _tenKPerformancePlan(),
        ),
        adaptivePlanEstimateRepository: adaptiveRepository,
        youProgressToday: _weekdayDate(DateTime.tuesday),
      ),
    );
    await tester.pumpAndSettle();

    // When: auth changes owners before the first estimate resolves.
    authRepository.emitSignedIn(uid: 'runner-2');
    await tester.pumpAndSettle();
    adaptiveRepository.complete(uid: 'runner-1', estimate: _usableEstimate());
    adaptiveRepository.complete(
      uid: 'runner-2',
      estimate: const AdaptivePlanEstimateReadModel.empty(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    // Then: runner-1's stale estimate never reaches runner-2's launch copy.
    expect(find.text('CONTROLLED STEADY RUN'), findsOneWidget);
    expect(find.textContaining('no distance target'), findsOneWidget);
    expect(find.textContaining('About ~3.2 km estimate'), findsNothing);
  });
}

class _LoadedGeneratedPlanRepository
    implements GeneratedPlanPersistenceRepository {
  const _LoadedGeneratedPlanRepository(this.plan);

  final BeginnerAdaptivePlanSnapshot plan;

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    return plan;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) async {}
}

class _LoadedAdaptivePlanEstimateRepository
    implements AdaptivePlanEstimateRepository {
  const _LoadedAdaptivePlanEstimateRepository(this.estimate);

  final AdaptivePlanEstimateReadModel estimate;

  @override
  Future<AdaptivePlanEstimateReadModel> loadAdaptivePlanEstimate({
    required String uid,
  }) async {
    return estimate;
  }
}

class _DelayedAdaptivePlanEstimateRepository
    implements AdaptivePlanEstimateRepository {
  final _loads = <String, Completer<AdaptivePlanEstimateReadModel>>{};

  @override
  Future<AdaptivePlanEstimateReadModel> loadAdaptivePlanEstimate({
    required String uid,
  }) {
    return _loads
        .putIfAbsent(uid, Completer<AdaptivePlanEstimateReadModel>.new)
        .future;
  }

  void complete({
    required String uid,
    required AdaptivePlanEstimateReadModel estimate,
  }) {
    final load = _loads[uid];
    if (load != null && !load.isCompleted) {
      load.complete(estimate);
    }
  }
}
