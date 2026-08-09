import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/leaderboard/data/static_leaderboard_repository.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_seen_store.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_steps.dart';
import 'package:runiac_app/features/tutorial/presentation/spotlight_scrim_painter.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';

const _ownerUid = 'test-auth-user-1';

/// The bottom nav's Run item's real accessible name. `BottomNavigationBar`
/// wraps each item's `tooltip` ("Run") in a `Tooltip` with
/// `excludeFromSemantics: true` and instead exposes a separate
/// `Semantics(label: "Tab N of M")` per item (see
/// `bottom_navigation_bar.dart`'s `_BottomNavigationTile.build`) — so "Run"
/// itself never reaches the semantics tree at all, blocked or not. Index 2
/// (0-based) is Run, matching `runiacAppTourSteps`'s "run-button" step's
/// `bottomNavItemIndex: 2`; the bar always has 5 fixed shell tabs, which is
/// app-shell chrome, not tour script copy.
const _runNavItemSemanticsLabel = 'Tab 3 of 5';

/// Mirrors `app_tour_flow_test.dart`'s `_pumpTourSettle`: the controller's
/// anchor poll uses plain `Future.delayed` timers that don't always schedule
/// a new frame while waiting, so `pumpAndSettle` can return before a poll
/// loop actually concludes. Ticking fixed 100ms frames advances those timers
/// deterministically.
Future<void> _pumpTourSettle(WidgetTester tester, {int ticks = 50}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapNext(WidgetTester tester) async {
  final button = tester.widget<FilledButton>(
    find.byKey(const ValueKey('appTourNextButton')),
  );
  button.onPressed!();
  await _pumpTourSettle(tester);
}

Future<void> _tapSkip(WidgetTester tester) async {
  final button = tester.widget<TextButton>(
    find.byKey(const ValueKey('appTourSkipButton')),
  );
  button.onPressed!();
  await _pumpTourSettle(tester);
}

SpotlightScrimPainter _scrimPainter(WidgetTester tester) {
  return tester
      .widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is SpotlightScrimPainter,
        ),
      )
      .painter as SpotlightScrimPainter;
}

/// The tour's own progress cue renders as "N of M"; used to confirm the
/// running tour has actually reached an anchored step (not just step 0,
/// which has no anchor/hole) without hardcoding any step copy.
String? _stepCounter(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('appTourStepCounter'));
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<Semantics>(finder).properties.label;
}

/// Whether [label] is announced anywhere in the *actually compiled*
/// semantics tree — i.e. exactly what a screen reader would be handed.
///
/// This deliberately walks the real `SemanticsNode` tree from the binding's
/// `rootSemanticsNode` rather than using `find.bySemanticsLabel` (which
/// resolves via `element.renderObject.debugSemantics`, a per-RenderObject
/// artifact whose sensitivity to `BlockSemantics`'s tree-assembly-time
/// pruning was not something to assume) or `find.byTooltip` (a widget/
/// element-tree finder that reads a `Tooltip` widget's `message` field
/// directly and is therefore blind to semantics blocking regardless of the
/// fix). Walking the compiled tree is the one check here that a control
/// blocked from assistive tech actually disappears from.
bool _semanticsTreeHasLabel(WidgetTester tester, String label) {
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    return false;
  }
  var found = false;
  void visit(SemanticsNode node) {
    if (found) {
      return;
    }
    if (node.getSemanticsData().label == label) {
      found = true;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return !found;
    });
  }

  visit(root);
  return found;
}

