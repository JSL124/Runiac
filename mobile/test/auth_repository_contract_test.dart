import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';

import 'support/in_memory_runiac_auth_repository.dart';

void main() {
  group('InMemoryRuniacAuthRepository contract', () {
    test('creates, signs out, and signs in a user', () async {
      final repository = InMemoryRuniacAuthRepository();

      final created = await repository.createUserWithEmailAndPassword(
        email: 'new.runner@runiac.app',
        password: 'password123',
      );

      expect(created.uid, isNotEmpty);
      expect(created.email, 'new.runner@runiac.app');
      expect(repository.currentUser, created);

      await repository.signOut();
      expect(repository.currentUser, isNull);

      final signedIn = await repository.signInWithEmailAndPassword(
        email: 'new.runner@runiac.app',
        password: 'password123',
      );

      expect(signedIn, created);
      expect(repository.currentUser, created);
    });

    test('auth state stream follows current user and sign-out', () async {
      final repository = InMemoryRuniacAuthRepository();
      final observed = <RuniacAuthUser?>[];
      final subscription = repository.authStateChanges().listen(observed.add);
      addTearDown(subscription.cancel);

      await repository.createUserWithEmailAndPassword(
        email: 'stream.runner@runiac.app',
        password: 'password123',
      );
      await repository.signOut();

      await pumpEventQueue();

      expect(observed, <RuniacAuthUser?>[
        null,
        const RuniacAuthUser(
          uid: 'fake-uid-1',
          email: 'stream.runner@runiac.app',
        ),
        null,
      ]);
    });

    test('enforces weak-password and duplicate email errors', () async {
      final repository = InMemoryRuniacAuthRepository();

      await expectLater(
        repository.createUserWithEmailAndPassword(
          email: 'weak.runner@runiac.app',
          password: 'short',
        ),
        throwsA(
          isA<RuniacAuthException>().having(
            (error) => error.code,
            'code',
            RuniacAuthErrorCode.weakPassword,
          ),
        ),
      );

      await repository.createUserWithEmailAndPassword(
        email: 'taken.runner@runiac.app',
        password: 'password123',
      );
      await repository.signOut();

      await expectLater(
        repository.createUserWithEmailAndPassword(
          email: 'taken.runner@runiac.app',
          password: 'another-password',
        ),
        throwsA(
          isA<RuniacAuthException>().having(
            (error) => error.code,
            'code',
            RuniacAuthErrorCode.emailAlreadyInUse,
          ),
        ),
      );
    });

    test('enforces user-not-found and invalid-credential', () async {
      final repository = InMemoryRuniacAuthRepository();

      await expectLater(
        repository.signInWithEmailAndPassword(
          email: 'missing.runner@runiac.app',
          password: 'password123',
        ),
        throwsA(
          isA<RuniacAuthException>().having(
            (error) => error.code,
            'code',
            RuniacAuthErrorCode.userNotFound,
          ),
        ),
      );

      await repository.createUserWithEmailAndPassword(
        email: 'existing.runner@runiac.app',
        password: 'password123',
      );
      await repository.signOut();

      await expectLater(
        repository.signInWithEmailAndPassword(
          email: 'existing.runner@runiac.app',
          password: 'wrong-password',
        ),
        throwsA(
          isA<RuniacAuthException>().having(
            (error) => error.code,
            'code',
            RuniacAuthErrorCode.invalidCredential,
          ),
        ),
      );
    });

    test('reset sent records recipient without signing the user in', () async {
      final repository = InMemoryRuniacAuthRepository();

      await repository.sendPasswordResetEmail(email: 'reset.runner@runiac.app');

      expect(repository.sentPasswordResetEmails, ['reset.runner@runiac.app']);
      expect(repository.currentUser, isNull);
    });
  });
}
