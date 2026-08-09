import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_agent.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_consent.dart';
import 'package:runiac_app/features/home/domain/guide/plan_brief_home_guide_agent.dart';
import 'package:runiac_app/features/home/domain/guide/rule_based_home_guide_agent.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_background_sequence.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map_model.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/tutorial/domain/models/tutorial_step.dart';
import 'package:runiac_app/features/tutorial/presentation/tutorial_anchor_registry.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';

import 'support/plan_family_test_drafts.dart';

const HomeGuideRequest _guideRequest = HomeGuideRequest(
  planTitle: 'First 10K Preparation',
  weekNumber: 1,
  weekFocus: 'Build a steady habit',
  dayLabel: 'Mon',
  workoutTitle: 'Easy Run',
  durationMinutes: 20,
  intensityLabel: 'Gentle',
  description: 'A relaxed run to build your habit.',
  supportiveNote: 'Keep the pace conversational.',
);

const HomeGuideRequest _stepGuideRequest = HomeGuideRequest(
  planTitle: 'First 10K Preparation',
  weekNumber: 1,
  weekFocus: 'Build a steady habit',
  dayLabel: 'Mon',
  workoutTitle: 'Easy Run',
  durationMinutes: 20,
  intensityLabel: 'Gentle',
  description: 'A relaxed run to build your habit.',
  steps: <String>[
    'Warm up 5 minutes',
    'Run 10 minutes easy',
    'Cool down 5 minutes',
  ],
  supportiveNote: 'Keep the pace conversational.',
);

const HomeGuideRequest _restGuideRequest = HomeGuideRequest(
  planTitle: 'First 10K Preparation',
  weekNumber: 1,
  weekFocus: 'Build a steady habit',
  dayLabel: 'Wed',
  workoutTitle: '',
  durationMinutes: 0,
  intensityLabel: '',
  description: '',
  isRestDay: true,
);

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

HomeStageMapModel _model(BeginnerAdaptivePlanSnapshot plan) {
  return buildHomeStageMapModel(
    plan: plan,
    completedScheduledWorkoutIds: const <String>{},
    activeWeekNumber: plan.weeks.first.weekNumber,
    backgroundSequence: homeStageBackgroundSequence(
      planId: plan.id,
      weekCount: plan.weeks.length,
    ),
  );
}

/// Same generated plan, but with the active/current stage moved to a middle
/// week (not the plan's first or last), so the current stage sits far enough
/// from both scroll extremes for the lower-third landing target to be
/// reachable without clamping.
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

int _assetImageCount(WidgetTester tester, String assetName) {
  return tester
      .widgetList<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == assetName,
        ),
      )
      .length;
}

