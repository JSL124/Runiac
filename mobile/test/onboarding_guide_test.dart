import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/onboarding/domain/guide/onboarding_guide_agent.dart';
import 'package:runiac_app/features/onboarding/domain/guide/rule_based_onboarding_guide_agent.dart';
import 'package:runiac_app/features/onboarding/presentation/onboarding_flow_screen.dart';
import 'package:runiac_app/features/onboarding/presentation/onboarding_guide_overlay.dart';

Future<void> _pumpFlow(
  WidgetTester tester, {
  Duration threshold = const Duration(seconds: 12),
}) async {
  final store = SelectedRunnerCharacterStore()..select(RunnerCharacter.pink);
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: SelectedRunnerCharacterScope(
        store: store,
        child: OnboardingFlowScreen(
          guideStallThreshold: threshold,
          onComplete: (_) async => true,
        ),
      ),
    ),
  );
}

/// Advances time past the stall threshold and lets the guide agent future
/// resolve and the entrance/typing animations complete.
Future<void> _stall(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 12));
  await tester.pump(); // resolve the guide agent future + setState
  await tester.pump(const Duration(seconds: 3)); // entrance + typing
}

void main() {
  group('RuleBasedOnboardingGuideAgent', () {
    test('returns tailored copy for every onboarding step id', () async {
      const agent = RuleBasedOnboardingGuideAgent();
      const stepIds = [
        'welcome',
        'goal',
        'consistency',
        'frequency',
        'capacity',
        'experience',
        'availability',
        'days',
        'time',
        'length',
        'place',
        'motivation',
        'health',
        'symptoms',
        'style',
        'preview',
      ];

      final messages = <String>{};
      for (final stepId in stepIds) {
        final message = await agent.guide(
          OnboardingGuideRequest(stepId: stepId),
        );
        expect(message.text.trim(), isNotEmpty, reason: 'empty for $stepId');
        messages.add(message.text);
      }

      // Every step has genuinely distinct hint copy.
      expect(messages.length, stepIds.length);
    });

    test('falls back gracefully for an unknown step', () async {
      const agent = RuleBasedOnboardingGuideAgent();
      final message = await agent.guide(
        const OnboardingGuideRequest(stepId: 'does-not-exist'),
      );
      expect(message.text.trim(), isNotEmpty);
    });
  });

  group('Onboarding guide overlay', () {
    testWidgets('appears after the stall threshold with step-specific copy', (
      tester,
    ) async {
      await _pumpFlow(tester);

      // Before the threshold, the guide is not shown.
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('running buddy'), findsNothing);

      await _stall(tester);

      // Welcome-step hint from RuleBasedOnboardingGuideAgent.
      expect(find.textContaining('running buddy'), findsOneWidget);
      // Spoken by the selected character (pink => Mila).
      expect(find.text('Mila'), findsOneWidget);
    });

    testWidgets('can be dismissed and does not reappear on the same step', (
      tester,
    ) async {
      await _pumpFlow(tester);
      await _stall(tester);
      expect(find.textContaining('running buddy'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      await tester.pump(
        onboardingGuideRunOutDuration + const Duration(milliseconds: 1),
      );
      expect(find.textContaining('running buddy'), findsNothing);

      // Idling again on the same step must not nag the user.
      await _stall(tester);
      expect(find.textContaining('running buddy'), findsNothing);
    });

    testWidgets('does not appear when the threshold is disabled', (
      tester,
    ) async {
      await _pumpFlow(tester, threshold: Duration.zero);
      await _stall(tester);
      expect(find.textContaining('running buddy'), findsNothing);
    });

    testWidgets('animated guide runs in before showing its idle help state', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OnboardingGuideOverlay(
              character: RunnerCharacter.pink,
              message: 'Pick the closest answer for now.',
              enterFromLeft: true,
              onDismiss: _noop,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('onboarding_guide_running_character')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('onboarding_guide_bubble')),
            )
            .opacity,
        0,
      );

      await tester.pump(onboardingGuideRunInDuration);
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(const ValueKey('onboarding_guide_idle_character')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('onboarding_guide_bubble')),
            )
            .opacity,
        1,
      );
    });

    testWidgets(
      'animated guide runs out to the right when more screen remains there',
      (tester) async {
        final originalSize = tester.view.physicalSize;
        final originalDevicePixelRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDevicePixelRatio;
        });
        var dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OnboardingGuideOverlay(
                character: RunnerCharacter.pink,
                message: 'Pick the closest answer for now.',
                enterFromLeft: true,
                onDismiss: () {
                  dismissed = true;
                },
              ),
            ),
          ),
        );
        await tester.pump(onboardingGuideRunInDuration);
        await tester.pump(const Duration(milliseconds: 250));

        final idleCenter = tester.getCenter(
          find.byKey(const ValueKey('onboarding_guide_idle_character')),
        );
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pump();

        expect(dismissed, isFalse);
        expect(
          find.byKey(const ValueKey('onboarding_guide_character_right')),
          findsOneWidget,
        );

        await tester.pump(onboardingGuideRunOutDuration * 0.5);
        final runningCenter = tester.getCenter(
          find.byKey(const ValueKey('onboarding_guide_running_character')),
        );
        expect(runningCenter.dx, greaterThan(idleCenter.dx));
        expect(dismissed, isFalse);

        await tester.pump(onboardingGuideRunOutDuration * 0.5);
        await tester.pump(const Duration(milliseconds: 1));
        expect(dismissed, isTrue);
      },
    );

    testWidgets(
      'animated guide runs out to the left when more screen remains there',
      (tester) async {
        final originalSize = tester.view.physicalSize;
        final originalDevicePixelRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDevicePixelRatio;
        });
        var dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OnboardingGuideOverlay(
                character: RunnerCharacter.pink,
                message: 'Pick the closest answer for now.',
                enterFromLeft: false,
                onDismiss: () {
                  dismissed = true;
                },
              ),
            ),
          ),
        );
        await tester.pump(onboardingGuideRunInDuration);
        await tester.pump(const Duration(milliseconds: 250));

        final idleCenter = tester.getCenter(
          find.byKey(const ValueKey('onboarding_guide_idle_character')),
        );
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pump();

        expect(dismissed, isFalse);
        expect(
          find.byKey(const ValueKey('onboarding_guide_character_left')),
          findsOneWidget,
        );

        await tester.pump(onboardingGuideRunOutDuration * 0.5);
        final runningCenter = tester.getCenter(
          find.byKey(const ValueKey('onboarding_guide_running_character')),
        );
        expect(runningCenter.dx, lessThan(idleCenter.dx));
        expect(dismissed, isFalse);

        await tester.pump(onboardingGuideRunOutDuration * 0.5);
        await tester.pump(const Duration(milliseconds: 1));
        expect(dismissed, isTrue);
      },
    );

    testWidgets('Blue runs in on its own run animation before idling', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OnboardingGuideOverlay(
              character: RunnerCharacter.blue,
              message: 'Pick the closest answer for now.',
              enterFromLeft: false,
              onDismiss: _noop,
            ),
          ),
        ),
      );
      await tester.pump(onboardingGuideRunInDuration * 0.5);

      expect(
        find.byKey(const ValueKey('onboarding_guide_running_character')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Image>(
              find.byKey(const ValueKey('onboarding_guide_running_character')),
            )
            .image,
        isA<AssetImage>().having(
          (image) => image.assetName,
          'assetName',
          'assets/images/characters/blue_runner_run_left.gif',
        ),
      );

      await tester.pump(onboardingGuideRunInDuration);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('onboarding_guide_running_character')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('onboarding_guide_idle_character')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('onboarding_guide_bubble')),
            )
            .opacity,
        1,
      );
    });
  });
}

void _noop() {}
