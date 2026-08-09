import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/presentation/xp_update_screen.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    XpUpdateDisplayModel model,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            // Force reduced motion so the staged controller jumps straight to
            // its final frame: final numbers/fractions, and no confetti.
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: XpUpdateScreen(model: model),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('awarded model settles on final XP, total, and streak values', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const XpUpdateDisplayModel(
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
      ),
    );

    expect(find.text('Nice work, Ada!'), findsOneWidget);
    expect(find.text('+75 XP'), findsOneWidget);
    expect(find.text('1,240 XP'), findsOneWidget);
    // The stamped-in new streak fully replaces the old value.
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('3 days'), findsNothing);
    expect(find.text('Lv.4'), findsOneWidget);
    expect(find.text('Level up!'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('level-up model shows the new level and level-up chip', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const XpUpdateDisplayModel(
        runnerName: 'Ben',
        earnedXpLabel: '+60 XP',
        totalXpLabel: '120 XP',
        levelLabel: '2',
        nextLevelLabel: '3',
        progressTargetLabel: 'Progress to Level 3',
        xpRemainingLabel: '180 XP to Level 3',
        previousProgressFraction: 0.60,
        currentProgressFraction: 0.20,
        streakChangeLabel: '1 → 2 days',
        streakNote: 'Keep it going',
        didLevelUp: true,
        xpAwardState: XpAwardState.awarded,
        heroMessage: 'You reached Level 2. Keep it up.',
        earnedXp: 60,
        totalXp: 120,
        previousTotalXp: 60,
        level: 2,
        previousLevel: 1,
        streakCount: 2,
        previousStreakCount: 1,
      ),
    );

    expect(find.text('Level 2, Ben!'), findsOneWidget);
    expect(find.text('Level up!'), findsOneWidget);
    // Final frame swaps the badge to the newly reached level.
    expect(find.text('Lv.2'), findsOneWidget);
    expect(find.text('Just leveled up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not-awarded model hides note copy and no celebration', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const XpUpdateDisplayModel(
        runnerName: 'Cлеo',
        earnedXpLabel: '+0 XP',
        totalXpLabel: '200 XP',
        levelLabel: '3',
        nextLevelLabel: '4',
        progressTargetLabel: 'Progress to Level 4',
        xpRemainingLabel: '100 XP to Level 4',
        previousProgressFraction: 0.40,
        currentProgressFraction: 0.40,
        streakChangeLabel: '5 days',
        streakNote: 'Nice work',
        didLevelUp: false,
        xpAwardState: XpAwardState.notAwarded,
        heroMessage: 'Daily XP cap reached — great effort today',
        earnedXp: 0,
        totalXp: 200,
        previousTotalXp: 200,
        level: 3,
        previousLevel: 3,
        streakCount: 5,
        previousStreakCount: 5,
      ),
    );

    expect(
      find.text('Daily XP cap reached — great effort today'),
      findsNothing,
    );
    expect(find.text('+0 XP'), findsNothing);
    expect(find.text('200 XP'), findsOneWidget);
    expect(find.text('5 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local sync pending state does not claim backend deferral', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const XpUpdateDisplayModel(
        runnerName: 'Ada',
        earnedXpLabel: '+0 XP',
        totalXpLabel: 'Saved on this device',
        levelLabel: '--',
        nextLevelLabel: '--',
        progressTargetLabel: 'Sync pending',
        xpRemainingLabel: 'XP updates after sync',
        previousProgressFraction: 0,
        currentProgressFraction: 0,
        streakChangeLabel: 'Not updated yet',
        streakNote: 'We’ll retry when the service is available.',
        didLevelUp: false,
        xpAwardState: XpAwardState.syncPending,
        heroMessage: 'This run is saved locally. XP updates after sync.',
      ),
    );

    expect(find.text('Run saved locally, Ada!'), findsOneWidget);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('Sync pending'), findsOneWidget);
    expect(find.text('Deferred by backend'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
