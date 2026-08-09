import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:runiac_app/features/run/presentation/advanced_analysis_screen.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';

const _paywallTitleKey = Key('paywall-title');
const _coachingLockKey = Key('coaching-premium-lock');

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
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

  const summary = ViewSummaryScreen();
  if (subscriptionStatus == null) {
    // No account scope at all: the gate must fail open.
    await tester.pumpWidget(const MaterialApp(home: summary));
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

Future<void> _tapMoreDetails(WidgetTester tester) async {
  final button = find.text('More Details');
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
  group('Basic runner', () {
    testWidgets('More Details opens the paywall, not advanced analysis', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      await _tapMoreDetails(tester);

      expect(find.byKey(_paywallTitleKey), findsOneWidget);
      expect(find.byType(AdvancedAnalysisScreen), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets(
      'activity feedback sparkle opens the paywall, not the overlay',
      (tester) async {
        await _pumpSummary(
          tester,
          subscriptionStatus: UserSubscriptionStatus.basic,
        );

        await tester.tap(find.byTooltip('Activity feedback'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(_paywallTitleKey), findsOneWidget);

        await _teardownTree(tester);
      },
    );

    testWidgets('coaching card is blurred behind the premium teaser', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      expect(find.byKey(_coachingLockKey), findsOneWidget);
      await tester.ensureVisible(find.byKey(_coachingLockKey));
      await tester.pump();
      expect(find.text('Premium coaching'), findsOneWidget);

      await tester.tap(find.byKey(_coachingLockKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(_paywallTitleKey), findsOneWidget);

      await _teardownTree(tester);
    });
  });

  group('Premium runner', () {
    testWidgets('More Details opens advanced analysis as before', (
      tester,
    ) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
      );

      await _tapMoreDetails(tester);

      expect(find.byType(AdvancedAnalysisScreen), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets('coaching card is not locked', (tester) async {
      await _pumpSummary(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
      );

      expect(find.byKey(_coachingLockKey), findsNothing);

      await _teardownTree(tester);
    });
  });

  group('No account scope (fail-open)', () {
    testWidgets('More Details opens advanced analysis unchanged', (
      tester,
    ) async {
      await _pumpSummary(tester);

      await _tapMoreDetails(tester);

      expect(find.byType(AdvancedAnalysisScreen), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets('coaching card is not locked', (tester) async {
      await _pumpSummary(tester);

      expect(find.byKey(_coachingLockKey), findsNothing);

      await _teardownTree(tester);
    });
  });
}
