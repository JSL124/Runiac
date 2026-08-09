import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/assets/runiac_assets.dart';
import 'package:runiac_app/core/share/share_card_export_service.dart';
import 'package:runiac_app/core/widgets/runiac_share_bottom_sheet.dart';
import 'package:runiac_app/features/leaderboard/presentation/widgets/share_rank_floating_panel.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/widgets/share_achievement_sheet.dart';

/// Regression guard for the property that let a one-word export bug ship
/// unnoticed: every share target must leave the runner with something to read.
///
/// The original defect made `capturePng` throw on a wide-gamut device. The busy
/// wrapper around each target had a `finally` but no `catch`, so the exception
/// escaped as an unhandled async error: the spinner cleared and the tap
/// produced no result, no message, and no log — indistinguishable from a dead
/// button. These tests drive every capture-backed target through both failure
/// shapes and assert the specific message the runner sees.

/// Fails the way the real bug did: an exception escaping the capture.
class _ThrowingExportService extends ShareCardExportService {
  const _ThrowingExportService();

  @override
  Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) {
    throw StateError('Cannot use a disposed image');
  }
}

/// Fails the other supported way: a clean null the callers already handle.
class _NullExportService extends ShareCardExportService {
  const _NullExportService();

  @override
  Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    return null;
  }
}

const _thrownMessage = 'Could not share right now';
const _nullCaptureMessage = 'Could not render the card';

/// Reads the target button's own `enabled` flag. Asserting the widget property
/// rather than its semantics keeps this independent of whether a semantics
/// handle happens to be active, which differs between a solo run and the full
/// suite.
bool _targetEnabled(WidgetTester tester, String key) {
  return tester
      .widget<RuniacShareTargetButton>(find.byKey(Key(key)))
      .enabled;
}

void _sizeSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(900, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// `Clipboard.setData` rides `SystemChannels.platform`, which has no handler in
/// a widget test; without this the copy targets throw instead of confirming.
void _stubClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async => null,
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}

Widget _activitySheet(ShareCardExportService export) {
  return MaterialApp(
    home: Scaffold(
      body: ShareAchievementSheet(
        summary: defaultRunSummarySnapshot,
        exportService: export,
      ),
    ),
  );
}

Widget _rankSheet(ShareCardExportService export) {
  return MaterialApp(
    home: Scaffold(
      body: ShareRankFloatingPanel(
        regionName: 'Singapore',
        divisionName: 'Bronze',
        rankLabel: '#12',
        leagueBadgeAssetPath: RuniacAssets.leaderboardLeagueBronze,
        exportService: export,
      ),
    ),
  );
}

/// The capture-backed targets that stay enabled on every platform.
///
/// "Copy to Clipboard" is excluded because it never captures an image, which is
/// why it kept working on device while every other target went dead. Instagram
/// is excluded because it is now disabled wherever Instagram Stories cannot be
/// opened — including the test host — and is covered separately below.
const _activityTargets = <String, String>{
  'run_share_activity_save_action': 'Save',
  'run_share_activity_copy_link_action': 'Copy Link',
  'run_share_activity_more_action': 'More',
};

const _rankTargets = <String, String>{
  'leaderboard_save_rank_action': 'Save',
  'leaderboard_copy_link_action': 'Copy Link',
  'leaderboard_share_rank_more_action': 'More',
};

