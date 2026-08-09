import 'dart:async';

import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';

class InMemoryRuniacAuthRepository implements RuniacAuthRepository {
  final _authStateController = StreamController<RuniacAuthUser?>.broadcast();
  final _accountsByEmail = <String, _FakeAuthAccount>{};
  final sentPasswordResetEmails = <String>[];
  final sentEmailVerificationEmails = <String>[];
  int googleSignInCalls = 0;
  var _nextUid = 1;
  RuniacAuthUser? _currentUser;

  @override
  Stream<RuniacAuthUser?> authStateChanges() {
    return Stream<RuniacAuthUser?>.multi((controller) {
      controller.add(_currentUser);
      final subscription = _authStateController.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  RuniacAuthUser? get currentUser => _currentUser;

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    if (password.length < 8) {
      throw RuniacAuthException.fromFirebaseCode('weak-password');
    }
    if (_accountsByEmail.containsKey(normalizedEmail)) {
      throw RuniacAuthException.fromFirebaseCode('email-already-in-use');
    }

    final user = RuniacAuthUser(
      uid: 'fake-uid-${_nextUid++}',
      email: normalizedEmail,
    );
    _accountsByEmail[normalizedEmail] = _FakeAuthAccount(
      user: user,
      password: password,
    );
    _setCurrentUser(user);
    return user;
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final account = _accountsByEmail[normalizedEmail];
    if (account == null) {
      throw RuniacAuthException.fromFirebaseCode('user-not-found');
    }
    if (account.password != password) {
      throw RuniacAuthException.fromFirebaseCode('invalid-credential');
    }

    _setCurrentUser(account.user);
    return account.user;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    sentPasswordResetEmails.add(_normalizeEmail(email));
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() async {
    googleSignInCalls += 1;
    final user = RuniacAuthUser(
      uid: 'fake-google-uid-${_nextUid++}',
      email: 'google.runner@runiac.app',
      emailVerified: true,
    );
    _setCurrentUser(user);
    return user;
  }

  @override
  Future<void> sendEmailVerification() async {
    final currentUser = _currentUser;
    if (currentUser == null || currentUser.email == null) {
      throw const RuniacAuthException(
        code: RuniacAuthErrorCode.userNotFound,
        userMessage: 'Please sign in again before verifying your email.',
      );
    }
    sentEmailVerificationEmails.add(_normalizeEmail(currentUser.email!));
  }

  @override
  Future<void> signOut() async {
    _setCurrentUser(null);
  }

  void _setCurrentUser(RuniacAuthUser? user) {
    _currentUser = user;
    _authStateController.add(user);
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();
}

class _FakeAuthAccount {
  const _FakeAuthAccount({required this.user, required this.password});

  final RuniacAuthUser user;
  final String password;
}
