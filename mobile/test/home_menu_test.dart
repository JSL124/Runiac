import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/haptics/runiac_haptics.dart';
import 'package:runiac_app/core/haptics/runiac_haptics_scope.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map.dart';

/// Records every haptic method invoked so the menu's press moments can be
/// asserted without touching a real platform channel.
class _RecordingHaptics implements RuniacHaptics {
  final List<String> calls = <String>[];

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
  void setEnabled(bool value) {}
}

/// The row's own press-tint container, identified by being the nearest
/// [AnimatedContainer] wrapping the row's label.
Color? _rowColor(WidgetTester tester, String label) {
  final container = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}

Widget _harness({
  VoidCallback? onOpenFriends,
  VoidCallback? onOpenChallenge,
  VoidCallback? onNotifications,
  int streakCount = 0,
  int unreadNotificationCount = 0,
  bool progressLoading = false,
  bool disableAnimations = false,
  RuniacHaptics? haptics,
}) {
  final map = HomeStageMap(
    onNotifications: onNotifications ?? () {},
    onProfile: () {},
    onTapTodayStage: () {},
    onOpenFriends: onOpenFriends,
    onOpenChallenge: onOpenChallenge,
    streakCount: streakCount,
    unreadNotificationCount: unreadNotificationCount,
    progressLoading: progressLoading,
  );
  final app = MaterialApp(
    home: Scaffold(
      body: disableAnimations
          ? Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: map,
              ),
            )
          : map,
    ),
  );
  if (haptics == null) {
    return app;
  }
  return RuniacHapticsScope(haptics: haptics, child: app);
}

final Finder _trigger = find.byKey(const ValueKey('homeMenuTrigger'));
final Finder _panel = find.byKey(const ValueKey('homeMenuPanel'));
final Finder _barrier = find.byKey(const ValueKey('homeMenuBarrier'));
final Finder _streakRow = find.byKey(const ValueKey('homeMenuStreakRow'));

