import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_steps.dart';
import 'package:runiac_app/features/tutorial/domain/models/tutorial_step.dart';
import 'package:runiac_app/features/tutorial/presentation/app_tour_overlay.dart';
import 'package:runiac_app/features/tutorial/presentation/spotlight_scrim_painter.dart';

const _step = TutorialStep(
  id: 'home-today-stone',
  tabIndex: 0,
  message: "This is today's stone on your plan, {guide}.",
  fallbackMessage: 'Your weekly plan lands here as a path of stones.',
);

/// Mirrors [_step] but adds a `restDayMessage`, for the `isRestDay` copy
/// resolution tests below.
const _restDayCapableStep = TutorialStep(
  id: 'home-today-stone',
  tabIndex: 0,
  message: "This is today's stone on your plan, {guide}.",
  fallbackMessage: 'Your weekly plan lands here as a path of stones.',
  restDayMessage: "Today's stone is a rest day, {guide}.",
);

/// A copy of the longest message across every `message`, `fallbackMessage`,
/// and `restDayMessage` in `runiacAppTourSteps` (the `home-rest-streak`
/// step's default `message`, at 117 characters — longer than any of the
/// rest-day variants added alongside it), hardcoded rather than imported so
/// this regression test stays stable regardless of concurrent edits to the
/// tour script.
const _longestCopyStep = TutorialStep(
  id: 'home-rest-streak',
  tabIndex: 0,
  message:
      'Rest days are part of the plan, not a break from it. They '
      "won't break your streak — only skipping a running day does.",
);

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: disableAnimations,
      textScaler: textScaler,
    ),
    child: MaterialApp(home: child),
  );
}

/// Pumps [child] at a real physical window size (not just a `MediaQuery`
/// override), so `tester.tap()` coordinates line up with what actually
/// renders — required for the narrow-width tap-target assertions below.
Future<void> _pumpAtPhysicalSize(
  WidgetTester tester,
  Widget child, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _wrap(child, disableAnimations: true, size: size, textScaler: textScaler),
  );
  await tester.pump();
}

SpotlightScrimPainter _scrimPainter(WidgetTester tester) {
  return tester
      .widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is SpotlightScrimPainter,
        ),
      )
      .painter as SpotlightScrimPainter;
}

