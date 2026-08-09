import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/presentation/qa/xp_update_qa_launcher.dart';

void main() {
  test('QA launcher is disabled for release mode', () {
    final app = buildXpUpdateQaApp(
      releaseMode: true,
      surface: xpUpdateQaSurfaceName,
      scenarioName: 'level_up',
    );

    expect(app, isNull);
  });

  test('QA launcher ignores non-XP surfaces', () {
    final app = buildXpUpdateQaApp(
      releaseMode: false,
      surface: 'home',
      scenarioName: 'level_up',
    );

    expect(app, isNull);
  });

  test('QA scenario resolver exposes level-up display data', () {
    final model = xpUpdateQaModelForScenario('level_up');

    expect(model.didLevelUp, isTrue);
    expect(model.level, 6);
    expect(model.previousLevel, 5);
    expect(model.earnedXpLabel, '+120 XP');
    expect(model.streakChangeLabel, '8 to 9 days');
  });

  testWidgets('QA launcher renders the requested XP update scenario', (
    tester,
  ) async {
    final app = buildXpUpdateQaApp(
      releaseMode: false,
      surface: xpUpdateQaSurfaceName,
      scenarioName: 'rest_day_streak_bridge',
    );

    expect(app, isA<MaterialApp>());
    await tester.pumpWidget(app!);
    await tester.pumpAndSettle();

    expect(find.text('Nice work, QA Runner!'), findsOneWidget);
    expect(find.text('+80 XP'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('2 days'), findsNothing);
    expect(find.textContaining('Rest day'), findsNothing);
    expect(find.textContaining('backend progression'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
