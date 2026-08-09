import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/observability/error_screen_tracker.dart';

void main() {
  testWidgets('records the active route name as screens are pushed', (
    tester,
  ) async {
    final tracker = ErrorScreenTracker();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        initialRoute: '/first',
        routes: {
          '/first': (_) => const Scaffold(body: Text('First')),
          '/second': (_) => const Scaffold(body: Text('Second')),
        },
      ),
    );

    expect(tracker.currentScreen, '/first');

    final navigatorState = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    navigatorState.pushNamed('/second');
    await tester.pumpAndSettle();

    expect(tracker.currentScreen, '/second');

    navigatorState.pop();
    await tester.pumpAndSettle();

    expect(tracker.currentScreen, '/first');
  });
}
