import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/paywall/domain/models/feature_access_read_model.dart';
import 'package:runiac_app/features/paywall/domain/repositories/feature_access_repository.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_feature_access.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_paywall_config.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:runiac_app/features/you/presentation/widgets/premium_upsell_section.dart';

import 'support/premium_user_account_repository.dart';

const _sectionKey = Key('premium-upsell-section');

class _FixedFeatureAccessRepository implements FeatureAccessRepository {
  const _FixedFeatureAccessRepository(this.keys);

  final List<String> keys;

  @override
  Future<FeatureAccessReadModel> loadFeatureAccess() async {
    return FeatureAccessReadModel(premiumFeatureKeys: keys);
  }
}

Future<void> _pumpSection(
  WidgetTester tester, {
  UserAccountRepository? accountRepository,
  FeatureAccessRepository featureAccessRepository =
      const StaticFeatureAccessRepository(),
}) async {
  const section = Scaffold(
    body: SingleChildScrollView(child: PremiumUpsellSection()),
  );
  if (accountRepository == null) {
    // No scopes at all: the gate must treat the account as unresolved.
    await tester.pumpWidget(const MaterialApp(home: section));
  } else {
    final accountStore = CurrentSessionUserAccount(
      repository: accountRepository,
    );
    addTearDown(accountStore.dispose);
    final paywallConfigStore = CurrentSessionPaywallConfig();
    addTearDown(paywallConfigStore.dispose);
    final featureAccessStore = CurrentSessionFeatureAccess(
      repository: featureAccessRepository,
    );
    addTearDown(featureAccessStore.dispose);
    await tester.pumpWidget(
      CurrentSessionUserAccountScope(
        store: accountStore,
        child: PaywallConfigScope(
          store: paywallConfigStore,
          child: FeatureAccessScope(
            store: featureAccessStore,
            child: const MaterialApp(home: section),
          ),
        ),
      ),
    );
  }
  // Account load + feature-access load + the finite staggered entrance.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Basic runner sees the upsell and tapping opens the paywall', (
    WidgetTester tester,
  ) async {
    await _pumpSection(
      tester,
      accountRepository: const StaticUserAccountRepository(),
    );

    expect(find.byKey(_sectionKey), findsOneWidget);
    expect(find.text('Unlock your full potential'), findsOneWidget);
    expect(
      find.text('Go deeper on every run with Runiac Premium.'),
      findsOneWidget,
    );
    expect(find.text("What's included with Premium"), findsOneWidget);
    // Built-in default checklist: advancedAnalysis only.
    expect(find.text('Advanced run analysis'), findsOneWidget);
    expect(
      find.byKey(const Key('premium-upsell-feature-advancedAnalysis')),
      findsOneWidget,
    );

    // Bounded pumps while the sheet is open: its highlight timer never
    // settles under pumpAndSettle.
    await tester.tap(find.byKey(_sectionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('paywall-title')), findsOneWidget);

    // Dispose the sheet (and its periodic timer) before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lists exactly the admin premium-checked features in order', (
    WidgetTester tester,
  ) async {
    await _pumpSection(
      tester,
      accountRepository: const StaticUserAccountRepository(),
      featureAccessRepository: const _FixedFeatureAccessRepository([
        'activityFeedback',
        'shareCards',
        'someFutureFeature',
      ]),
    );

    // Catalog labels for known keys, humanized fallback for unknown ones.
    expect(find.text('AI activity feedback'), findsOneWidget);
    expect(find.text('Share cards'), findsOneWidget);
    expect(find.text('Some future feature'), findsOneWidget);
    expect(find.text('Advanced run analysis'), findsNothing);

    final feedbackY = tester
        .getTopLeft(
          find.byKey(const Key('premium-upsell-feature-activityFeedback')),
        )
        .dy;
    final shareY = tester
        .getTopLeft(find.byKey(const Key('premium-upsell-feature-shareCards')))
        .dy;
    expect(feedbackY, lessThan(shareY));
  });

  testWidgets('reduced motion renders the list settled without animating', (
    WidgetTester tester,
  ) async {
    final accountStore = CurrentSessionUserAccount(
      repository: const StaticUserAccountRepository(),
    );
    addTearDown(accountStore.dispose);
    final paywallConfigStore = CurrentSessionPaywallConfig();
    addTearDown(paywallConfigStore.dispose);
    final featureAccessStore = CurrentSessionFeatureAccess(
      repository: const _FixedFeatureAccessRepository([
        'advancedAnalysis',
        'shareCards',
      ]),
    );
    addTearDown(featureAccessStore.dispose);

    await tester.pumpWidget(
      CurrentSessionUserAccountScope(
        store: accountStore,
        child: PaywallConfigScope(
          store: paywallConfigStore,
          child: FeatureAccessScope(
            store: featureAccessStore,
            child: const MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: true),
                child: Scaffold(
                  body: SingleChildScrollView(child: PremiumUpsellSection()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Advanced run analysis'), findsOneWidget);
    expect(find.text('Share cards'), findsOneWidget);
  });

  testWidgets('Premium runner sees nothing', (WidgetTester tester) async {
    await _pumpSection(
      tester,
      accountRepository: const PremiumUserAccountRepository(),
    );

    expect(find.byKey(_sectionKey), findsNothing);
    expect(find.text('Unlock your full potential'), findsNothing);
  });

  testWidgets('absent scopes render nothing (unresolved account)', (
    WidgetTester tester,
  ) async {
    await _pumpSection(tester);

    expect(find.byKey(_sectionKey), findsNothing);
    expect(find.text('Unlock your full potential'), findsNothing);
  });
}
