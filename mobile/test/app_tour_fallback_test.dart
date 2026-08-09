import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/domain/repositories/feed_repository.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';
import 'package:runiac_app/features/leaderboard/domain/repositories/leaderboard_repository.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_seen_store.dart';
import 'package:runiac_app/features/tutorial/presentation/spotlight_scrim_painter.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';

const _ownerUid = 'test-auth-user-1';

/// See `app_tour_flow_test.dart` for why explicit ticks are used instead of
/// `pumpAndSettle`: the controller's anchor poll waits on plain
/// `Future.delayed` timers that don't necessarily schedule a new frame.
Future<void> _pumpTourSettle(WidgetTester tester, {int ticks = 50}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// See `app_tour_flow_test.dart` for why most steps advance via the Next
/// button's own `onPressed` callback rather than a simulated screen tap:
/// this suite's focus is the tour's fallback-copy behaviour, not the pixel
/// geometry of every screen it visits.
Future<void> _tapNext(WidgetTester tester) async {
  final button = tester.widget<FilledButton>(
    find.byKey(const ValueKey('appTourNextButton')),
  );
  button.onPressed!();
  await _pumpTourSettle(tester);
}

/// Advances the tour via a real `tester.tap()` on the Next button. Used on
/// the Leaderboard step specifically: its anchor is a full-bleed tab
/// background, the exact shape that once placed `AppTourOverlay`'s speech
/// bubble off-screen. A real tap proves the button is actually reachable
/// now that oversized holes degrade to the no-hole layout.
Future<void> _tapNextByTap(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('appTourNextButton')));
  await _pumpTourSettle(tester);
}

String _bubbleText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const ValueKey('appTourBubbleBody')))
      .data!;
}

/// Reads the "N of M" phrasing off the step-progress cue's `Semantics`
/// label. The cue itself renders as a compact segmented indicator, not
/// literal text, so its rendered "text" for test purposes is what assistive
/// tech would announce.
String? _stepCounter(WidgetTester tester) {
  return tester
      .widget<Semantics>(find.byKey(const ValueKey('appTourStepCounter')))
      .properties
      .label;
}

bool _slotOffstage(WidgetTester tester, int index) {
  return tester
      .widget<Offstage>(find.byKey(ValueKey<String>('runiac-shell-slot-$index')))
      .offstage;
}

/// Always returns zero posts, regardless of viewer context — used to exercise
/// the feed step's fallback to the whole-container `feedPostList` anchor when
/// there is no first post card to spotlight.
class _EmptyFeedRepository implements FeedRepository {
  const _EmptyFeedRepository();

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    return FeedReadModel(posts: const []);
  }
}

/// Always resolves to the region-required state, never a loaded map — the
/// leaderboard tab renders only its `leaderboardStateMessage` anchor in this
/// state, never `leaderboardMap`.
class _RegionRequiredLeaderboardRepository implements LeaderboardRepository {
  const _RegionRequiredLeaderboardRepository();

  @override
  Future<LeaderboardReadModel> loadLeaderboard() async {
    return LeaderboardReadModel(
      status: LeaderboardReadStatus.regionRequired,
      regionLabel: '',
      currentRunnerRankLabel: '',
      entries: const [],
    );
  }