void main() {
  testWidgets('Menu trigger is visible and the panel starts hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(onOpenFriends: () {}));
    await tester.pumpAndSettle();

    expect(_trigger, findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    expect(_panel, findsNothing);
    expect(_barrier, findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('Challenge'), findsNothing);

    final triggerSize = tester.getSize(_trigger);
    expect(triggerSize.width, greaterThanOrEqualTo(76));
    expect(triggerSize.height, greaterThanOrEqualTo(34));
  });

  testWidgets('The header no longer carries a streak pill or a bell', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(streakCount: 4));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    expect(find.text('4'), findsNothing);
    expect(find.bySemanticsLabel('Notifications'), findsNothing);
  });

  testWidgets('Tapping the trigger opens every menu row', (tester) async {
    await tester.pumpWidget(_harness(onOpenFriends: () {}, streakCount: 12));
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    expect(_panel, findsOneWidget);
    expect(_barrier, findsOneWidget);
    expect(_streakRow, findsOneWidget);
    expect(find.text('12 day streak'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Challenge'), findsOneWidget);
  });

  testWidgets('Streak row is read-only and shows a loading placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(streakCount: 1, progressLoading: true));
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    expect(find.text('Day streak …'), findsOneWidget);
    expect(find.text('1 day streak'), findsNothing);

    // Tapping the streak row must not dismiss the menu: it is status, not a
    // destination.
    await tester.tap(_streakRow);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
  });

  testWidgets('Unread count renders as a badge over the Notifications icon', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(unreadNotificationCount: 3));
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Notifications, 3 unread'), findsOneWidget);
  });

  testWidgets('Unread badge caps at 99+', (tester) async {
    await tester.pumpWidget(_harness(unreadNotificationCount: 130));
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    expect(find.text('99+'), findsOneWidget);
    // Carried over from the deleted HomeHeader badge test: the count has to
    // stay legible against the red disc.
    expect(tester.widget<Text>(find.text('99+')).style?.color, Colors.white);
  });

  testWidgets('No unread badge is drawn at zero', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    expect(find.text('99+'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
  });

  testWidgets(
    'Notifications item fires the callback once and closes the menu',
    (tester) async {
      var openNotificationsCount = 0;
      await tester.pumpWidget(
        _harness(onNotifications: () => openNotificationsCount++),
      );
      await tester.pumpAndSettle();

      await tester.tap(_trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      expect(openNotificationsCount, 1);
      expect(_panel, findsNothing);
      expect(_barrier, findsNothing);
    },
  );

  testWidgets('Friends item fires the callback once and closes the menu', (
    tester,
  ) async {
    var openFriendsCount = 0;
    await tester.pumpWidget(_harness(onOpenFriends: () => openFriendsCount++));
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(openFriendsCount, 1);
    expect(_panel, findsNothing);
    expect(_barrier, findsNothing);
  });

  testWidgets('Challenge item fires the callback once and closes the menu', (
    tester,
  ) async {
    var openFriendsCount = 0;
    var openChallengeCount = 0;
    await tester.pumpWidget(
      _harness(
        onOpenFriends: () => openFriendsCount++,
        onOpenChallenge: () => openChallengeCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Challenge'));
    await tester.pumpAndSettle();

    expect(openChallengeCount, 1);
    expect(openFriendsCount, 0);
    // No coming-soon SnackBar is shown anymore.
    expect(find.text('Challenge is coming soon!'), findsNothing);
    expect(_panel, findsNothing);
    expect(_barrier, findsNothing);
  });

  testWidgets('Holding a row tints it and releasing outside clears the tint', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(onOpenFriends: () {}));
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    final resting = _rowColor(tester, 'Friends');

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Friends')),
    );
    await tester.pumpAndSettle();
    final pressed = _rowColor(tester, 'Friends');
    expect(pressed, isNot(resting));

    // Only the held row lights up — that is the whole point of the feedback.
    expect(_rowColor(tester, 'Challenge'), resting);

    // Dragging off the row and releasing cancels the tap and the tint.
    await gesture.moveBy(const Offset(0, 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_rowColor(tester, 'Friends'), resting);
    expect(_panel, findsOneWidget);
  });

  testWidgets('A tapped row stays lit while the menu closes', (tester) async {
    await tester.pumpWidget(_harness(onOpenFriends: () {}));
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    final resting = _rowColor(tester, 'Friends');
    await tester.tap(find.text('Friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Mid-close the row that fired is still highlighted, so the tap is
    // acknowledged instead of the panel simply vanishing.
    expect(_rowColor(tester, 'Friends'), isNot(resting));
    await tester.pumpAndSettle();
  });

  testWidgets('Menu presses fire the documented haptics', (tester) async {
    final haptics = _RecordingHaptics();
    await tester.pumpWidget(_harness(onOpenFriends: () {}, haptics: haptics));
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    expect(haptics.calls, ['selection']);

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(haptics.calls, ['selection', 'impactLight']);
  });

  testWidgets('The read-only streak row never tints on press', (tester) async {
    await tester.pumpWidget(_harness(streakCount: 5));
    await tester.pumpAndSettle();
    await tester.tap(_trigger);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(_streakRow));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _streakRow, matching: find.byType(AnimatedContainer)),
      findsNothing,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
  });

  testWidgets('Tapping outside the open menu dismisses it', (tester) async {
    await tester.pumpWidget(_harness(onOpenFriends: () {}));
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);

    await tester.tap(_barrier);
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(_barrier, findsNothing);
  });

  testWidgets('Omitted onOpenFriends does not throw when Friends is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_panel, findsNothing);
  });

  testWidgets('The panel and barrier outlive the close animation', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(onOpenFriends: () {}));
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    // Mid-open the panel is mounted but only partly revealed: still fading in
    // and still scaled down towards the caret.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_panel, findsOneWidget);
    final midOpacity = tester
        .widget<Opacity>(
          find.ancestor(of: _panel, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(midOpacity, greaterThan(0));
    expect(midOpacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: _panel, matching: find.byType(Opacity)).first,
          )
          .opacity,
      1,
    );

    await tester.tap(_barrier);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Still on screen, and the barrier still swallows map taps, while the
    // exit animation runs.
    expect(_panel, findsOneWidget);
    expect(_barrier, findsOneWidget);

    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(_barrier, findsNothing);
  });

  testWidgets('Reduced motion settles the menu without animating', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(onOpenFriends: () {}, disableAnimations: true),
    );
    await tester.pumpAndSettle();

    await tester.tap(_trigger);
    // A single frame is enough: no transition is scheduled.
    await tester.pump();
    expect(_panel, findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);

    await tester.tap(_barrier);
    await tester.pump();
    expect(_panel, findsNothing);
    expect(_barrier, findsNothing);
  });
}