void main() {
  test('Home guide selects idle, running, and fallback assets by motion', () {
    expect(
      homeStageGuideAssetPath(
        character: RunnerCharacter.blue,
        facing: RunnerCharacterFacing.front,
      ),
      RunnerCharacter.blue.idleAnimationAssetPath,
    );

    expect(
      homeStageGuideAssetPath(
        character: RunnerCharacter.blue,
        facing: RunnerCharacterFacing.right,
        isMoving: true,
      ),
      'assets/images/characters/blue_runner_run_right.gif',
    );

    expect(
      homeStageGuideAssetPath(
        character: RunnerCharacter.cap,
        facing: RunnerCharacterFacing.right,
        isMoving: true,
      ),
      'assets/images/characters/cap_runner_run_right.gif',
    );

    expect(
      homeStageGuideAssetPath(
        character: RunnerCharacter.cap,
        facing: RunnerCharacterFacing.front,
      ),
      'assets/images/characters/cap_runner_idle.gif',
    );

    expect(
      homeStageGuideAssetPath(
        character: RunnerCharacter.cap,
        facing: RunnerCharacterFacing.back,
        isMoving: true,
      ),
      'assets/images/characters/cap_runner_back.png',
    );

    expect(
      homeStageGuideAssetPath(
        character: RunnerCharacter.pink,
        facing: RunnerCharacterFacing.right,
        isMoving: true,
        reducedMotion: true,
      ),
      'assets/images/characters/pink_runner_front.png',
    );
  });

  test('guide height preserves the selected asset aspect ratio', () {
    for (final character in RunnerCharacter.values) {
      expect(
        homeStageGuideHeightForWidth(character: character, width: 193),
        closeTo(289, 0.0001),
        reason: '${character.displayName} should use the Bolt footprint',
      );
    }
  });

  test(
    'stage map uses the plan creation weekday as day zero through week 8',
    () {
      final plan = _plan().withStartsOnDate('2026-07-05');
      final startSunday = DateTime(2026, 7, 5);

      for (var week = 1; week <= 8; week += 1) {
        final date = startSunday.add(Duration(days: 7 * (week - 1)));
        final activeWeek = activeGeneratedPlanWeekFor(plan, currentDate: date);
        final activeDayIndex = activeGeneratedPlanDayIndexFor(
          plan,
          currentDate: date,
        );

        final model = buildHomeStageMapModel(
          plan: plan,
          completedScheduledWorkoutIds: const <String>{},
          activeWeekNumber: activeWeek!.weekNumber,
          currentWeekdayIndex: DateTime.monday + activeDayIndex!,
          backgroundSequence: homeStageBackgroundSequence(
            planId: plan.id,
            weekCount: plan.weeks.length,
          ),
        );

        expect(model.currentWeekIndex, week - 1);
        expect(model.todayDayIndex, 0);
        expect(model.characterDayIndex, 0);
        expect(model.currentStageId, HomeStageMapModel.stageId(week - 1, 0));
      }
    },
  );

  testWidgets('empty state keeps a working header and Menu panel', (
    WidgetTester tester,
  ) async {
    var notifications = 0;
    var profile = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            model: null,
            streakCount: 4,
            unreadNotificationCount: 2,
            levelBadgeLabel: 'Lv.3',
            levelProgressFraction: 0.5,
            onNotifications: () => notifications++,
            onProfile: () => profile++,
            onTapTodayStage: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your journey map is waiting'), findsOneWidget);
    // Streak and notifications now live inside the Menu panel, not the header.
    expect(find.text('4'), findsNothing);
    expect(find.bySemanticsLabel('Notifications'), findsNothing);
    expect(find.bySemanticsLabel('Profile'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Profile'));
    expect(profile, 1);

    await tester.tap(find.byKey(const ValueKey('homeMenuTrigger')));
    await tester.pumpAndSettle();
    expect(find.text('4 day streak'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // unread badge over the bell icon

    await tester.tap(find.bySemanticsLabel('Notifications, 2 unread'));
    await tester.pumpAndSettle();
    expect(notifications, 1);
  });

  testWidgets(
    'passes the profile photo URL through to the header level badge',
    (WidgetTester tester) async {
      const photoUrl =
          'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: null,
              streakCount: 0,
              unreadNotificationCount: 0,
              profileInitials: 'MT',
              profilePhotoUrl: photoUrl,
              levelBadgeLabel: 'Lv.3',
              levelProgressFraction: 0.5,
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<RuniacLevelProfileBadge>(
          find.byType(RuniacLevelProfileBadge),
        ).photoUrl,
        photoUrl,
      );
    },
  );

  testWidgets('active plan renders stage stones and a tappable today stage', (
    WidgetTester tester,
  ) async {
    final plan = _plan();
    final model = _model(plan);
    var todayTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            model: model,
            streakCount: 0,
            onNotifications: () {},
            onProfile: () {},
            onTapTodayStage: () => todayTaps++,
          ),
        ),
      ),
    );
    // Do not settle: today's stage runs a gentle repeating pulse.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _assetImageCount(
        tester,
        'assets/images/home/stages/dashboard_stage_run.png',
      ),
      greaterThan(0),
    );
    expect(
      _assetImageCount(
        tester,
        'assets/images/home/stages/dashboard_stage_rest.png',
      ),
      greaterThan(0),
    );

    final todayStage = find.bySemanticsLabel("Today's stage");
    expect(todayStage, findsOneWidget);
    await tester.tap(todayStage);
    await tester.pump();
    expect(todayTaps, 1);

    // At least one weekday caption (e.g. MON) renders near the stones.
    expect(find.text('MON'), findsWidgets);
  });

  testWidgets('weekday captions stay attached to their stage stones', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = _plan();
    final model = _model(plan);
    final firstWeekNumber = model.sections.first.weekNumber;
    const dayIndex = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            model: model,
            onNotifications: () {},
            onProfile: () {},
            onTapTodayStage: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final stoneRect = tester.getRect(
      find.byKey(ValueKey<String>('homeStageStone-$firstWeekNumber-$dayIndex')),
    );
    final labelRect = tester.getRect(
      find.byKey(
        ValueKey<String>('homeStageDayLabel-$firstWeekNumber-$dayIndex'),
      ),
    );

    expect(labelRect.center.dx, closeTo(stoneRect.center.dx, 0.5));
    expect(labelRect.top, greaterThan(stoneRect.center.dy));
    expect(labelRect.top, lessThan(stoneRect.bottom));
    expect(labelRect.bottom, closeTo(stoneRect.bottom, 6));
  });

  testWidgets(
    'guide scales to its stone and starts at the nearest valid Home-map '
    'scroll position',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final plan = _plan();
      final model = _model(plan);
      final firstWeekNumber = model.sections.first.weekNumber;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: model,
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final stoneFinders = <Finder>[
        for (var dayIndex = 0; dayIndex < kHomeStageDaysPerWeek; dayIndex++)
          find.byKey(
            ValueKey<String>('homeStageStone-$firstWeekNumber-$dayIndex'),
          ),
      ];
      for (final stoneFinder in stoneFinders) {
        expect(stoneFinder, findsOneWidget);
      }

      final stoneSize = tester.getSize(stoneFinders.first);
      expect(stoneSize.width, inInclusiveRange(92, 108));
      expect(stoneSize.height, stoneSize.width);
      for (final stoneFinder in stoneFinders.skip(1)) {
        expect(tester.getSize(stoneFinder), stoneSize);
      }

      final centers = [
        for (final stoneFinder in stoneFinders) tester.getCenter(stoneFinder),
      ];
      expect(centers.first.dx, closeTo(centers.last.dx, 1));
      expect(centers.first.dx - centers[3].dx, greaterThan(80));
      expect(centers[0].dx, greaterThan(centers[1].dx));
      expect(centers[1].dx, greaterThan(centers[2].dx));
      expect(centers[2].dx, greaterThan(centers[3].dx));
      expect(centers[4].dx, greaterThan(centers[3].dx));
      expect(centers[5].dx, greaterThan(centers[4].dx));
      expect(centers[6].dx, greaterThan(centers[5].dx));

      final secondWeekNumber = model.sections[1].weekNumber;
      final lowerEnd = tester.getCenter(stoneFinders.last);
      final upperStart = tester.getCenter(
        find.byKey(ValueKey<String>('homeStageStone-$secondWeekNumber-0')),
      );
      expect(lowerEnd.dx, closeTo(upperStart.dx, 1));

      final characterSize = tester.getSize(
        find.byKey(const ValueKey<String>('homeStageCharacter')),
      );
      expect(characterSize.width, closeTo(stoneSize.width * 0.86, 0.1));
      // Feet-anchored standing pose: the body rises above the stone, so the
      // sprite is taller than the stone while staying narrower than it.
      expect(characterSize.height, greaterThan(stoneSize.height));
      expect(
        characterSize.height / characterSize.width,
        closeTo(289 / 193, 0.01),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.pixels, greaterThan(0));
      final homeMapSize = tester.getSize(find.byType(HomeStageMap));
      final characterCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('homeStageCharacter')),
      );
      expect(characterCenter.dy, greaterThanOrEqualTo(homeMapSize.height / 3));
      expect(characterCenter.dy, lessThan(homeMapSize.height));
    },
  );

  testWidgets('guide character stands on top of its current stage stone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = _plan();
    final model = _model(plan);
    final firstWeekNumber = model.sections.first.weekNumber;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            model: model,
            onNotifications: () {},
            onProfile: () {},
            onTapTodayStage: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final currentStoneFinder = find.byKey(
      ValueKey<String>(
        'homeStageStone-$firstWeekNumber-${model.characterDayIndex}',
      ),
    );
    final characterFinder = find.byKey(
      const ValueKey<String>('homeStageCharacter'),
    );

    final stoneRect = tester.getRect(currentStoneFinder);
    final characterRect = tester.getRect(characterFinder);

    // The character stands centred on its stage stone horizontally, inside
    // the stone's footprint so it never blocks adjacent stages.
    expect(characterRect.center.dx, closeTo(stoneRect.center.dx, 0.5));
    expect(characterRect.width, lessThanOrEqualTo(stoneRect.width));

    // Feet-anchored: the sprite bottom, minus the shared transparent foot
    // inset (2% of sprite height), rests on the stone's standing surface —
    // 46% of the stone's height down from its top edge (the visible face
    // of the perspective plate).
    final expectedFootY = stoneRect.top + stoneRect.height * 0.46;
    final footY = characterRect.bottom - characterRect.height * 0.02;
    expect(footY, closeTo(expectedFootY, 1.0));

    // The body rises above the stone, and the feet stay above the stone's
    // bottom edge so the plate remains visible beneath the character.
    expect(characterRect.top, lessThan(stoneRect.top));
    expect(characterRect.bottom, lessThan(stoneRect.bottom));
  });

  testWidgets(
    'an early current stage clamps the landing scroll instead of forcing the '
    'lower-third position',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The default plan's current stage is the very first stage (week 1,
      // day 1), which sits too close to the map's natural start for the
      // lower-third landing target to be reachable.
      final plan = _plan();
      final model = _model(plan);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: model,
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      // The requested lower-third target is unreachable this close to the
      // map's start, so the scroll rests at its clamped natural extreme
      // rather than being forced past it.
      expect(
        scrollable.position.pixels,
        closeTo(scrollable.position.maxScrollExtent, 1.0),
      );

      final homeMapSize = tester.getSize(find.byType(HomeStageMap));
      final characterCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('homeStageCharacter')),
      );
      // Because the scroll was clamped, the character does not land exactly
      // at the lower-third mark; it rests further down the viewport instead.
      expect(characterCenter.dy, greaterThan(homeMapSize.height * 2 / 3 + 20));
    },
  );

  testWidgets(
    'a later current stage lands the character at the lower third of the '
    'viewport '
    'without clamping',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final plan = _plan();
      final model = _modelAtMiddleWeek(plan);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: model,
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      // A middle-plan stage is far from both scroll extremes, so the
      // requested lower-third target is fully reachable and not clamped.
      expect(scrollable.position.pixels, greaterThan(1.0));
      expect(
        scrollable.position.pixels,
        lessThan(scrollable.position.maxScrollExtent - 1.0),
      );

      // The landing scroll centres the rendered character box one-third up
      // from the viewport bottom, rather than centring its stage stone.
      final homeMapSize = tester.getSize(find.byType(HomeStageMap));
      final middleWeekNumber = plan.weeks[plan.weeks.length ~/ 2].weekNumber;
      final stoneRect = tester.getRect(
        find.byKey(
          ValueKey<String>(
            'homeStageStone-$middleWeekNumber-${model.characterDayIndex}',
          ),
        ),
      );
      final characterRect = tester.getRect(
        find.byKey(const ValueKey<String>('homeStageCharacter')),
      );
      expect(characterRect.center.dy, closeTo(homeMapSize.height * 2 / 3, 2.0));

      final initialPixels = scrollable.position.pixels;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 96),
      );
      await tester.pump();
      await tester.pump();
      expect(scrollable.position.pixels, lessThan(initialPixels - 20));

      // The character remains feet-anchored to that stone.
      expect(characterRect.bottom, greaterThan(stoneRect.top));
      expect(characterRect.bottom, lessThan(stoneRect.bottom));
    },
  );

  testWidgets(
    'homeStoneCluster anchor tightly bounds today\'s stone and its '
    'immediate neighbours (widened to the nearest day of the missing kind '
    'when the ±1 window is all-run or all-rest), clamped to the current '
    'week section',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final registry = TutorialAnchorRegistry();
      final plan = _plan();
      final model = _model(plan);
      final weekIndex = model.currentWeekIndex!;
      final weekNumber = model.sections[weekIndex].weekNumber;
      final stones = model.sections[weekIndex].stones;
      final todayIndex = stones.indexWhere((stone) => stone.isCurrent);
      expect(todayIndex, greaterThanOrEqualTo(0));
      var firstIndex = (todayIndex - 1).clamp(0, kHomeStageDaysPerWeek - 1);
      var lastIndex = (todayIndex + 1).clamp(0, kHomeStageDaysPerWeek - 1);

      // Mirrors `_buildStoneClusterAnchor`'s run/rest-mix widening: this
      // plan's four consecutive run days (Mon-Thu) put today (Monday) in an
      // all-run ±1 window, so the anchor is expected to widen to the
      // nearest rest day (Friday, index 4) rather than staying at ±1.
      final hasRun = stones
          .sublist(firstIndex, lastIndex + 1)
          .any((s) => s.isRun);
      final hasRest = stones
          .sublist(firstIndex, lastIndex + 1)
          .any((s) => !s.isRun);
      if (!hasRun || !hasRest) {
        final needRun = !hasRun;
        int? nearestIndex;
        var nearestDistance = stones.length;
        for (var d = 0; d < stones.length; d++) {
          if (stones[d].isRun != needRun) {
            continue;
          }
          final distance = (d - todayIndex).abs();
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearestIndex = d;
          }
        }
        if (nearestIndex != null) {
          firstIndex = firstIndex < nearestIndex ? firstIndex : nearestIndex;
          lastIndex = lastIndex > nearestIndex ? lastIndex : nearestIndex;
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: TutorialAnchorScope(
            registry: registry,
            child: Scaffold(
              body: HomeStageMap(
                model: model,
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final clusterRect = registry.rectFor(TutorialAnchorId.homeStoneCluster);
      expect(clusterRect, isNotNull);

      final stoneRects = [
        for (var d = firstIndex; d <= lastIndex; d++)
          tester.getRect(
            find.byKey(ValueKey<String>('homeStageStone-$weekNumber-$d')),
          ),
      ];
      double minOf(Iterable<double> values) =>
          values.reduce((a, b) => a < b ? a : b);
      double maxOf(Iterable<double> values) =>
          values.reduce((a, b) => a > b ? a : b);
      const clusterPadding = 6.0;
      final expectedLeft = minOf(stoneRects.map((r) => r.left)) - clusterPadding;
      final expectedTop = minOf(stoneRects.map((r) => r.top)) - clusterPadding;
      final expectedRight =
          maxOf(stoneRects.map((r) => r.right)) + clusterPadding;
      final expectedBottom =
          maxOf(stoneRects.map((r) => r.bottom)) + clusterPadding;

      expect(clusterRect!.left, closeTo(expectedLeft, 1.0));
      expect(clusterRect.top, closeTo(expectedTop, 1.0));
      expect(clusterRect.right, closeTo(expectedRight, 1.0));
      expect(clusterRect.bottom, closeTo(expectedBottom, 1.0));
    },
  );

  testWidgets(
    'homeStoneCluster anchor stays well under half the screen area on a '
    'standard phone viewport, so the tour cuts a real spotlight hole '
    'instead of degrading to a full-screen dim',
    (WidgetTester tester) async {
      const size = Size(402, 874);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final registry = TutorialAnchorRegistry();
      final plan = _plan();
      final model = _model(plan);

      await tester.pumpWidget(
        MaterialApp(
          home: TutorialAnchorScope(
            registry: registry,
            child: Scaffold(
              body: HomeStageMap(
                model: model,
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final clusterRect = registry.rectFor(TutorialAnchorId.homeStoneCluster);
      expect(clusterRect, isNotNull);

      final screenArea = size.width * size.height;
      final clusterArea = clusterRect!.width * clusterRect.height;
      expect(clusterArea, lessThan(screenArea * 0.5));
    },
  );

  testWidgets('tapping today stage in the app opens the workout detail', (
    WidgetTester tester,
  ) async {
    final monday = DateTime(2026, 6, 22); // a Monday
    final plan = _plan().withStartsOnDate(generatedPlanDateLabel(monday));
    final store = CurrentSessionGeneratedPlanStore();
    expect(store.setActivePlan(plan), isTrue);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        youProgressToday: monday,
        currentSessionGeneratedPlanStore: store,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final todayStage = find.bySemanticsLabel("Today's stage");
    expect(todayStage, findsOneWidget);

    await tester.tap(todayStage);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Workout detail'), findsOneWidget);
  });

  group('guide speech bubble', () {
    const characterTapTarget = ValueKey<String>('homeGuideCharacterTapTarget');
    const bubbleBody = ValueKey<String>('homeGuideBubbleBody');
    const bubble = ValueKey<String>('homeGuideBubble');

    testWidgets('hides the guide until consent is granted', (
      WidgetTester tester,
    ) async {
      final agent = _ControlledGuideAgent();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: _model(_plan()),
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
              guideAgent: agent,
              guideRequest: _guideRequest,
              guideConsentStatus: HomeGuideConsentStatus.notGranted,
            ),
          ),
        ),
      );
      await tester.pump();

      // Without consent the guide never calls the remote agent and shows no
      // bubble or inline consent prompt. Consent now lives in the onboarding
      // sheet and Account → Privacy & Safety.
      expect(agent.invocationCount, 0);
      expect(find.byKey(bubble), findsNothing);
      expect(
        find.text('Personalize your guide with recent run totals.'),
        findsNothing,
      );
    });

    testWidgets(
      'shows the on-device plan brief even without data-use consent',
      (WidgetTester tester) async {
        // The consent covers sending run data to the AI provider. A guide that
        // sends nothing is not gated by it, so a runner who declined still
        // reads their own plan instead of losing the bubble entirely.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: _model(_plan()),
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: const PlanBriefHomeGuideAgent(),
                guideRequest: _stepGuideRequest,
                guideConsentStatus: HomeGuideConsentStatus.notGranted,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(bubble), findsOneWidget);
        expect(
          find.textContaining(
            "Today's Mon session is Easy Run for about 20 minutes.",
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'plan brief lists every step at once and does not advance on tap',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: _model(_plan()),
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: const PlanBriefHomeGuideAgent(),
                guideRequest: _stepGuideRequest,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final body = tester.widget<Text>(
          find.descendant(of: find.byKey(bubbleBody), matching: find.byType(Text)),
        );
        expect(body.data, contains('1. Warm up 5 minutes'));
        expect(body.data, contains('2. Run 10 minutes easy'));
        expect(body.data, contains('3. Cool down 5 minutes'));
        expect(
          find.bySemanticsLabel("Today's plan and its steps."),
          findsOneWidget,
        );

        // A single message has nowhere to advance to: tapping leaves the same
        // copy on screen rather than cycling to AI-only content.
        await tester.tap(find.byKey(bubbleBody));
        await tester.pump();
        expect(find.textContaining('1. Warm up 5 minutes'), findsOneWidget);
      },
    );

    testWidgets(
      'shows the guide bubble without a data-use shield after consent',
      (WidgetTester tester) async {
        final agent = _ControlledGuideAgent();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: _model(_plan()),
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: agent,
                guideRequest: _guideRequest,
                guideConsentStatus: HomeGuideConsentStatus.granted,
              ),
            ),
          ),
        );
        await tester.pump();
        agent.completeNext(_guideBundle());
        await tester.pump();
        await tester.pump();

        expect(find.byKey(bubble), findsOneWidget);
        expect(find.bySemanticsLabel('Manage guide data use'), findsNothing);
      },
    );

    testWidgets('shows rest-day encouragement on a rest day', (
      WidgetTester tester,
    ) async {
      final plan = _plan();
      final model = _model(plan);
      const agent = RuleBasedHomeGuideAgent();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: model,
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
              guideAgent: agent,
              guideRequest: _restGuideRequest,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(bubble), findsOneWidget);
      expect(find.textContaining('rest day'), findsOneWidget);
      // Accessibility label is rest-flavored, not "Plan summary".
      expect(
        find.bySemanticsLabel('Rest-day cheer. Tap to hear a rest tip.'),
        findsOneWidget,
      );

      // The rest bundle still cycles through its three messages on tap.
      await tester.tap(find.byKey(bubbleBody));
      await tester.pump();
      expect(find.textContaining('Rest-day tip:'), findsOneWidget);
    });

    testWidgets(
      'auto-opens summary and cycles tip, progression, then summary once',
      (WidgetTester tester) async {
        final plan = _plan();
        final model = _model(plan);
        final agent = _ControlledGuideAgent();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: model,
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: agent,
                guideRequest: _guideRequest,
              ),
            ),
          ),
        );
        await tester.pump();
        agent.completeNext(_guideBundle());
        await tester.pump();
        await tester.pump();

        expect(find.byKey(characterTapTarget), findsOneWidget);
        expect(find.text('Summary is ready.'), findsOneWidget);

        await tester.tap(find.byKey(bubbleBody));
        await tester.pump();
        expect(find.text('Tip is ready.'), findsOneWidget);

        await tester.tap(find.byKey(bubbleBody));
        await tester.pump();
        expect(find.text('Progression is ready.'), findsOneWidget);

        await tester.tap(find.byKey(bubbleBody));
        await tester.pump();
        expect(find.text('Summary is ready.'), findsOneWidget);
        expect(agent.invocationCount, 1);
      },
    );

    testWidgets('dismissing hides it and character reopens the current tip', (
      WidgetTester tester,
    ) async {
      final plan = _plan();
      final model = _model(plan);
      final agent = _ControlledGuideAgent();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: model,
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
              guideAgent: agent,
              guideRequest: _guideRequest,
            ),
          ),
        ),
      );
      await tester.pump();
      agent.completeNext(_guideBundle());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(bubbleBody));
      await tester.pump();
      expect(find.text('Tip is ready.'), findsOneWidget);

      await Scrollable.ensureVisible(
        tester.element(find.bySemanticsLabel('Close guide message')),
        alignment: 0.35,
      );
      await tester.tap(find.bySemanticsLabel('Close guide message'));
      await tester.pump();

      expect(find.byKey(bubble), findsNothing);

      await Scrollable.ensureVisible(
        tester.element(find.byKey(characterTapTarget)),
        alignment: 0.5,
      );
      await tester.tap(find.byKey(characterTapTarget));
      await tester.pump();

      expect(find.text('Tip is ready.'), findsOneWidget);
      expect(agent.invocationCount, 1);
    });

    testWidgets(
      'resets to summary for a changed stage and suppresses no plan',
      (WidgetTester tester) async {
        final plan = _plan();
        final initialModel = _model(plan);
        final nextModel = HomeStageMapModel(
          sections: initialModel.sections,
          currentWeekIndex: initialModel.currentWeekIndex,
          todayDayIndex: 2,
          characterDayIndex: 2,
          currentStageId: '0:2',
        );
        final agent = _ControlledGuideAgent();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: initialModel,
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: agent,
                guideRequest: _guideRequest,
              ),
            ),
          ),
        );
        await tester.pump();
        agent.completeNext(_guideBundle());
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(bubbleBody));
        await tester.pump();
        expect(find.text('Tip is ready.'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: nextModel,
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: agent,
                guideRequest: _guideRequest,
              ),
            ),
          ),
        );
        await tester.pump();
        agent.completeNext(_guideBundle(planSummary: 'New summary is ready.'));
        await tester.pump();
        await tester.pump();
        expect(find.text('New summary is ready.'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: null,
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: agent,
                guideRequest: _guideRequest,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(characterTapTarget), findsNothing);
        expect(find.byKey(bubble), findsNothing);
        expect(agent.invocationCount, 2);
      },
    );

    testWidgets('loading disables advance and error shows the fallback', (
      WidgetTester tester,
    ) async {
      final agent = _ControlledGuideAgent();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStageMap(
              model: _model(_plan()),
              onNotifications: () {},
              onProfile: () {},
              onTapTodayStage: () {},
              guideAgent: agent,
              guideRequest: _guideRequest,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Preparing your guide...'), findsOneWidget);
      await tester.tap(find.byKey(bubbleBody));
      await tester.pump();
      expect(agent.invocationCount, 1);

      agent.completeNextError(StateError('unavailable'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text("Let's get moving — you've got this today."),
        findsOneWidget,
      );
    });

    testWidgets('renders valid near-limit copy at narrow large-text widths', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(320, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final agent = _ControlledGuideAgent();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: HomeStageMap(
                model: _model(_plan()),
                onNotifications: () {},
                onProfile: () {},
                onTapTodayStage: () {},
                guideAgent: agent,
                guideRequest: _guideRequest,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      agent.completeNext(_nearLimitGuideBundle());
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(find.byKey(bubble)).width, lessThanOrEqualTo(280));
      expect(find.text(_nearLimitPlanSummary), findsOneWidget);
      expect(
        find.bySemanticsLabel('Plan summary. Tap to hear a running tip.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Close guide message'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.bySemanticsLabel('Close guide message'));
      await tester.pump();
      expect(find.byKey(bubble), findsNothing);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(characterTapTarget)),
        alignment: 0.5,
      );
      await tester.tap(find.byKey(characterTapTarget));
      await tester.pump();
      expect(find.text(_nearLimitPlanSummary), findsOneWidget);
      expect(agent.invocationCount, 1);

      tester.view.physicalSize = const Size(360, 844);
      await tester.pump();
      expect(tester.getSize(find.byKey(bubble)).width, lessThanOrEqualTo(280));
      expect(find.text(_nearLimitPlanSummary), findsOneWidget);
      expect(
        find.bySemanticsLabel('Plan summary. Tap to hear a running tip.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Close guide message'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Close guide message'));
      await tester.pump();
      expect(find.byKey(bubble), findsNothing);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      semantics.dispose();
    });
  });
}

