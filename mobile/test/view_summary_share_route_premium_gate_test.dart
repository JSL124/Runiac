import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_thumbnail_artifact.dart';
import 'package:runiac_app/features/feed/data/feed_publish/history_artifact_resolver.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/run/presentation/widgets/share_route_to_feed_sheet.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';

const _paywallTitleKey = Key('paywall-title');

// A 1x1 PNG so the resolved artifact renders a real MemoryImage in the sheet.
final _artifact = FeedThumbnailArtifact(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL5WQAAAABJRU5ErkJggg==',
  ),
);

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
}

// Returns a deterministic artifact so the premium/fail-open share path opens the
// sheet without hitting Mapbox or a canvas render.
class _StubHistoryArtifactResolver implements HistoryArtifactResolver {
  const _StubHistoryArtifactResolver(this.artifact);

  final FeedThumbnailArtifact artifact;

  @override
  Future<FeedThumbnailArtifact?> resolve(
    ActivityRouteThumbnailRequest request,
  ) async => artifact;
}

Future<void> _pumpSummary(
  WidgetTester tester, {
  UserSubscriptionStatus? subscriptionStatus,
}) async {
  final originalSize = tester.view.physicalSize;
  final originalDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDevicePixelRatio;
  });

  final summary = ViewSummaryScreen(
    historyArtifactResolver: _StubHistoryArtifactResolver(_artifact),
  );
  if (subscriptionStatus == null) {
    // No account scope at all: the gate must fail open.
    await tester.pumpWidget(MaterialApp(home: summary));
  } else {
    final store = CurrentSessionUserAccount(
      repository: _FixedUserAccountRepository(
        UserAccountReadModel(subscriptionStatus: subscriptionStatus),
      ),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CurrentSessionUserAccountScope(store: store, child: summary),
      ),
    );
  }
  // Let the one-shot account load resolve.
  await tester.pump();
  await tester.pump();
}

Future<void> _tapShareRoute(WidgetTester tester) async {
  final button = find.text('Share Route');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Disposes the pumped tree so the paywall's periodic highlight timer is
/// cancelled before the test ends.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

// Every case here pumps the summary WITHOUT a feature-access scope, so the
// gate resolves through `FeatureAccessReadModel.defaults`. What this file
// pins is therefore the shipped-default and fail-open behaviour, not the
// admin-configured tiers — those live in feature_access_premium_gate_test.dart,
// which injects an explicit premiumFeatureKeys list for all three directions.
void main() {
  group('Basic runner', () {
    testWidgets('Share Route opens the share sheet: default tier is Basic', (
      tester,
    ) async {
      // shareRouteToFeed ships Basic (it has been stored Basic in production
      // since 2026-07-25), so an unread config document must not paywall a
      // Basic runner out of a feature the callable would have allowed.
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      await _tapShareRoute(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ShareRouteToFeedSheet), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });
  });

  group('Premium runner', () {
    testWidgets('Share Route opens the share sheet, not the paywall', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
      );

      await _tapShareRoute(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ShareRouteToFeedSheet), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });
  });

  group('No account scope (fail-open)', () {
    testWidgets('Share Route opens the share sheet with no paywall', (
      tester,
    ) async {
      await _pumpSummary(tester);

      await _tapShareRoute(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ShareRouteToFeedSheet), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });
  });
}