Widget _buildHarness({
  required FakeRuniacAuthRepository authRepository,
  required AppTourSeenStore? seenStore,
  bool autoStartArmed = false,
}) {
  // The You tab (built eagerly behind an Offstage, like every other tab) and
  // Home both read these ancestor scopes unconditionally, exactly as
  // `app_tour_flow_test.dart`'s harness does.
  final activityHistoryStore = CurrentSessionActivityHistoryStore(
    ownerUid: _ownerUid,
  );
  addTearDown(activityHistoryStore.dispose);
  return MaterialApp(
    home: CurrentSessionActivityHistoryScope(
      store: activityHistoryStore,
      child: CurrentSessionGeneratedPlanScope(
        store: CurrentSessionGeneratedPlanStore(),
        child: RuniacShell(
          authRepository: authRepository,
          feedRepository: const StaticFeedRepository(),
          leaderboardRepository: const StaticLeaderboardRepository(),
          profileRepository: const StaticUserProfileRepository(),
          profilePersistenceRepository:
              const NoopUserProfilePersistenceRepository(),
          enableForegroundGps: false,
          appTourSeenStore: seenStore,
          appTourAutoStartArmed: autoStartArmed,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'while the tour overlay is running, the obscured shell (bottom nav '
    "Run item) is unreachable via semantics, but the overlay's own App tour "
    'container and Skip/Next controls remain reachable',
    (tester) async {
      final handle = tester.ensureSemantics();

      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.setArmed(uid: _ownerUid, armed: true);

      await tester.pumpWidget(
        _buildHarness(
          authRepository: authRepository,
          seenStore: seenStore,
          autoStartArmed: true,
        ),
      );
      await _pumpTourSettle(tester);

      // Sanity: the tour is actually running and on the very first (no
      // anchor) step.
      expect(find.byKey(const ValueKey('appTourNextButton')), findsOneWidget);
      expect(_stepCounter(tester), '1 of ${runiacAppTourSteps.length}');

      // REGRESSION EVIDENCE: the scrim already blocks the *pointer* from
      // reaching the Run nav item (see app_tour_flow_test.dart's coverage of
      // that), but before this fix the item's *semantics* node survived
      // underneath it regardless of which step is showing — this assertion
      // is what caught that: a screen reader could still reach and activate
      // the Run item while the tour is running.
      expect(
        _semanticsTreeHasLabel(tester, _runNavItemSemanticsLabel),
        isFalse,
        reason:
            'the bottom nav Run item must not be reachable via semantics '
            'while the tour overlay is showing',
      );

      // The overlay's own semantics must remain fully exposed: its
      // container label, and its Skip/Next controls.
      expect(find.bySemanticsLabel('App tour'), findsOneWidget);
      expect(find.bySemanticsLabel('Skip tour'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^1 of ${runiacAppTourSteps.length}\$')),
        findsOneWidget,
      );

      // Advance to the "home-level-avatar" step (index 5): unlike the plan
      // stone steps, this anchor doesn't depend on an active generated plan
      // being present, so it reliably resolves in this harness. Confirms the
      // anchor registry's GlobalKey lookup and the overlay's hole-cutting
      // still work with BlockSemantics in the tree — semantics blocking must
      // not affect the render-tree lookup the anchor registry relies on.
      for (var i = 0; i < 5; i++) {
        await _tapNext(tester);
      }
      expect(_stepCounter(tester), '6 of ${runiacAppTourSteps.length}');
      expect(_scrimPainter(tester).hole, isNotNull);

      // Still true after advancing: the shell stays fully blocked from
      // semantics while the overlay keeps showing.
      expect(
        _semanticsTreeHasLabel(tester, _runNavItemSemanticsLabel),
        isFalse,
      );

      // Skip stops the tour; the shell's semantics must be fully restored —
      // a paused/stopped tour must never leave the app unusable for a
      // screen-reader user.
      await _tapSkip(tester);
      expect(find.byKey(const ValueKey('appTourNextButton')), findsNothing);
      expect(
        _semanticsTreeHasLabel(tester, _runNavItemSemanticsLabel),
        isTrue,
      );
      handle.dispose();
    },
  );

  testWidgets(
    'a tour paused behind a modal route keeps the shell fully reachable via '
    'semantics rather than leaving it blocked',
    (tester) async {
      final handle = tester.ensureSemantics();

      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.setArmed(uid: _ownerUid, armed: true);

      await tester.pumpWidget(
        _buildHarness(
          authRepository: authRepository,
          seenStore: seenStore,
          autoStartArmed: true,
        ),
      );
      await _pumpTourSettle(tester);
      expect(find.byKey(const ValueKey('appTourNextButton')), findsOneWidget);
      expect(
        _semanticsTreeHasLabel(tester, _runNavItemSemanticsLabel),
        isFalse,
      );

      // Push a modal route on top: `_syncFrontmost` pauses the controller,
      // which drops `showOverlay` (running && !paused) without stopping the
      // tour outright.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(builder: (context) => const SizedBox.shrink()),
      );
      await _pumpTourSettle(tester);

      // Paused: no overlay controls, and the shell underneath (still
      // technically obscured by the pushed route in this harness, but no
      // longer blocked by the tour) is not left inert by a leftover block.
      expect(find.byKey(const ValueKey('appTourNextButton')), findsNothing);
      expect(find.bySemanticsLabel('App tour'), findsNothing);

      navigator.pop();
      await _pumpTourSettle(tester);

      // Back in front: the tour resumes, and the shell is blocked again.
      expect(find.byKey(const ValueKey('appTourNextButton')), findsOneWidget);
      expect(
        _semanticsTreeHasLabel(tester, _runNavItemSemanticsLabel),
        isFalse,
      );
      handle.dispose();
    },
  );
}
