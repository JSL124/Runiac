/// Cover for the XP-update screen's "Home" CTA and its plan-completion
/// redirect, in isolation from the shell.
///
/// The CTA has one non-negotiable job — get the runner out of the run flow —
/// and one conditional extra: when the backend recorded that this run finished
/// the active plan and the ceremony has not been spent yet, select the Home
/// dashboard on the way out, because `HomeTab` only releases the held
/// celebration once Home is frontmost.
///
/// These tests pin the ordering (dashboard first, then pop) and every
/// degradation path, since a redirect that swallows the pop would trap the
/// runner on a screen whose only other exit is the back arrow.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/plan/presentation/plan_completion_celebration_scope.dart';
import 'package:runiac_app/features/run/presentation/xp_update_screen.dart';

void main() {
  group('XpUpdateScreen "Home" CTA', () {
    testWidgets('pops to the root when no celebration is pending, and does '
        'not touch the selected tab', (tester) async {
      final harness = await _pumpXpUpdate(tester, pending: false);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(XpUpdateScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
      expect(
        harness.homeDashboardRequests,
        isZero,
        reason: 'an ordinary run must leave the runner on the tab they left',
      );
    });

    testWidgets('selects the Home dashboard before popping when a celebration '
        'is pending', (tester) async {
      final harness = await _pumpXpUpdate(tester, pending: true);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(XpUpdateScreen), findsNothing);
      expect(harness.homeDashboardRequests, 1);
      expect(
        harness.log,
        <String>['show-home-dashboard', 'pop'],
        reason:
            'switching tabs after the pop would show the old tab for a frame '
            'and delay the ceremony by one navigation',
      );
    });

    testWidgets('pops every run-flow route, not just the topmost one', (
      tester,
    ) async {
      // The real stack is Home -> cool-down -> summary -> XP update.
      final harness = await _pumpXpUpdate(
        tester,
        pending: true,
        underlyingRunFlowRoutes: 2,
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('root'), findsOneWidget);
      expect(find.text('run-flow-0'), findsNothing);
      expect(find.text('run-flow-1'), findsNothing);
      expect(harness.homeDashboardRequests, 1);
    });

    testWidgets('still pops when no celebration scope is present at all', (
      tester,
    ) async {
      // This is the QA surface (`RUNIAC_QA_SURFACE=xp_update`) and any test
      // that pumps the screen bare.
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const XpUpdateScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(XpUpdateScreen), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(XpUpdateScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('still pops when the pending check throws', (tester) async {
      // A failed `shared_preferences` read must cost the celebration, never
      // the way out of the screen.
      final harness = await _pumpXpUpdate(tester, pendingError: true);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(XpUpdateScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
      expect(harness.homeDashboardRequests, isZero);
      expect(tester.takeException(), isNull);
    });

    testWidgets('still pops when the pending check never resolves before the '
        'runner leaves by the back arrow', (tester) async {
      final gate = Completer<bool>();
      final harness = await _pumpXpUpdate(tester, pendingFuture: gate.future);

      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(
        find.byType(XpUpdateScreen),
        findsOneWidget,
        reason: 'the pop waits on the marker read',
      );

      // The runner gives up and uses the header back arrow instead.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(XpUpdateScreen), findsNothing);

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        harness.homeDashboardRequests,
        isZero,
        reason: 'the screen was gone before the answer arrived',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second tap cannot request the dashboard twice', (
      tester,
    ) async {
      final gate = Completer<bool>();
      final harness = await _pumpXpUpdate(tester, pendingFuture: gate.future);

      await tester.tap(find.text('Home'));
      await tester.tap(find.text('Home'));
      await tester.pump();
      gate.complete(true);
      await tester.pumpAndSettle();

      expect(find.byType(XpUpdateScreen), findsNothing);
      expect(
        harness.homeDashboardRequests,
        1,
        reason: 'a double tap must not queue two tab switches',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _Harness {
  _Harness(this.log);

  final List<String> log;

  int get homeDashboardRequests =>
      log.where((entry) => entry == 'show-home-dashboard').length;
}

Future<_Harness> _pumpXpUpdate(
  WidgetTester tester, {
  bool pending = false,
  bool pendingError = false,
  Future<bool>? pendingFuture,
  int underlyingRunFlowRoutes = 0,
}) async {
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final log = <String>[];
  final router = PlanCompletionCelebrationRouter(
    isCelebrationPending: () {
      if (pendingError) {
        return Future<bool>.error(StateError('marker read failed'));
      }
      return pendingFuture ?? Future<bool>.value(pending);
    },
  )..attachHomeDashboard(() => log.add('show-home-dashboard'));

  await tester.pumpWidget(
    PlanCompletionCelebrationScope(
      router: router,
      child: MaterialApp(
        navigatorObservers: [_PopLog(log)],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  for (var i = 0; i < underlyingRunFlowRoutes; i++) {
                    unawaited(
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              Scaffold(body: Text('run-flow-$i')),
                        ),
                      ),
                    );
                  }
                  unawaited(
                    navigator.push(
                      MaterialPageRoute<void>(
                        builder: (context) => const XpUpdateScreen(),
                      ),
                    ),
                  );
                },
                child: const Text('root'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('root'));
  await tester.pumpAndSettle();
  expect(find.byType(XpUpdateScreen), findsOneWidget);

  return _Harness(log);
}

/// Records pops so the dashboard request can be ordered against them.
class _PopLog extends NavigatorObserver {
  _PopLog(this.log);

  final List<String> log;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    log.add('pop');
    super.didPop(route, previousRoute);
  }
}
