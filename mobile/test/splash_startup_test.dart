import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/splash/presentation/runiac_splash_tokens.dart';

void main() {
  testWidgets('RuniacApp shows the splash before the shell', (tester) async {
    await tester.pumpWidget(const RuniacApp());

    expect(find.byKey(const ValueKey('runiac_splash_screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('runiac_splash_logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('runiac_splash_dot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('runiac_splash_dot_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('runiac_splash_dot_2')), findsOneWidget);
    expect(find.text('RUN · TRACK · GROW'), findsOneWidget);
    expect(find.text('Good to see you'), findsNothing);
  });

  testWidgets('splash transitions to the Runiac shell after duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(splashDuration: Duration(milliseconds: 1)),
    );

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(
      RuniacSplashTokens.transitionDuration + const Duration(milliseconds: 1),
    );

    expect(find.byKey(const ValueKey('runiac_splash_screen')), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('RuniacApp can bypass the splash deterministically', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    expect(find.byKey(const ValueKey('runiac_splash_screen')), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('splash exposes one loading semantic label', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const RuniacApp(splashDuration: Duration(seconds: 10)),
    );

    final splashSemantics = tester.getSemantics(
      find.byKey(const ValueKey('runiac_splash_screen')),
    );

    expect(splashSemantics.label, 'Runiac is loading');
    expect(splashSemantics.flagsCollection.isLiveRegion, isTrue);

    semantics.dispose();
  });
}
