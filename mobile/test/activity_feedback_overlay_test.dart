import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/run/domain/models/activity_feedback_agent.dart';
import 'package:runiac_app/features/run/presentation/widgets/activity_feedback_overlay.dart';

const _runLeftAsset = 'assets/images/characters/pink_runner_run_left.gif';
const _idleAsset = 'assets/images/characters/pink_runner_idle.gif';
const _reducedMotionAsset = 'assets/images/characters/pink_runner_front.png';
const _runDuration = Duration(milliseconds: 800);

const _bundle = ActivityFeedbackBundle(
  source: ActivityFeedbackSource.generated,
  sections: ActivityFeedbackSections(
    summary: 'Your run stayed calm and consistent.',
    wentWell: 'Your pacing stayed repeatable.',
    improve: 'Keep your first kilometre a little easier.',
    nextFocus: 'Aim for one relaxed, steady session next.',
  ),
);

Future<void> _pumpOverlay(
  WidgetTester tester, {
  RunnerCharacter character = RunnerCharacter.pink,
  Future<ActivityFeedbackBundle> Function()? loadFeedback,
  VoidCallback? onClose,
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
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
            textScaler: textScaler,
          ),
          child: ActivityFeedbackOverlay(
            character: character,
            loadFeedback: loadFeedback ?? () async => _bundle,
            onClose: onClose ?? () {},
          ),
        ),
      ),
    ),
  );
}

String _assetName(WidgetTester tester, Key key) {
  final image = tester.widget<Image>(find.byKey(key));
  final provider = image.image;
  expect(provider, isA<AssetImage>());
  return (provider as AssetImage).assetName;
}

double _bubbleOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.byKey(const ValueKey('activity_feedback_bubble')),
      )
      .opacity;
}

Finder _feedbackBarrier() {
  return find.byKey(const ValueKey('activity_feedback_barrier'));
}

