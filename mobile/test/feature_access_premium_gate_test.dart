import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_thumbnail_artifact.dart';
import 'package:runiac_app/features/feed/data/feed_publish/history_artifact_resolver.dart';
import 'package:runiac_app/features/paywall/domain/models/feature_access_read_model.dart';
import 'package:runiac_app/features/paywall/domain/repositories/feature_access_repository.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_feature_access.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/run/presentation/widgets/share_route_to_feed_sheet.dart';
import 'package:runiac_app/features/run/presentation/widgets/share_achievement_sheet.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';

// Does the Platform Administrator's config/featureAccess tier actually reach
// the app? Every case here pumps the real run-summary surface with a real
// FeatureAccessScope and asserts the tap outcome flips with the document —
// the gates used to hardcode "Basic sees the paywall" and ignored the
// document entirely, so a console flip changed nothing on device.

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

/// Stands in for the admin-published document with an explicit premium list.
class _FixedFeatureAccessRepository implements FeatureAccessRepository {
  const _FixedFeatureAccessRepository(this.premiumFeatureKeys);

  final List<String> premiumFeatureKeys;

  @override
  Future<FeatureAccessReadModel> loadFeatureAccess() async =>
      FeatureAccessReadModel(premiumFeatureKeys: premiumFeatureKeys);
}

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
  required UserSubscriptionStatus subscriptionStatus,
  required List<String> premiumFeatureKeys,
}) async {
  final originalSize = tester.view.physicalSize;
  final originalDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDevicePixelRatio;
  });

  final accountStore = CurrentSessionUserAccount(
    repository: _FixedUserAccountRepository(
      UserAccountReadModel(subscriptionStatus: subscriptionStatus),
    ),
  );
  addTearDown(accountStore.dispose);
  final featureAccessStore = CurrentSessionFeatureAccess(
    repository: _FixedFeatureAccessRepository(premiumFeatureKeys),
  );
  addTearDown(featureAccessStore.dispose);
  await featureAccessStore.ensureLoaded();

  await tester.pumpWidget(
    MaterialApp(
      home: CurrentSessionUserAccountScope(
        store: accountStore,
        child: FeatureAccessScope(
          store: featureAccessStore,
          child: ViewSummaryScreen(
            historyArtifactResolver: _StubHistoryArtifactResolver(_artifact),
          ),
        ),
      ),
    ),
  );
  // Let the one-shot account load resolve.
  await tester.pump();
  await tester.pump();
}

Future<void> _tapByText(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapByTooltip(WidgetTester tester, String tooltip) async {
  final button = find.byTooltip(tooltip);
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

void main() {
  group('shareRouteToFeed', () {
    testWidgets('a Basic runner shares freely once the admin sets it to Basic', (
      tester,
    ) async {
      // The reported bug: the console said Basic, the server allowed it, and
      // the app still opened the paywall.
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        premiumFeatureKeys: const ['advancedAnalysis'],
      );

      await _tapByText(tester, 'Share Route');
      await tester.pumpAndSettle();

      expect(find.byType(ShareRouteToFeedSheet), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets('a Basic runner is intercepted while the admin keeps it Premium', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        premiumFeatureKeys: const ['shareRouteToFeed'],
      );

      await _tapByText(tester, 'Share Route');

      expect(find.byKey(_paywallTitleKey), findsOneWidget);
      expect(find.byType(ShareRouteToFeedSheet), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets('a Premium runner shares regardless of the tier', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
        premiumFeatureKeys: const ['shareRouteToFeed'],
      );

      await _tapByText(tester, 'Share Route');
      await tester.pumpAndSettle();

      expect(find.byType(ShareRouteToFeedSheet), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });
  });

  group('shareCards', () {
    testWidgets('Share summary is open to Basic while the tier is Basic', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        premiumFeatureKeys: const [],
      );

      await _tapByTooltip(tester, 'Share summary');
      await tester.pumpAndSettle();

      expect(find.byType(ShareAchievementSheet), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets('promoting shareCards to Premium starts intercepting Basic', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        premiumFeatureKeys: const ['shareCards'],
      );

      await _tapByTooltip(tester, 'Share summary');

      expect(find.byKey(_paywallTitleKey), findsOneWidget);
      expect(find.byType(ShareAchievementSheet), findsNothing);

      await _teardownTree(tester);
    });
  });

  group('advancedAnalysis', () {
    testWidgets('opening it to Basic unlocks the coaching card too', (
      tester,
    ) async {
      // The coaching card follows the same key, so an admin who opens
      // Advanced analysis does not leave a stray locked card behind.
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        premiumFeatureKeys: const [],
      );

      await _tapByText(tester, 'More Details');
      await tester.pumpAndSettle();

      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });
  });
}
