import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:runiac_app/core/assets/runiac_assets.dart';
import 'package:runiac_app/features/home/presentation/plan_completion_ceremony.dart';

Widget _harness({required bool reduceMotion}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPlanCompletionCeremony(context),
                child: const Text('open'),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The ceremony's build-up, mirroring `_gaugeFillDuration` in the overlay.
///
/// One controller plays the gauge and fires the reveal, so this is both how
/// long the bar takes to fill and when the badge and headline arrive. The
/// gauge composition is authored at 3.43s and remapped onto this.
const _gaugeFull = Duration(milliseconds: 1800);

double _headlineOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.widgetWithText(AnimatedOpacity, 'Plan Completed!'),
      )
      .opacity;
}

void main() {
  testWidgets(
    'renders the barrier and close button, and reveals the message and '
    'second asset once the gauge finishes',
    (tester) async {
      await tester.pumpWidget(_harness(reduceMotion: false));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(_headlineOpacity(tester), 0);

      await tester.pump(_gaugeFull);
      expect(_headlineOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 260));
    },
  );

  testWidgets(
    'nothing reveals while the gauge is still filling',
    (tester) async {
      // The payoff has to land on a full gauge. A sequencing constant shorter
      // than the composition drops the badge and the headline over a
      // half-filled bar, which reads as a glitch — this pins the two together
      // so shortening one without re-measuring the other fails here.
      await tester.pumpWidget(_harness(reduceMotion: false));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      // Elapsed times below include the 220ms opening transition pumped above.
      //
      // ~0.9s in: roughly halfway through the fill.
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        _headlineOpacity(tester),
        0,
        reason: 'the gauge is only about half full here',
      );

      // ~1.6s in: still short of full.
      await tester.pump(const Duration(milliseconds: 700));
      expect(_headlineOpacity(tester), 0);

      // ~1.9s in: past the end of the build-up.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        _headlineOpacity(tester),
        1,
        reason: 'and it reveals as soon as the gauge is full',
      );
      await tester.pump(const Duration(milliseconds: 260));
    },
  );

  testWidgets(
    'the fireworks join the payoff, not the build-up',
    (tester) async {
      // Same asset the challenge badge ceremony uses, so the two celebrations
      // read as the same class of moment.
      await tester.pumpWidget(_harness(reduceMotion: false));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      final fireworks = find.byWidgetPredicate(
        (widget) =>
            widget is LottieBuilder &&
            widget.lottie is AssetLottie &&
            (widget.lottie as AssetLottie).assetName ==
                RuniacAssets.challengeCelebrationLottie,
      );
      expect(fireworks, findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(
          find.ancestor(of: fireworks, matching: find.byType(AnimatedOpacity)),
        ).opacity,
        0,
        reason: 'the gauge fill stays a quiet build-up',
      );

      await tester.pump(_gaugeFull);
      expect(
        tester.widget<AnimatedOpacity>(
          find.ancestor(of: fireworks, matching: find.byType(AnimatedOpacity)),
        ).opacity,
        1,
      );
      await tester.pump(const Duration(milliseconds: 260));
    },
  );

  testWidgets('reduced motion drops the fireworks entirely', (tester) async {
    await tester.pumpWidget(_harness(reduceMotion: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is LottieBuilder &&
            widget.lottie is AssetLottie &&
            (widget.lottie as AssetLottie).assetName ==
                RuniacAssets.challengeCelebrationLottie,
      ),
      findsNothing,
    );
  });

  testWidgets('tapping the close button dismisses the overlay', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(reduceMotion: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('reduced motion opens directly in the fully-revealed state', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(reduceMotion: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Plan Completed!'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.widgetWithText(AnimatedOpacity, 'Plan Completed!'),
          )
          .opacity,
      1,
    );
  });
}