void main() {
  group('ActivityFeedbackOverlay motion', () {
    testWidgets(
      'uses onboarding assets and reveals a compact bubble after arrival',
      (tester) async {
        await _pumpOverlay(tester);
        await tester.pump();

        expect(
          _assetName(
            tester,
            const ValueKey('activity_feedback_running_character'),
          ),
          _runLeftAsset,
        );
        expect(_bubbleOpacity(tester), 0);
        expect(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey('activity_feedback_running_character'),
                ),
              )
              .dx,
          greaterThan(390),
        );
        expect(
          find.byKey(const ValueKey('activity_feedback_panel')),
          findsNothing,
        );

        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('activity_feedback_running_character')),
          findsOneWidget,
        );
        expect(_bubbleOpacity(tester), 0);

        await tester.pump(_runDuration - const Duration(milliseconds: 400));
        await tester.pump();

        expect(
          _assetName(
            tester,
            const ValueKey('activity_feedback_idle_character'),
          ),
          _idleAsset,
        );
        expect(
          find.byKey(const ValueKey('activity_feedback_running_character')),
          findsNothing,
        );
        expect(_bubbleOpacity(tester), 1);
        expect(find.text('Summary'), findsOneWidget);

        final characterRect = tester.getRect(
          find.byKey(const ValueKey('activity_feedback_character_footprint')),
        );
        final bubbleRect = tester.getRect(
          find.byKey(const ValueKey('activity_feedback_bubble')),
        );
        expect(bubbleRect.left, greaterThanOrEqualTo(characterRect.right));
        expect(characterRect.left, lessThan(32));

        final whiteSurfaceFinder = find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color == Colors.white,
        );
        final whiteSurfaces = tester.renderObjectList<RenderBox>(
          whiteSurfaceFinder,
        );
        expect(
          whiteSurfaces.every((surface) => surface.size.width <= 300),
          isTrue,
        );
      },
    );

    testWidgets('shows loading copy before fixed four-step feedback', (
      tester,
    ) async {
      final feedback = Completer<ActivityFeedbackBundle>();
      await _pumpOverlay(tester, loadFeedback: () => feedback.future);
      await tester.pump();
      await tester.pump(_runDuration);
      await tester.pump();

      expect(find.text('Analysing your run...'), findsOneWidget);
      expect(find.text('Summary'), findsNothing);

      feedback.complete(_bundle);
      await tester.pump();
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text(_bundle.sections.summary), findsOneWidget);

      await tester.tap(find.byTooltip('Next feedback step'));
      await tester.pump();
      expect(find.text('Went well'), findsOneWidget);
      expect(find.text(_bundle.sections.wentWell), findsOneWidget);

      await tester.tap(find.byTooltip('Next feedback step'));
      await tester.pump();
      expect(find.text('Improve'), findsOneWidget);
      expect(find.text(_bundle.sections.improve), findsOneWidget);

      await tester.tap(find.byTooltip('Next feedback step'));
      await tester.pump();
      expect(find.text('Next focus'), findsOneWidget);
      expect(find.text(_bundle.sections.nextFocus), findsOneWidget);

      await tester.tap(find.byTooltip('Previous feedback step'));
      await tester.pump();
      expect(find.text('Improve'), findsOneWidget);
    });

    // Regression for manual script 6.2.1 step 3: the sixth generation of the
    // day is refused with the same generic sections as any other fallback, so
    // without the notice the runner is told neither why the copy is generic
    // nor when they may generate again.
    testWidgets('a quota refusal states the reset day on the first page', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        loadFeedback: () async => fallbackActivityFeedbackBundle(
          source: ActivityFeedbackSource.quota,
          retryAfterDate: '2026-08-09',
        ),
      );
      await tester.pump(_runDuration);
      await tester.pump();

      expect(find.text('Summary'), findsOneWidget);
      expect(
        find.textContaining(
          'Daily limit reached — personalised feedback unlocks again on '
          '9 August 2026.',
        ),
        findsOneWidget,
      );
      // The notice leads page one rather than adding a page of its own.
      expect(find.text('1/4'), findsOneWidget);
    });

    testWidgets('a quota refusal without a date still says it resets', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        loadFeedback: () async => fallbackActivityFeedbackBundle(
          source: ActivityFeedbackSource.quota,
        ),
      );
      await tester.pump(_runDuration);
      await tester.pump();

      expect(
        find.textContaining('unlocks again tomorrow.'),
        findsOneWidget,
      );
    });

    // A provider outage is a different fact from a spent quota and must not
    // borrow its copy — script 6.2.4 covers that path and passed as-is.
    testWidgets('a plain fallback carries no quota notice', (tester) async {
      await _pumpOverlay(
        tester,
        loadFeedback: () async => fallbackActivityFeedbackBundle(),
      );
      await tester.pump(_runDuration);
      await tester.pump();

      expect(find.textContaining('Daily limit reached'), findsNothing);
    });

    testWidgets('keeps a non-dismissible barrier over the full surface', (
      tester,
    ) async {
      await _pumpOverlay(tester);
      await tester.pump();

      final barrier = tester.widgetList<ModalBarrier>(_feedbackBarrier()).first;
      expect(barrier.dismissible, isFalse);
      expect(barrier.color, isNotNull);
      expect(barrier.color!.a, greaterThan(0.4));
    });
  });

  group('ActivityFeedbackOverlay close and reduced motion', () {
    testWidgets('hides bubble, runs left, and closes only after exit', (
      tester,
    ) async {
      var closeCalls = 0;
      await _pumpOverlay(tester, onClose: () => closeCalls++);
      await tester.pump(_runDuration);
      await tester.pump();
      expect(_bubbleOpacity(tester), 1);

      await tester.tap(find.byTooltip('Close activity feedback'));
      await tester.tap(
        find.byTooltip('Close activity feedback'),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(_bubbleOpacity(tester), 0);
      expect(
        _assetName(
          tester,
          const ValueKey('activity_feedback_running_character'),
        ),
        _runLeftAsset,
      );
      expect(_feedbackBarrier(), findsOneWidget);
      expect(closeCalls, 0);

      await tester.pump(_runDuration - const Duration(milliseconds: 1));
      expect(closeCalls, 0);
      expect(_feedbackBarrier(), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(closeCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(closeCalls, 1);
    });

    testWidgets('reduced motion shows idle bubble and closes immediately', (
      tester,
    ) async {
      var closeCalls = 0;
      await _pumpOverlay(
        tester,
        disableAnimations: true,
        onClose: () => closeCalls++,
      );
      await tester.pump();

      expect(
        _assetName(tester, const ValueKey('activity_feedback_idle_character')),
        _reducedMotionAsset,
      );
      expect(
        find.byKey(const ValueKey('activity_feedback_running_character')),
        findsNothing,
      );
      expect(_bubbleOpacity(tester), 1);

      await tester.tap(find.byTooltip('Close activity feedback'));
      expect(closeCalls, 1);
      await tester.pump();
      expect(closeCalls, 1);
    });
  });

  testWidgets(
    'keeps long feedback and controls reachable at large text scale',
    (tester) async {
      const longCopy =
          'This is intentionally long feedback that should wrap across many '
          'lines without pushing the close control or the four-step navigation '
          'outside the compact speech bubble. Keep the guidance useful and '
          'specific while preserving a calm, beginner-friendly reading flow.';
      const longBundle = ActivityFeedbackBundle(
        source: ActivityFeedbackSource.generated,
        sections: ActivityFeedbackSections(
          summary: longCopy,
          wentWell: longCopy,
          improve: longCopy,
          nextFocus: longCopy,
        ),
      );

      await _pumpOverlay(
        tester,
        textScaler: TextScaler.linear(2.2),
        loadFeedback: () async => longBundle,
      );
      await tester.pump(_runDuration);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Close activity feedback'), findsOneWidget);
      expect(find.byTooltip('Next feedback step'), findsOneWidget);

      final closeRect = tester.getRect(
        find.byTooltip('Close activity feedback'),
      );
      final nextRect = tester.getRect(find.byTooltip('Next feedback step'));
      expect(closeRect.top, greaterThanOrEqualTo(0));
      expect(closeRect.bottom, lessThanOrEqualTo(844));
      expect(nextRect.top, greaterThanOrEqualTo(0));
      expect(nextRect.bottom, lessThanOrEqualTo(844));

      await tester.tap(find.byTooltip('Next feedback step'));
      await tester.pump();
      expect(find.text('Went well'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
