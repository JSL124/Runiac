/// Regression cover for the hosted `mobile-integration-tests` failure:
///
///   A RenderFlex overflowed by 12 pixels on the bottom   (×2)
///   A RenderFlex overflowed by 33 pixels on the bottom   (×2)
///   character_selection_screen.dart
///
/// The screen puts four character cards in the single flexible slot between a
/// fixed heading and a fixed confirm button, so the cards absorb every bit of
/// missing height. On a short viewport each cell fell under the ~31dp its name
/// needs (~52dp for the premium-locked pair, which also render a "Premium"
/// label) and overflowed — a hard failure in debug builds, which is what took
/// the integration job down.
///
/// It only reproduced between roughly 508dp and 548dp of usable height, and
/// CI's Android emulator sat right on that boundary: the same commit passed or
/// failed depending on whether the system-bar insets had been applied by the
/// frame the test pumped. These cases pin both edges of that window plus the
/// ordinary phone geometry, so the fix cannot regress in either direction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/presentation/character_selection_screen.dart';

/// Android status bar + navigation bar, split the way the system reports them.
const _systemBars = EdgeInsets.only(top: 24, bottom: 48);

Future<Object?> _pumpAt(
  WidgetTester tester, {
  required double height,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = Size(360 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(360, height), padding: padding),
      child: MaterialApp(home: CharacterSelectionScreen(onConfirm: (_) {})),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  return tester.takeException();
}

void main() {
  group('CharacterSelectionScreen lays out without overflowing', () {
    testWidgets('on an ordinary phone', (tester) async {
      expect(await _pumpAt(tester, height: 800), isNull);
    });

    testWidgets('at the top of the window that used to fail', (tester) async {
      expect(
        await _pumpAt(tester, height: 620, padding: _systemBars),
        isNull,
        reason: '548dp of usable height threw 4 overflow exceptions',
      );
    });

    testWidgets('at the bottom of the window that used to fail', (
      tester,
    ) async {
      expect(await _pumpAt(tester, height: 580, padding: _systemBars), isNull);
    });

    testWidgets('on a viewport far shorter than any real phone', (
      tester,
    ) async {
      expect(await _pumpAt(tester, height: 426), isNull);
    });

    testWidgets('every character stays reachable once the area scrolls', (
      tester,
    ) async {
      // Scrolling is the fallback, so it has to actually deliver what the
      // no-scroll layout promised: all four buddies, none stranded.
      await _pumpAt(tester, height: 580, padding: _systemBars);

      for (final name in const ['Bolt', 'Cap', 'Mila', 'Ivy']) {
        expect(
          find.text(name),
          findsOneWidget,
          reason: '$name must still be reachable on a short viewport',
        );
      }
    });
  });
}
