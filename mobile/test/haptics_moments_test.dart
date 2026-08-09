// Focused coverage for curated haptic moments: run lifecycle, XP/level-up
// reveal, plan completion, challenge-earned ceremony, the save-success
// overlay, and feed like/comment engagement. Each moment is asserted through
// a recording fake injected via `RuniacHapticsScope`, never against the real
// platform channel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/core/haptics/runiac_haptics.dart';
import 'package:runiac_app/core/haptics/runiac_haptics_scope.dart';
import 'package:runiac_app/core/widgets/runiac_success_check_overlay.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_result_ceremony.dart';
import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';
import 'package:runiac_app/features/home/presentation/plan_completion_ceremony.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/presentation/run_launch_screen.dart';
import 'package:runiac_app/features/run/presentation/xp_update_screen.dart';

/// Records every haptic method invoked, in call order, so tests can assert
/// on which curated moments fired without depending on a real platform
/// channel.
class RecordingRuniacHaptics implements RuniacHaptics {
  final List<String> calls = <String>[];
  bool enabled = true;

  @override
  void selection() => calls.add('selection');

  @override
  void impactLight() => calls.add('impactLight');

  @override
  void impactMedium() => calls.add('impactMedium');

  @override
  void impactHeavy() => calls.add('impactHeavy');

  @override
  void error() => calls.add('error');

  @override
  void setEnabled(bool value) => enabled = value;
}

Widget _wrap(RecordingRuniacHaptics recorder, Widget child) {
  return RuniacHapticsScope(
    haptics: recorder,
    child: MaterialApp(home: child),
  );
}

