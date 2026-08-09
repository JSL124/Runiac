import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/core/widgets/character_guidance_overlay.dart';

const _runDuration = Duration(milliseconds: 800);

/// `find.byTooltip` resolves the tooltip widget an [IconButton] builds around
/// its icon, so the button itself is its ancestor.
IconButton _buttonFor(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

List<CharacterGuidanceStep> _steps(int count) {
  return <CharacterGuidanceStep>[
    for (var index = 0; index < count; index += 1)
      CharacterGuidanceStep(
        title: 'Title $index',
        body: 'Body copy for step $index.',
      ),
  ];
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  int stepCount = 4,
  Future<List<CharacterGuidanceStep>> Function()? loadSteps,
  VoidCallback? onClose,
  String loadingCopy = 'Reading your plan...',
  String keyPrefix = 'activity_feedback',
  bool disableAnimations = false,
}) async {
  final originalSize = tester.view.physicalSize;
  final originalDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDevicePixelRatio;
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: disableAnimations,
          ),
          child: CharacterGuidanceOverlay(
            character: RunnerCharacter.pink,
            keyPrefix: keyPrefix,
            loadingCopy: loadingCopy,
            closeTooltip: 'Close guidance',
            previousTooltip: 'Previous guidance step',
            nextTooltip: 'Next guidance step',
            loadSteps: loadSteps ?? () async => _steps(stepCount),
            onClose: onClose ?? () {},
          ),
        ),
      ),
    ),
  );
}

Future<void> _settleArrival(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(_runDuration);
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('CharacterGuidanceOverlay paging', () {
    for (final count in <int>[2, 4, 6]) {
      testWidgets('renders a $count-step counter and pages to the end', (
        tester,
      ) async {
        await _pumpOverlay(tester, stepCount: count);
        await _settleArrival(tester);

        expect(find.text('1/$count'), findsOneWidget);
        expect(find.text('Title 0'), findsOneWidget);

        for (var index = 1; index < count; index += 1) {
          await tester.tap(find.byTooltip('Next guidance step'));
          await tester.pump();
          expect(find.text('${index + 1}/$count'), findsOneWidget);
          expect(find.text('Title $index'), findsOneWidget);
        }
      });
    }

    testWidgets('disables previous on the first step and next on the last', (
      tester,
    ) async {
      await _pumpOverlay(tester, stepCount: 3);
      await _settleArrival(tester);

      IconButton buttonFor(String tooltip) => _buttonFor(tester, tooltip);

      expect(buttonFor('Previous guidance step').onPressed, isNull);
      expect(buttonFor('Next guidance step').onPressed, isNotNull);

      await tester.tap(find.byTooltip('Next guidance step'));
      await tester.pump();
      await tester.tap(find.byTooltip('Next guidance step'));
      await tester.pump();

      expect(find.text('3/3'), findsOneWidget);
      expect(buttonFor('Previous guidance step').onPressed, isNotNull);
      expect(buttonFor('Next guidance step').onPressed, isNull);

      await tester.tap(find.byTooltip('Previous guidance step'));
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('a single step disables both paging controls', (tester) async {
      await _pumpOverlay(tester, stepCount: 1);
      await _settleArrival(tester);

      expect(find.text('1/1'), findsOneWidget);
      expect(_buttonFor(tester, 'Previous guidance step').onPressed, isNull);
      expect(_buttonFor(tester, 'Next guidance step').onPressed, isNull);
    });
  });

  group('CharacterGuidanceOverlay loading and keys', () {
    testWidgets('shows the supplied loading copy before steps resolve', (
      tester,
    ) async {
      final completer = Completer<List<CharacterGuidanceStep>>();
      await _pumpOverlay(
        tester,
        loadingCopy: 'Reading your plan...',
        loadSteps: () => completer.future,
      );
      await _settleArrival(tester);

      expect(find.text('Reading your plan...'), findsOneWidget);
      expect(find.text('Title 0'), findsNothing);
      expect(find.textContaining('/'), findsNothing);

      completer.complete(_steps(4));
      await tester.pump();
      await tester.pump();

      expect(find.text('Reading your plan...'), findsNothing);
      expect(find.text('Title 0'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
    });

    testWidgets('scopes every widget key to the supplied prefix', (
      tester,
    ) async {
      await _pumpOverlay(tester, keyPrefix: 'workout_briefing');
      await _settleArrival(tester);

      expect(find.byKey(const ValueKey('workout_briefing_barrier')), findsOne);
      expect(find.byKey(const ValueKey('workout_briefing_motion')), findsOne);
      expect(find.byKey(const ValueKey('workout_briefing_bubble')), findsOne);
      expect(
        find.byKey(const ValueKey('workout_briefing_idle_character')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('activity_feedback_barrier')),
        findsNothing,
      );
    });

    testWidgets('runs in before the bubble becomes visible', (tester) async {
      await _pumpOverlay(tester, keyPrefix: 'workout_briefing');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workout_briefing_running_character')),
        findsOne,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workout_briefing_bubble')),
            )
            .opacity,
        0,
      );

      await _settleArrival(tester);

      expect(
        find.byKey(const ValueKey('workout_briefing_idle_character')),
        findsOne,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workout_briefing_bubble')),
            )
            .opacity,
        1,
      );
    });

    testWidgets('reduced motion arrives immediately and closes without delay', (
      tester,
    ) async {
      var closed = 0;
      await _pumpOverlay(
        tester,
        keyPrefix: 'workout_briefing',
        disableAnimations: true,
        onClose: () => closed += 1,
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workout_briefing_idle_character')),
        findsOne,
      );

      await tester.tap(find.byTooltip('Close guidance'));
      await tester.pump();

      expect(closed, 1);
    });
  });
}