void main() {
  group('run activity share sheet', () {
    for (final entry in _activityTargets.entries) {
      testWidgets(
        'a thrown capture failure on "${entry.value}" still tells the runner',
        (WidgetTester tester) async {
          _sizeSurface(tester);
          _stubClipboard(tester);
          await tester.pumpWidget(
            _activitySheet(const _ThrowingExportService()),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(Key(entry.key)));
          await tester.pumpAndSettle();

          expect(
            find.text(_thrownMessage),
            findsOneWidget,
            reason:
                '${entry.value} threw and reported nothing — the exact silent '
                'failure this guard exists to prevent',
          );
        },
      );

      testWidgets('a null capture on "${entry.value}" still tells the runner', (
        WidgetTester tester,
      ) async {
        _sizeSurface(tester);
        _stubClipboard(tester);
        await tester.pumpWidget(_activitySheet(const _NullExportService()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();

        expect(find.text(_nullCaptureMessage), findsOneWidget);
      });
    }

    testWidgets('the sheet stays usable after a failed export', (
      WidgetTester tester,
    ) async {
      // The busy overlay must clear even when the action threw, otherwise the
      // whole sheet is stuck behind a spinner.
      _sizeSurface(tester);
      _stubClipboard(tester);
      await tester.pumpWidget(_activitySheet(const _ThrowingExportService()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('run_share_activity_save_action')));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // A second tap on a different target must still be accepted.
      await tester.tap(find.byKey(const Key('run_share_activity_more_action')));
      await tester.pumpAndSettle();

      expect(find.text(_thrownMessage), findsOneWidget);
    });

    testWidgets('Copy to Clipboard needs no capture and still confirms', (
      WidgetTester tester,
    ) async {
      // This is the one target that survived the device bug, because it is the
      // only one that never rasterizes the card. It must keep working even
      // while every capture-backed target is failing.
      _sizeSurface(tester);
      _stubClipboard(tester);
      await tester.pumpWidget(_activitySheet(const _ThrowingExportService()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('run_share_activity_copy_action')));
      await tester.pumpAndSettle();

      expect(find.text('Activity copied to clipboard'), findsOneWidget);
    });

    testWidgets(
      'the Instagram target is disabled where Stories cannot be opened, '
      'rather than failing on tap',
      (WidgetTester tester) async {
        // isInstagramStoryAvailable() is false off iOS, so the button is greyed
        // out. Previously it rendered enabled everywhere and a tap could only
        // ever produce an error message.
        _sizeSurface(tester);
        await tester.pumpWidget(_activitySheet(const _NullExportService()));
        await tester.pumpAndSettle();

        expect(
          _targetEnabled(tester, 'run_share_activity_instagram_action'),
          isFalse,
        );

        await tester.tap(
          find.byKey(const Key('run_share_activity_instagram_action')),
        );
        await tester.pumpAndSettle();

        expect(find.text(_nullCaptureMessage), findsNothing);
      },
    );
  });

  group('leaderboard rank share sheet', () {
    for (final entry in _rankTargets.entries) {
      testWidgets(
        'a thrown capture failure on "${entry.value}" still tells the runner',
        (WidgetTester tester) async {
          _sizeSurface(tester);
          _stubClipboard(tester);
          await tester.pumpWidget(_rankSheet(const _ThrowingExportService()));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(Key(entry.key)));
          await tester.pumpAndSettle();

          expect(find.text(_thrownMessage), findsOneWidget);
        },
      );

      testWidgets('a null capture on "${entry.value}" still tells the runner', (
        WidgetTester tester,
      ) async {
        _sizeSurface(tester);
        _stubClipboard(tester);
        await tester.pumpWidget(_rankSheet(const _NullExportService()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();

        expect(find.text(_nullCaptureMessage), findsOneWidget);
      });
    }

    testWidgets('Copy to Clipboard still confirms on the rank sheet', (
      WidgetTester tester,
    ) async {
      _sizeSurface(tester);
      _stubClipboard(tester);
      await tester.pumpWidget(_rankSheet(const _ThrowingExportService()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('leaderboard_copy_rank_action')));
      await tester.pumpAndSettle();

      expect(find.text('Rank copied to clipboard'), findsOneWidget);
    });

    testWidgets(
      'the Instagram target is disabled where Stories cannot be opened',
      (WidgetTester tester) async {
        _sizeSurface(tester);
        await tester.pumpWidget(_rankSheet(const _NullExportService()));
        await tester.pumpAndSettle();

        expect(
          _targetEnabled(tester, 'leaderboard_instagram_rank_action'),
          isFalse,
        );
      },
    );
  });
}
