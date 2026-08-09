import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/leaderboard/presentation/widgets/leaderboard_refresh_countdown.dart';

void main() {
  const style = TextStyle(fontSize: 12);

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('live countdown ticks down every second from the period end', (
    tester,
  ) async {
    var now = DateTime(2026, 7, 15, 10, 0, 0);
    final end = DateTime(2026, 7, 15, 10, 0, 10);

    await tester.pumpWidget(
      host(
        LeaderboardRefreshCountdown(
          periodEndsAt: end,
          staticLabel: 'static',
          live: true,
          clock: () => now,
          style: style,
        ),
      ),
    );

    expect(find.text('Refreshes in 00:00:00:10'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Refreshes in 00:00:00:09'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Refreshes in 00:00:00:08'), findsOneWidget);
  });

  testWidgets('countdown clamps to zero and stops ticking at the period end', (
    tester,
  ) async {
    var now = DateTime(2026, 7, 15, 10, 0, 0);
    final end = DateTime(2026, 7, 15, 10, 0, 2);

    await tester.pumpWidget(
      host(
        LeaderboardRefreshCountdown(
          periodEndsAt: end,
          staticLabel: 'static',
          live: true,
          clock: () => now,
          style: style,
        ),
      ),
    );

    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Refreshes in 00:00:00:00'), findsOneWidget);

    // No further ticks are scheduled once the deadline has passed, so pumping
    // more time leaves the label unchanged and no timer is left pending.
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Refreshes in 00:00:00:00'), findsOneWidget);
  });

  testWidgets('non-live countdown renders the static label without ticking', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const LeaderboardRefreshCountdown(
          periodEndsAt: null,
          staticLabel: 'Refreshes soon',
          live: false,
          style: style,
        ),
      ),
    );

    expect(find.text('Refreshes soon'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Refreshes soon'), findsOneWidget);
  });
}
