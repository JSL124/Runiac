import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/firestore_user_account_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  group('FirestoreUserAccountRepository', () {
    test('maps the trusted premium subscription status', () async {
      final repository = FirestoreUserAccountRepository(
        authRepository: FakeRuniacAuthRepository()..emitSignedIn(),
        reader: const _FakeReader({'subscriptionStatus': 'premium'}),
      );

      final account = await repository.loadUserAccount();

      expect(account.subscriptionStatus, UserSubscriptionStatus.premium);
      expect(account.isPremium, isTrue);
      expect(account.subscriptionStatusLabel, 'Premium');
    });

    test('maps the trusted basic subscription status', () async {
      final repository = FirestoreUserAccountRepository(
        authRepository: FakeRuniacAuthRepository()..emitSignedIn(),
        reader: const _FakeReader({'subscriptionStatus': 'basic'}),
      );

      final account = await repository.loadUserAccount();

      expect(account.subscriptionStatus, UserSubscriptionStatus.basic);
      expect(account.subscriptionStatusLabel, 'Basic');
    });

    test('treats a missing account document as basic', () async {
      final repository = FirestoreUserAccountRepository(
        authRepository: FakeRuniacAuthRepository()..emitSignedIn(),
        reader: const _FakeReader(null),
      );

      final account = await repository.loadUserAccount();

      expect(account.isPremium, isFalse);
    });

    test('never reads an unknown or malformed status as premium', () async {
      for (final value in <Object?>[
        null,
        '',
        'Premium ',
        'PREMIUM',
        'trial',
        1,
        true,
      ]) {
        final repository = FirestoreUserAccountRepository(
          authRepository: FakeRuniacAuthRepository()..emitSignedIn(),
          reader: _FakeReader({'subscriptionStatus': value}),
        );

        final account = await repository.loadUserAccount();

        // Trimmed/cased real values still resolve; anything else fails closed.
        final expectsPremium =
            value is String && value.trim().toLowerCase() == 'premium';
        expect(account.isPremium, expectsPremium, reason: '$value');
      }
    });

    test('reports basic without a signed-in user', () async {
      final repository = FirestoreUserAccountRepository(
        authRepository: FakeRuniacAuthRepository(),
        reader: const _FakeReader({'subscriptionStatus': 'premium'}),
      );

      final account = await repository.loadUserAccount();

      expect(account.isPremium, isFalse);
    });

    test('degrades to a one-shot read when signed out', () async {
      final repository = FirestoreUserAccountRepository(
        authRepository: FakeRuniacAuthRepository(),
        reader: const _FakeReader({'subscriptionStatus': 'premium'}),
      );

      await expectLater(
        repository.watchUserAccount(),
        emitsInOrder(<Matcher>[
          predicate<UserAccountReadModel>((account) => !account.isPremium),
          emitsDone,
        ]),
      );
    });

    test('streams trusted status changes for a signed-in user', () async {
      final reader = _FakeLiveReader();
      final repository = FirestoreUserAccountRepository(
        authRepository: FakeRuniacAuthRepository()..emitSignedIn(),
        reader: reader,
      );

      final statuses = repository
          .watchUserAccount()
          .map((account) => account.subscriptionStatus)
          .take(2)
          .toList();

      reader.emit({'subscriptionStatus': 'basic'});
      reader.emit({'subscriptionStatus': 'premium'});

      expect(await statuses, <UserSubscriptionStatus>[
        UserSubscriptionStatus.basic,
        UserSubscriptionStatus.premium,
      ]);
      await reader.close();
    });
  });

  test('keeps the account repository read-only against users/{uid}', () {
    final source = File(
      'lib/features/profile/data/firestore_user_account_repository.dart',
    ).readAsStringSync();

    expect(source, contains("collection('users')"));
    expect(source, contains('.snapshots('));
    // `firestore.rules` denies every client write to `users/{uid}`; the client
    // may only relay the trusted subscription state it reads back.
    expect(source, isNot(contains('.set(')));
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('.delete(')));
    expect(source, isNot(contains('.add(')));
  });
}

class _FakeReader implements UserAccountDocumentReader {
  const _FakeReader(this._data);

  final Map<String, Object?>? _data;

  @override
  Future<Map<String, Object?>?> readUserAccount({required String uid}) async {
    return _data;
  }
}

class _FakeLiveReader implements LiveUserAccountDocumentReader {
  final _controller = StreamController<Map<String, Object?>?>();

  void emit(Map<String, Object?>? data) => _controller.add(data);

  Future<void> close() => _controller.close();

  @override
  Future<Map<String, Object?>?> readUserAccount({required String uid}) async {
    return null;
  }

  @override
  Stream<Map<String, Object?>?> watchUserAccount({required String uid}) {
    return _controller.stream;
  }
}