void main() {
  group('save-success overlay', () {
    testWidgets('fires impactMedium when shown', (tester) async {
      final recorder = RecordingRuniacHaptics();
      await tester.pumpWidget(
        _wrap(
          recorder,
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showRuniacSuccessCheckOverlay(context),
                child: const Text('save'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('save'));
      await tester.pump();

      expect(recorder.calls, contains('impactMedium'));
    });

    testWidgets('still fires impactMedium under reduced motion', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      await tester.pumpWidget(
        RuniacHapticsScope(
          haptics: recorder,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: Scaffold(
                    body: Builder(
                      builder: (innerContext) => ElevatedButton(
                        onPressed: () =>
                            showRuniacSuccessCheckOverlay(innerContext),
                        child: const Text('save'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('save'));
      await tester.pump();

      expect(recorder.calls, contains('impactMedium'));
    });
  });

  group('XP update reveal', () {
    const baseModel = XpUpdateDisplayModel(
      runnerName: 'Ada',
      earnedXpLabel: '+75 XP',
      totalXpLabel: '1,240 XP',
      levelLabel: '4',
      nextLevelLabel: '5',
      progressTargetLabel: 'Progress to Level 5',
      xpRemainingLabel: '260 XP to Level 5',
      previousProgressFraction: 0.30,
      currentProgressFraction: 0.62,
      streakChangeLabel: '3 → 4 days',
      streakNote: 'Keep it going',
      didLevelUp: false,
      xpAwardState: XpAwardState.awarded,
      heroMessage: 'Earned from this run',
      earnedXp: 75,
      totalXp: 1240,
      previousTotalXp: 1165,
      level: 4,
      previousLevel: 4,
      streakCount: 4,
      previousStreakCount: 3,
    );

    testWidgets('non level-up reveal fires impactMedium only', (tester) async {
      final recorder = RecordingRuniacHaptics();
      await tester.pumpWidget(
        _wrap(
          recorder,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const XpUpdateScreen(model: baseModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, contains('impactMedium'));
      expect(recorder.calls, isNot(contains('impactHeavy')));
    });

    testWidgets('level-up reveal fires impactHeavy, not impactMedium', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      final levelUpModel = XpUpdateDisplayModel(
        runnerName: baseModel.runnerName,
        earnedXpLabel: baseModel.earnedXpLabel,
        totalXpLabel: baseModel.totalXpLabel,
        levelLabel: baseModel.levelLabel,
        nextLevelLabel: baseModel.nextLevelLabel,
        progressTargetLabel: baseModel.progressTargetLabel,
        xpRemainingLabel: baseModel.xpRemainingLabel,
        previousProgressFraction: baseModel.previousProgressFraction,
        currentProgressFraction: baseModel.currentProgressFraction,
        streakChangeLabel: baseModel.streakChangeLabel,
        streakNote: baseModel.streakNote,
        didLevelUp: true,
        xpAwardState: baseModel.xpAwardState,
        heroMessage: 'You reached Level 5. Keep it up.',
        earnedXp: baseModel.earnedXp,
        totalXp: baseModel.totalXp,
        previousTotalXp: baseModel.previousTotalXp,
        level: baseModel.level,
        previousLevel: baseModel.previousLevel,
        streakCount: baseModel.streakCount,
        previousStreakCount: baseModel.previousStreakCount,
      );

      await tester.pumpWidget(
        _wrap(
          recorder,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: XpUpdateScreen(model: levelUpModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, contains('impactHeavy'));
      expect(recorder.calls, isNot(contains('impactMedium')));
    });
  });

  group('plan completion ceremony', () {
    testWidgets('fires impactHeavy once on reveal', (tester) async {
      final recorder = RecordingRuniacHaptics();
      await tester.pumpWidget(
        _wrap(
          recorder,
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showPlanCompletionCeremony(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(
        recorder.calls.where((call) => call == 'impactHeavy'),
        hasLength(1),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 260));

      // Still exactly one, even after the gauge-fill reveal completes.
      expect(
        recorder.calls.where((call) => call == 'impactHeavy'),
        hasLength(1),
      );
    });
  });

  group('challenge earned ceremony', () {
    testWidgets('fires impactHeavy on reveal', (tester) async {
      final recorder = RecordingRuniacHaptics();
      await tester.pumpWidget(
        _wrap(
          recorder,
          const ChallengeBadgeCeremony(tierId: ChallengeTierId.k10),
        ),
      );

      // The ceremony runs a continuous ambient/fireworks loop that never
      // settles, so drive a bounded number of frames instead of
      // `pumpAndSettle`.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(recorder.calls, contains('impactHeavy'));
    });
  });

  // These drive `RunLaunchScreen` — the screen the shell actually routes to
  // (`runiac_shell.dart`). An earlier version of this group drove
  // `RunActiveScreen`, which no production code references, so it stayed
  // green while the shipped run flow fired no haptics at all.
  group('run lifecycle', () {
    setUp(() {
      // `_startRun` awaits the SharedPreferences-backed voice settings
      // repository; without mock values getInstance() never resolves here.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('start fires impactMedium and pause/resume fire impactLight', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final recorder = RecordingRuniacHaptics();
      await tester.pumpWidget(
        _wrap(recorder, const RunLaunchScreen(enableForegroundGps: false)),
      );
      await tester.pumpAndSettle();

      expect(
        recorder.calls,
        isEmpty,
        reason: 'no haptic before the run actually starts',
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(recorder.calls, contains('impactMedium'));
      final afterStart = recorder.calls.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pumpAndSettle();

      expect(recorder.calls.skip(afterStart), contains('impactLight'));
      final afterPause = recorder.calls.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();

      expect(recorder.calls.skip(afterPause), contains('impactLight'));
    });
  });

  // Feed engagement runs on the static demo timeline: `feed-current-001`
  // starts unliked and `feed-friend-001` starts liked, so both directions of
  // the like toggle are reachable without a backend.
  group('feed engagement', () {
    Future<void> pumpFeed(
      WidgetTester tester,
      RecordingRuniacHaptics recorder,
    ) async {
      // Tall enough that the first two posts are both on screen and tappable.
      tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(recorder, const Scaffold(body: CurrentSessionFeed())),
      );
      await tester.pumpAndSettle();
      expect(recorder.calls, isEmpty, reason: 'no haptic before any tap');
    }

    testWidgets('liking fires impactLight and unliking fires selection', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      await pumpFeed(tester, recorder);

      await tester.tap(
        find.byKey(const ValueKey('feed-like-action-feed-current-001')),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, <String>['impactLight']);

      await tester.tap(
        find.byKey(const ValueKey('feed-like-action-feed-friend-001')),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, <String>['impactLight', 'selection']);
    });

    testWidgets('opening comments fires selection and posting one fires '
        'impactLight', (tester) async {
      final recorder = RecordingRuniacHaptics();
      await pumpFeed(tester, recorder);

      await tester.tap(
        find.byKey(const ValueKey('feed-comment-action-feed-current-001')),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, <String>['selection']);

      await tester.enterText(
        find.byKey(const ValueKey('feed-comment-input-feed-current-001')),
        'Nice pace!',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-submit-feed-current-001')),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, <String>['selection', 'impactLight']);
    });

    testWidgets('a rejected comment fires error instead of impactLight', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      await pumpFeed(tester, recorder);

      await tester.tap(
        find.byKey(const ValueKey('feed-comment-action-feed-current-001')),
      );
      await tester.pumpAndSettle();

      // Whitespace-only passes the composer's non-empty enablement check but
      // fails the trimmed 1-500 character rule.
      await tester.enterText(
        find.byKey(const ValueKey('feed-comment-input-feed-current-001')),
        '   ',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-submit-feed-current-001')),
      );
      await tester.pumpAndSettle();

      expect(recorder.calls, <String>['selection', 'error']);
    });
  });
}