  @override
  Future<LeaderboardReadModel> loadRegion({required String regionId}) async {
    return loadLeaderboard();
  }
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

Widget _buildHarness({
  required FakeRuniacAuthRepository authRepository,
  required AppTourSeenStore seenStore,
  LeaderboardRepository leaderboardRepository = const _RegionRequiredLeaderboardRepository(),
  FeedRepository feedRepository = const StaticFeedRepository(),
}) {
  // The You tab (visited once the tour advances past leaderboard) asserts a
  // CurrentSessionActivityHistoryScope ancestor; see
  // `shell_tab_lifecycle_test.dart` for the same wiring.
  final activityHistoryStore = CurrentSessionActivityHistoryStore(
    ownerUid: _ownerUid,
  );
  addTearDown(activityHistoryStore.dispose);
  return MaterialApp(
    home: CurrentSessionActivityHistoryScope(
      store: activityHistoryStore,
      child: CurrentSessionGeneratedPlanScope(
        // A fresh store has no active plan, so the Home stage map never
        // marks a stone `isCurrent` — the `home-today-stone` fallback
        // scenario below reuses this same "no plan yet" default state.
        store: CurrentSessionGeneratedPlanStore(),
        child: RuniacShell(
          authRepository: authRepository,
          feedRepository: feedRepository,
          leaderboardRepository: leaderboardRepository,
          profileRepository: const StaticUserProfileRepository(),
          profilePersistenceRepository:
              const NoopUserProfilePersistenceRepository(),
          enableForegroundGps: false,
          appTourSeenStore: seenStore,
          appTourAutoStartArmed: true,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'leaderboard region-required state renders fallback copy and the tour '
    'still advances to the next step',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.setArmed(uid: _ownerUid, armed: true);

      await tester.pumpWidget(
        _buildHarness(authRepository: authRepository, seenStore: seenStore),
      );
      await _pumpTourSettle(tester);

      // welcome(0) -> home-today-stone(1) -> home-stone-days(2)
      // -> home-rest-streak(3) -> home-stone-detail(4) -> home-level-avatar(5)
      // -> home-menu(6) -> run-button(7) -> feed(8) -> leaderboard(9).
      for (var i = 0; i < 9; i++) {
        await _tapNext(tester);
      }

      expect(_stepCounter(tester), '10 of 12');
      expect(
        _bubbleText(tester),
        "Pick your planning area in your profile and you'll join your "
        "city's monthly XP ranking.",
      );

      // The step is not silently skipped: Next still advances to `you`. A
      // real tap while anchored on the Leaderboard step (see
      // `_tapNextByTap`) proves the button is actually reachable.
      await _tapNextByTap(tester);
      expect(_stepCounter(tester), '11 of 12');
      expect(_slotOffstage(tester, 4), isFalse);
    },
  );

  testWidgets(
    'home with no current stage stone renders fallback copy for every '
    'stone-related step, instead of being skipped, and the tour still '
    'reaches finish',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.setArmed(uid: _ownerUid, armed: true);

      await tester.pumpWidget(
        _buildHarness(authRepository: authRepository, seenStore: seenStore),
      );
      await _pumpTourSettle(tester);

      // welcome(0) -> home-today-stone(1): `homeTodayStone` never resolves
      // without an active plan.
      await _tapNext(tester);

      expect(_stepCounter(tester), '2 of 12');
      expect(
        _bubbleText(tester),
        "Your plan appears here as a path of stones once it's ready.",
      );
      expect(_slotOffstage(tester, 0), isFalse);

      // home-today-stone(1) -> home-stone-days(2): `homeStoneCluster` also
      // never resolves without an active plan (there is no current week),
      // so this new step degrades to its fallback too.
      await _tapNext(tester);
      expect(_stepCounter(tester), '3 of 12');
      expect(
        _bubbleText(tester),
        'Your plan lays out one stone per day — some for running, some '
        'for resting.',
      );

      // home-stone-days(2) -> home-rest-streak(3): same anchor, same
      // fallback behaviour.
      await _tapNext(tester);
      expect(_stepCounter(tester), '4 of 12');
      expect(
        _bubbleText(tester),
        'Rest days are planned, not lost days. Only skipping a running '
        'day resets your streak.',
      );

      // home-rest-streak(3) -> home-stone-detail(4): back to `homeTodayStone`.
      await _tapNext(tester);
      expect(_stepCounter(tester), '5 of 12');
      expect(
        _bubbleText(tester),
        "Once your plan is ready, today's running stone opens that day's "
        'workout.',
      );

      // None of the three new steps got stuck: the tour still walks the
      // rest of the script through to `finish` with no active plan.
      for (var i = 0; i < 7; i++) {
        await _tapNext(tester);
      }
      expect(_stepCounter(tester), '12 of 12');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('appTourNextButton')),
            )
            .child,
        isA<Text>().having((text) => text.data, 'data', 'Done'),
      );
      await _tapNext(tester);
      expect(find.byKey(const ValueKey('appTourNextButton')), findsNothing);
    },
  );

  testWidgets(
    'feed with an empty timeline falls back to the whole-container anchor '
    'and the tour still advances to the next step',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.setArmed(uid: _ownerUid, armed: true);

      await tester.pumpWidget(
        _buildHarness(
          authRepository: authRepository,
          seenStore: seenStore,
          feedRepository: const _EmptyFeedRepository(),
        ),
      );
      await _pumpTourSettle(tester);

      // welcome(0) -> home-today-stone(1) -> home-stone-days(2)
      // -> home-rest-streak(3) -> home-stone-detail(4) -> home-level-avatar(5)
      // -> home-menu(6) -> run-button(7) -> feed(8).
      for (var i = 0; i < 8; i++) {
        await _tapNext(tester);
      }

      expect(_stepCounter(tester), '9 of 12');
      // No `feedFirstPost` card exists to spotlight, so the step degrades to
      // the same no-hole presentation as an oversized hole (the whole-tab
      // `feedPostList` container is the only candidate left to resolve).
      expect(_scrimPainter(tester).hole, isNull);

      // The step is not silently skipped: Next still advances to
      // `leaderboard`.
      await _tapNext(tester);
      expect(_stepCounter(tester), '10 of 12');
    },
  );
}
