import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/tutorial/domain/models/tutorial_step.dart';
import 'package:runiac_app/features/tutorial/presentation/tutorial_anchor_registry.dart';

void main() {
  group('TutorialAnchorRegistry', () {
    testWidgets(
      'rectFor matches the wrapped widget\'s on-screen rect inside a scope',
      (tester) async {
        final registry = TutorialAnchorRegistry();
        const child = SizedBox(width: 40, height: 20, key: Key('anchored'));

        await tester.pumpWidget(
          MaterialApp(
            home: TutorialAnchorScope(
              registry: registry,
              child: Center(
                child: TutorialAnchor(
                  id: TutorialAnchorId.homeMenuTrigger,
                  child: child,
                ),
              ),
            ),
          ),
        );

        final resolved = registry.rectFor(TutorialAnchorId.homeMenuTrigger);
        final expected = tester.getRect(find.byWidget(child));
        expect(resolved, isNotNull);
        expect(resolved, expected);
      },
    );

    testWidgets(
      'rectFor is null for an id never wrapped, and null again once removed',
      (tester) async {
        final registry = TutorialAnchorRegistry();

        expect(registry.rectFor(TutorialAnchorId.feedPostList), isNull);

        var mounted = true;
        late StateSetter setState;
        await tester.pumpWidget(
          MaterialApp(
            home: TutorialAnchorScope(
              registry: registry,
              child: StatefulBuilder(
                builder: (context, setter) {
                  setState = setter;
                  return mounted
                      ? const TutorialAnchor(
                          id: TutorialAnchorId.feedPostList,
                          child: SizedBox(width: 10, height: 10),
                        )
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(registry.rectFor(TutorialAnchorId.feedPostList), isNotNull);

        setState(() {
          mounted = false;
        });
        await tester.pump();

        expect(registry.rectFor(TutorialAnchorId.feedPostList), isNull);
      },
    );

    testWidgets(
      'with no scope in the tree, the child renders unchanged with no key attached',
      (tester) async {
        const child = SizedBox(width: 10, height: 10, key: Key('plain-child'));

        await tester.pumpWidget(
          const MaterialApp(
            home: TutorialAnchor(
              id: TutorialAnchorId.youSegmentedControl,
              child: child,
            ),
          ),
        );

        // The pass-through must not introduce a KeyedSubtree carrying the
        // anchor's GlobalKey: no KeyedSubtree should exist above the child at
        // all when there is no TutorialAnchorScope.
        expect(find.byType(KeyedSubtree), findsNothing);
        expect(find.byWidget(child), findsOneWidget);
      },
    );

    test('keyFor is stable per id and distinct across ids', () {
      final registry = TutorialAnchorRegistry();

      final first = registry.keyFor(TutorialAnchorId.homeTodayStone);
      final second = registry.keyFor(TutorialAnchorId.homeTodayStone);
      final other = registry.keyFor(TutorialAnchorId.homeLevelAvatar);

      expect(identical(first, second), isTrue);
      expect(identical(first, other), isFalse);
    });
  });

  group('bottomNavItemRect', () {
    test('returns the middle fifth slice of the bar', () {
      const bar = Rect.fromLTWH(0, 700, 400, 56);
      final rect = bottomNavItemRect(bar, 2);

      expect(rect.left, 160);
      expect(rect.width, 80);
    });
  });
}
