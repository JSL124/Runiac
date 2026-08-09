import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/home/presentation/home_recenter_intent_controller.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_background_sequence.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map_model.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';

// Home is the runner's map, so its bottom-bar item means "take me back to my
// character". The tab keeps its scroll offset while other tabs are on screen,
// which is what makes the request necessary at all: without it, a runner who
// scrolled up to look at later weeks comes back to those weeks, not to the
// character standing on today's stage.

BeginnerAdaptivePlanSnapshot _plan() {
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

/// The current stage sits in a middle week, far from both scroll extremes, so
/// the landing offset is a real position rather than a clamped end.
HomeStageMapModel _modelAtMiddleWeek(BeginnerAdaptivePlanSnapshot plan) {
  final middleWeekNumber = plan.weeks[plan.weeks.length ~/ 2].weekNumber;
  return buildHomeStageMapModel(
    plan: plan,
    completedScheduledWorkoutIds: const <String>{},
    activeWeekNumber: middleWeekNumber,
    backgroundSequence: homeStageBackgroundSequence(
      planId: plan.id,
      weekCount: plan.weeks.length,
    ),
  );
}

ScrollableState _mapScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable).first);
}

void main() {
  testWidgets('a recenter request returns the map to the character', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recenterIntent = HomeRecenterIntentController();
    addTearDown(recenterIntent.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            model: _modelAtMiddleWeek(_plan()),
            onNotifications: () {},
            onProfile: () {},
            onTapTodayStage: () {},
            recenterIntent: recenterIntent,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final landingOffset = _mapScrollable(tester).position.pixels;
    expect(landingOffset, greaterThan(1));

    // The runner scrolls away to look at the rest of the plan.
    await tester.drag(find.byType(HomeStageMap), const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(
      _mapScrollable(tester).position.pixels,
      lessThan(landingOffset - 100),
    );

    recenterIntent.request();
    await tester.pumpAndSettle();

    expect(
      _mapScrollable(tester).position.pixels,
      closeTo(landingOffset, 0.5),
    );
  });

  testWidgets('a request while already on the character changes nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recenterIntent = HomeRecenterIntentController();
    addTearDown(recenterIntent.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            model: _modelAtMiddleWeek(_plan()),
            onNotifications: () {},
            onProfile: () {},
            onTapTodayStage: () {},
            recenterIntent: recenterIntent,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final landingOffset = _mapScrollable(tester).position.pixels;
    recenterIntent.request();
    await tester.pumpAndSettle();

    expect(_mapScrollable(tester).position.pixels, landingOffset);
  });

  testWidgets(
    'tapping Home in the bottom bar scrolls back to the character, from Home '
    'and from another tab',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore()
        ..setActivePlan(_plan());
      addTearDown(authRepository.dispose);
      addTearDown(generatedPlanStore.dispose);

      final activityHistoryStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-auth-user-1',
      );
      addTearDown(activityHistoryStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: activityHistoryStore,
            child: CurrentSessionGeneratedPlanScope(
            store: generatedPlanStore,
            child: RuniacShell(
              authRepository: authRepository,
              feedRepository: const StaticFeedRepository(),
              profileRepository: const StaticUserProfileRepository(),
              profilePersistenceRepository:
                  const NoopUserProfilePersistenceRepository(),
              enableForegroundGps: false,
            ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final landingOffset = _mapScrollable(tester).position.pixels;
      expect(landingOffset, greaterThan(1));

      // Scrolled away, still on Home: the Home item is a way back.
      await tester.drag(find.byType(HomeStageMap), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(_mapScrollable(tester).position.pixels, lessThan(landingOffset));

      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(
        _mapScrollable(tester).position.pixels,
        closeTo(landingOffset, 0.5),
      );

      // Scrolled away, then returning from another tab: same destination, so
      // Home never reappears somewhere the runner did not ask for.
      await tester.drag(find.byType(HomeStageMap), const Offset(0, 200));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();

      expect(
        _mapScrollable(tester).position.pixels,
        closeTo(landingOffset, 0.5),
      );
    },
  );
}
