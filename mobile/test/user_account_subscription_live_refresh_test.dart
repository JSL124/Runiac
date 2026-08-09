import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';

const _badgeKey = ValueKey('account-subscription-status-badge');

void main() {
  testWidgets(
    'Account subscription badge relays the trusted tier from the account stream',
    (tester) async {
      final account = _LiveUserAccountRepository(
        const UserAccountReadModel(
          subscriptionStatus: UserSubscriptionStatus.premium,
        ),
      );
      addTearDown(account.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: const _ProfileRepository(),
          userAccountRepository: account,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.byKey(_badgeKey), findsOneWidget);
      expect(find.text('PREMIUM'), findsOneWidget);
    },
  );

  testWidgets(
    'Account subscription badge upgrades in place when an admin grants premium',
    (tester) async {
      final account = _LiveUserAccountRepository(const UserAccountReadModel());
      addTearDown(account.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: const _ProfileRepository(),
          userAccountRepository: account,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('BASIC'), findsOneWidget);

      // Mirrors an admin console write to `users/{uid}.subscriptionStatus`
      // arriving over the app-level snapshot listener.
      account.publish(
        const UserAccountReadModel(
          subscriptionStatus: UserSubscriptionStatus.premium,
        ),
      );
      await tester.pumpAndSettle();

      // No restart, no re-login, and no re-navigation.
      expect(find.text('PREMIUM'), findsOneWidget);
      expect(find.text('BASIC'), findsNothing);
    },
  );

  testWidgets('Account subscription badge downgrades in place on expiry', (
    tester,
  ) async {
    final account = _LiveUserAccountRepository(
      const UserAccountReadModel(
        subscriptionStatus: UserSubscriptionStatus.premium,
      ),
    );
    addTearDown(account.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        profileRepository: const _ProfileRepository(),
        userAccountRepository: account,
      ),
    );
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('PREMIUM'), findsOneWidget);

    account.publish(const UserAccountReadModel());
    await tester.pumpAndSettle();

    expect(find.text('BASIC'), findsOneWidget);
    expect(find.text('PREMIUM'), findsNothing);
  });

  testWidgets(
    'Account subscription badge falls back to Basic without a live account source',
    (tester) async {
      await tester.pumpWidget(
        const RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _ProfileRepository(),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.byKey(_badgeKey), findsOneWidget);
      expect(find.text('BASIC'), findsOneWidget);
    },
  );
}

class _LiveUserAccountRepository implements LiveUserAccountRepository {
  _LiveUserAccountRepository(this._current);

  final _controller = StreamController<UserAccountReadModel>.broadcast();
  UserAccountReadModel _current;

  void publish(UserAccountReadModel account) {
    _current = account;
    _controller.add(account);
  }

  void dispose() {
    unawaited(_controller.close());
  }

  @override
  Future<UserAccountReadModel> loadUserAccount() async => _current;

  @override
  Stream<UserAccountReadModel> watchUserAccount() async* {
    yield _current;
    yield* _controller.stream;
  }
}

class _ProfileRepository implements UserProfileRepository {
  const _ProfileRepository();

  @override
  Future<UserProfileReadModel> loadUserProfile() async {
    return UserProfileReadModel(
      userId: 'test-account-user',
      displayName: 'Maya Tan',
      fullName: 'Maya Tan',
      nickname: 'Maya',
      avatarInitials: 'MT',
      ageYears: 24,
      weightKg: 58.5,
      locationLabel: 'Queenstown, Singapore',
      previewLevelBadge: '',
      previewNote: '',
      setupSectionLabel: 'RUNNING SETUP',
      manageSectionLabel: 'MANAGE',
      footerCaption: 'Runiac',
      setupItems: <UserProfileInfoItemReadModel>[],
      manageRows: <UserProfileManageRowReadModel>[],
    );
  }
}