void main() {
  testWidgets('renders resolved copy and the character display name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () {},
          onSkip: () {},
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    expect(find.text('Cap'), findsOneWidget);
    expect(
      find.text(resolveTutorialCopy(_step.message, RunnerCharacter.cap)),
      findsOneWidget,
    );
  });

  testWidgets('useFallbackCopy renders fallback text instead of main text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: null,
          useFallbackCopy: true,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () {},
          onSkip: () {},
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    expect(
      find.text(
        resolveTutorialCopy(_step.effectiveFallbackMessage, RunnerCharacter.cap),
      ),
      findsOneWidget,
    );
    expect(
      find.text(resolveTutorialCopy(_step.message, RunnerCharacter.cap)),
      findsNothing,
    );
  });

  testWidgets(
    'isRestDay: true renders restDayMessage instead of message when the '
    'step defines one',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _restDayCapableStep,
            hole: null,
            useFallbackCopy: false,
            isRestDay: true,
            character: RunnerCharacter.cap,
            stepIndex: 0,
            stepCount: 9,
            onNext: () {},
            onSkip: () {},
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(
        find.text(
          resolveTutorialCopy(
            _restDayCapableStep.restDayMessage,
            RunnerCharacter.cap,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          resolveTutorialCopy(_restDayCapableStep.message, RunnerCharacter.cap),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'isRestDay: false and isRestDay: null both render message unchanged, '
    'even for a step that defines a restDayMessage',
    (tester) async {
      for (final isRestDay in <bool?>[false, null]) {
        await tester.pumpWidget(
          _wrap(
            AppTourOverlay(
              step: _restDayCapableStep,
              hole: null,
              useFallbackCopy: false,
              isRestDay: isRestDay,
              character: RunnerCharacter.cap,
              stepIndex: 0,
              stepCount: 9,
              onNext: () {},
              onSkip: () {},
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump();

        expect(
          find.text(
            resolveTutorialCopy(
              _restDayCapableStep.message,
              RunnerCharacter.cap,
            ),
          ),
          findsOneWidget,
          reason: 'isRestDay: $isRestDay',
        );
      }
    },
  );

  testWidgets(
    'useFallbackCopy still wins over isRestDay: true — an unresolved anchor '
    'shows the generic fallback, never the rest-day variant',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _restDayCapableStep,
            hole: null,
            useFallbackCopy: true,
            isRestDay: true,
            character: RunnerCharacter.cap,
            stepIndex: 0,
            stepCount: 9,
            onNext: () {},
            onSkip: () {},
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(
        find.text(
          resolveTutorialCopy(
            _restDayCapableStep.effectiveFallbackMessage,
            RunnerCharacter.cap,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          resolveTutorialCopy(
            _restDayCapableStep.restDayMessage,
            RunnerCharacter.cap,
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('tapping Next fires onNext exactly once', (tester) async {
    var nextCount = 0;
    var skipCount = 0;
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
    await tester.pump();

    expect(nextCount, 1);
    expect(skipCount, 0);
  });

  testWidgets('tapping Skip tour fires onSkip exactly once', (tester) async {
    var nextCount = 0;
    var skipCount = 0;
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('appTourSkipButton')));
    await tester.pump();

    expect(skipCount, 1);
    expect(nextCount, 0);
  });

  testWidgets(
    'step progress announces "2 of 9" to screen readers for stepIndex 1, '
    'stepCount 9',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _step,
            hole: null,
            useFallbackCopy: false,
            character: RunnerCharacter.cap,
            stepIndex: 1,
            stepCount: 9,
            onNext: () {},
            onSkip: () {},
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      final counterFinder = find.byKey(const ValueKey('appTourStepCounter'));
      expect(counterFinder, findsOneWidget);
      // The counter no longer renders "N of M" as literal text (it is now a
      // compact segmented progress cue), so its phrasing must still reach
      // assistive tech via `Semantics`.
      expect(
        tester.widget<Semantics>(counterFinder).properties.label,
        '2 of 9',
      );
      expect(find.text('2 of 9'), findsNothing);
    },
  );

  testWidgets(
    'flips the bubble above a bottom-nav-shaped hole so it never overlaps it',
    (tester) async {
      const size = Size(390, 844);
      final hole = Rect.fromLTWH(0, size.height - 56, size.width, 56);
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _step,
            hole: hole,
            useFallbackCopy: false,
            character: RunnerCharacter.cap,
            stepIndex: 0,
            stepCount: 9,
            onNext: () {},
            onSkip: () {},
          ),
          disableAnimations: true,
          size: size,
        ),
      );
      await tester.pump();

      final bubbleRect = tester.getRect(
        find.byKey(const ValueKey('appTourBubbleBody')),
      );
      expect(bubbleRect.bottom, lessThanOrEqualTo(hole.top));
    },
  );

  testWidgets('places the bubble below a hole near the top of the screen', (
    tester,
  ) async {
    const size = Size(390, 844);
    const hole = Rect.fromLTWH(20, 0, 60, 56);
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: hole,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () {},
          onSkip: () {},
        ),
        disableAnimations: true,
        size: size,
      ),
    );
    await tester.pump();

    final bubbleRect = tester.getRect(
      find.byKey(const ValueKey('appTourBubbleBody')),
    );
    expect(bubbleRect.top, greaterThanOrEqualTo(hole.bottom));
  });

  testWidgets(
    'a normal card-sized hole in the middle of the screen keeps today\'s '
    'placement behaviour',
    (tester) async {
      const size = Size(390, 844);
      // Small enough to be far under the oversized-hole area threshold, and
      // centred so neither spaceAbove nor spaceBelow is starved.
      const hole = Rect.fromLTWH(150, 380, 90, 90);
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _step,
            hole: hole,
            useFallbackCopy: false,
            character: RunnerCharacter.cap,
            stepIndex: 0,
            stepCount: 9,
            onNext: () {},
            onSkip: () {},
          ),
          disableAnimations: true,
          size: size,
        ),
      );
      await tester.pump();

      // spaceBelow (844 - 12 - 470 = 362) clears the 190 clearance, so the
      // original heuristic (and this one) places the block below the hole.
      final bubbleRect = tester.getRect(
        find.byKey(const ValueKey('appTourBubbleBody')),
      );
      expect(bubbleRect.top, greaterThanOrEqualTo(hole.bottom));
      expect(_scrimPainter(tester).hole, isNotNull);
    },
  );

  testWidgets(
    'a hole spanning the entire screen keeps the block fully on screen and '
    'the Next button real-tappable',
    (tester) async {
      // Wide enough that the bubble's Skip/counter/Next control row has
      // enough horizontal room to lay out without overflowing — a pre-
      // existing layout budget unrelated to this defect (reproducible with
      // `hole: null` on unmodified code at a 390-wide viewport). Kept wide
      // here purely so this test isolates the placement/painter behaviour
      // this fix is responsible for.
      const size = Size(600, 844);
      // The bound checks below compare against the real render surface, so
      // the test viewport must actually match the `size` used to compute
      // placement — otherwise a mismatched default test window would make
      // this assertion meaningless.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hole = Rect.fromLTWH(0, 0, size.width, size.height);
      var nextCount = 0;
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _step,
            hole: hole,
            useFallbackCopy: false,
            character: RunnerCharacter.cap,
            stepIndex: 0,
            stepCount: 9,
            onNext: () => nextCount++,
            onSkip: () {},
          ),
          disableAnimations: true,
          size: size,
        ),
      );
      await tester.pump();

      final screenBounds = Offset.zero & size;
      final bubbleRect = tester.getRect(
        find.byKey(const ValueKey('appTourBubbleBody')),
      );
      expect(screenBounds.contains(bubbleRect.topLeft), isTrue);
      expect(screenBounds.contains(bubbleRect.bottomRight), isTrue);

      // The whole-screen hole cannot act as a spotlight, so the painter must
      // fall back to the plain full-screen dim (no cut-out).
      expect(_scrimPainter(tester).hole, isNull);

      await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
      await tester.pump();
      expect(nextCount, 1);
    },
  );

  testWidgets(
    'a hole covering ~90% of the screen renders in no-hole mode',
    (tester) async {
      // See the "entire screen" test above for why this is wider than a
      // typical phone viewport.
      const size = Size(600, 844);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // 540 x 814 out of 600 x 844 is ~90% of the screen area.
      const hole = Rect.fromLTWH(20, 15, 540, 814);
      await tester.pumpWidget(
        _wrap(
          AppTourOverlay(
            step: _step,
            hole: hole,
            useFallbackCopy: false,
            character: RunnerCharacter.cap,
            stepIndex: 0,
            stepCount: 9,
            onNext: () {},
            onSkip: () {},
          ),
          disableAnimations: true,
          size: size,
        ),
      );
      await tester.pump();

      expect(_scrimPainter(tester).hole, isNull);

      final screenBounds = Offset.zero & size;
      final bubbleRect = tester.getRect(
        find.byKey(const ValueKey('appTourBubbleBody')),
      );
      expect(screenBounds.contains(bubbleRect.topLeft), isTrue);
      expect(screenBounds.contains(bubbleRect.bottomRight), isTrue);
    },
  );

  testWidgets('shows full copy on the very first pump under disableAnimations', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () {},
          onSkip: () {},
        ),
        disableAnimations: true,
      ),
    );
    // No pumpAndSettle: the full copy must already be present on the very
    // first frame when animations are disabled.

    expect(
      find.text(resolveTutorialCopy(_step.message, RunnerCharacter.cap)),
      findsOneWidget,
    );
  });

  testWidgets('a scrim tap away from the buttons fires neither callback', (
    tester,
  ) async {
    var nextCount = 0;
    var skipCount = 0;
    await tester.pumpWidget(
      _wrap(
        AppTourOverlay(
          step: _step,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 0,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    // Tap near the top-left corner of the screen, well away from the bubble
    // (pinned to the bottom in no-hole mode) and its buttons.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(nextCount, 0);
    expect(skipCount, 0);
  });

  testWidgets(
    'no RenderFlex overflow at a 375x812 narrow phone width with the '
    'longest step copy, and both buttons stay tappable',
    (tester) async {
      var nextCount = 0;
      var skipCount = 0;
      await _pumpAtPhysicalSize(
        tester,
        AppTourOverlay(
          step: _longestCopyStep,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 8,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        size: const Size(375, 812),
      );

      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
      await tester.pump();
      expect(nextCount, 1);

      await tester.tap(find.byKey(const ValueKey('appTourSkipButton')));
      await tester.pump();
      expect(skipCount, 1);
    },
  );

  testWidgets(
    'no RenderFlex overflow at a 375x812 narrow phone width with the '
    'longest step copy and a large text scale, and both buttons stay '
    'tappable',
    (tester) async {
      var nextCount = 0;
      var skipCount = 0;
      await _pumpAtPhysicalSize(
        tester,
        AppTourOverlay(
          step: _longestCopyStep,
          hole: null,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 8,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        size: const Size(375, 812),
        textScaler: const TextScaler.linear(2.0),
      );

      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
      await tester.pump();
      expect(nextCount, 1);

      await tester.tap(find.byKey(const ValueKey('appTourSkipButton')));
      await tester.pump();
      expect(skipCount, 1);
    },
  );

  testWidgets(
    'a hole leaving ~200-300px on the placed side does not clip the '
    'Next/Skip buttons off-screen at a narrow viewport and 2x text scale',
    (tester) async {
      var nextCount = 0;
      var skipCount = 0;
      const size = Size(375, 812);
      // Leaves ~238px above and ~250px below (safeTop/safeBottom are 12px
      // each here) — both comfortably above the old 190px clearance
      // heuristic (so the pre-fix code treated the gap as "usable" and
      // placed the block there) but well under the bubble's real 340px
      // maxHeight cap once the longest step copy is typed out at a 2x text
      // scale, so the pre-fix block was placed but rendered taller than the
      // gap, pushing its footer (Skip/Next) off the bottom of the screen.
      const hole = Rect.fromLTWH(40, 250, 295, 300);
      await _pumpAtPhysicalSize(
        tester,
        AppTourOverlay(
          step: _longestCopyStep,
          hole: hole,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 8,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        size: size,
        textScaler: const TextScaler.linear(2.0),
      );

      await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
      await tester.pump();
      expect(nextCount, 1);

      await tester.tap(find.byKey(const ValueKey('appTourSkipButton')));
      await tester.pump();
      expect(skipCount, 1);
    },
  );

  testWidgets(
    'when neither side can fit the block, degrades to no-hole mode with '
    'the block fully on screen and both buttons tappable',
    (tester) async {
      var nextCount = 0;
      var skipCount = 0;
      const size = Size(375, 812);
      // Same geometry as the test above: ~238px above, ~250px below — too
      // little room on either side for a block that can grow up to 340px,
      // so this must degrade to the plain full-screen dim with the block
      // pinned to the bottom safe area instead of being clipped in place.
      const hole = Rect.fromLTWH(40, 250, 295, 300);
      await _pumpAtPhysicalSize(
        tester,
        AppTourOverlay(
          step: _longestCopyStep,
          hole: hole,
          useFallbackCopy: false,
          character: RunnerCharacter.cap,
          stepIndex: 8,
          stepCount: 9,
          onNext: () => nextCount++,
          onSkip: () => skipCount++,
        ),
        size: size,
        textScaler: const TextScaler.linear(2.0),
      );

      expect(_scrimPainter(tester).hole, isNull);

      // Check the fixed footer controls, not the scrollable copy text: the
      // typed text's own render size is its full (potentially very tall)
      // intrinsic content height regardless of the scroll viewport clipping
      // it — that is the pre-existing, intentional reason it scrolls at
      // this copy length and text scale (see the "no RenderFlex overflow"
      // tests above) — so it is not itself a signal of whether the block
      // as a whole stayed on screen. The Skip/Next buttons are fixed
      // siblings below that scrollable region, so their rects are what
      // "fully on screen and tappable" actually means here.
      final screenBounds = Offset.zero & size;
      final nextRect = tester.getRect(
        find.byKey(const ValueKey('appTourNextButton')),
      );
      final skipRect = tester.getRect(
        find.byKey(const ValueKey('appTourSkipButton')),
      );
      expect(screenBounds.contains(nextRect.center), isTrue);
      expect(screenBounds.contains(skipRect.center), isTrue);

      await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
      await tester.pump();
      expect(nextCount, 1);

      await tester.tap(find.byKey(const ValueKey('appTourSkipButton')));
      await tester.pump();
      expect(skipCount, 1);
    },
  );
}