const String _nearLimitPlanSummary =
    'Take an easy rhythm, let your breath stay calm, and follow today’s plan with patience. If the pace feels demanding, slow down and finish feeling comfortable.';

HomeGuideBundle _nearLimitGuideBundle() {
  final bundle = HomeGuideBundle.tryCreate(
    planSummary: _nearLimitPlanSummary,
    runningTip: 'Relax your shoulders and keep each step light.',
    progressionCheckIn: 'A calm baseline gives your next run a strong start.',
    isFromRemoteAgent: false,
  );
  if (bundle == null) {
    throw StateError('Near-limit fixture must satisfy the display contract.');
  }
  return bundle;
}

HomeGuideBundle _guideBundle({String planSummary = 'Summary is ready.'}) {
  return HomeGuideBundle(
    planSummary: HomeGuideMessage(
      kind: HomeGuideMessageKind.planSummary,
      text: planSummary,
    ),
    runningTip: const HomeGuideMessage(
      kind: HomeGuideMessageKind.runningTip,
      text: 'Tip is ready.',
    ),
    progressionCheckIn: const HomeGuideMessage(
      kind: HomeGuideMessageKind.progressionCheckIn,
      text: 'Progression is ready.',
    ),
    isFromRemoteAgent: false,
  );
}

class _ControlledGuideAgent implements HomeGuideAgent {
  final List<Completer<HomeGuideBundle>> _pending =
      <Completer<HomeGuideBundle>>[];

  int invocationCount = 0;

  /// Stands in for the remote AI guide, which is the only guide the
  /// personalized-data-use consent gates.
  @override
  bool get requiresDataConsent => true;

  @override
  Future<HomeGuideBundle> explainTodayPlan(HomeGuideRequest request) {
    invocationCount += 1;
    final completer = Completer<HomeGuideBundle>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext(HomeGuideBundle bundle) {
    _pending.removeAt(0).complete(bundle);
  }

  void completeNextError(Object error) {
    _pending.removeAt(0).completeError(error);
  }
}
