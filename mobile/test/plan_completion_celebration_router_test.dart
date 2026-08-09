/// Unit cover for the seam that carries a pending plan-completion celebration
/// out of the run flow and back to the Home dashboard.
///
/// The router is deliberately dumb — it answers "is a celebration waiting?" and
/// forwards a "show the Home dashboard" request to whichever shell is mounted.
/// Everything that could strand the ceremony lives in the edges tested here:
/// a request with no shell attached, a stale shell detaching after a newer one
/// attached, and a scope that is simply absent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/plan/presentation/plan_completion_celebration_scope.dart';

void main() {
  group('PlanCompletionCelebrationRouter', () {
    test('delegates the pending check to its owner every time it is asked', () async {
      var calls = 0;
      var answer = false;
      final router = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async {
          calls += 1;
          return answer;
        },
      );

      expect(await router.isCelebrationPending(), isFalse);
      answer = true;
      expect(await router.isCelebrationPending(), isTrue);
      expect(
        calls,
        2,
        reason: 'the answer must never be cached — it changes mid-session',
      );
    });

    test('showHomeDashboard is a no-op when no shell is attached', () {
      final router = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async => true,
      );

      expect(router.showHomeDashboard, returnsNormally);
    });

    test('showHomeDashboard reaches the attached shell', () {
      var shown = 0;
      final router = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async => true,
      )..attachHomeDashboard(() => shown += 1);

      router.showHomeDashboard();
      router.showHomeDashboard();

      expect(shown, 2, reason: 'the request is not one-shot; the marker is');
    });

    test('detaching the attached handler stops further requests', () {
      var shown = 0;
      void handler() => shown += 1;
      final router = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async => true,
      )..attachHomeDashboard(handler);

      router.detachHomeDashboard(handler);
      router.showHomeDashboard();

      expect(shown, isZero);
    });

    test(
      'a stale detach cannot unhook the shell that replaced it',
      () {
        // Flutter mounts the replacement before disposing the old subtree, so
        // the outgoing shell's dispose() runs *after* the incoming one has
        // already attached. Keying the detach on the handler is what stops
        // that ordering from silently disabling the redirect.
        var oldShown = 0;
        var newShown = 0;
        void oldHandler() => oldShown += 1;
        void newHandler() => newShown += 1;

        final router = PlanCompletionCelebrationRouter(
          isCelebrationPending: () async => true,
        )..attachHomeDashboard(oldHandler);
        router.attachHomeDashboard(newHandler);
        router.detachHomeDashboard(oldHandler);

        router.showHomeDashboard();

        expect(newShown, 1);
        expect(oldShown, isZero);
      },
    );
  });

  group('PlanCompletionCelebrationScope', () {
    testWidgets('maybeOf returns null when no scope is above the widget', (
      tester,
    ) async {
      PlanCompletionCelebrationRouter? seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = PlanCompletionCelebrationScope.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(seen, isNull);
    });

    testWidgets('maybeOf exposes the router to routes pushed under it', (
      tester,
    ) async {
      final router = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async => true,
      );
      PlanCompletionCelebrationRouter? seenOnPushedRoute;

      await tester.pumpWidget(
        PlanCompletionCelebrationScope(
          router: router,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) {
                      seenOnPushedRoute =
                          PlanCompletionCelebrationScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                child: const Text('push'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      expect(
        seenOnPushedRoute,
        same(router),
        reason:
            'the run flow pushes onto the app navigator, so the scope has to '
            'sit above it rather than inside the shell',
      );
    });

    test('updateShouldNotify tracks the router identity', () {
      final a = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async => true,
      );
      final b = PlanCompletionCelebrationRouter(
        isCelebrationPending: () async => true,
      );
      const child = SizedBox.shrink();

      expect(
        PlanCompletionCelebrationScope(
          router: a,
          child: child,
        ).updateShouldNotify(
          PlanCompletionCelebrationScope(router: a, child: child),
        ),
        isFalse,
      );
      expect(
        PlanCompletionCelebrationScope(
          router: b,
          child: child,
        ).updateShouldNotify(
          PlanCompletionCelebrationScope(router: a, child: child),
        ),
        isTrue,
      );
    });
  });
}
