class RuniacAuthUser {
  const RuniacAuthUser({
    required this.uid,
    required this.email,
    this.emailVerified = false,
  });

  final String uid;
  final String? email;
  final bool emailVerified;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RuniacAuthUser &&
            other.uid == uid &&
            other.email == email &&
            other.emailVerified == emailVerified;
  }

  @override
  int get hashCode => Object.hash(uid, email, emailVerified);

  @override
  String toString() {
    return 'RuniacAuthUser(uid: $uid, email: $email, '
        'emailVerified: $emailVerified)';
  }
}

enum RuniacAuthErrorCode {
  weakPassword,
  emailAlreadyInUse,
  userNotFound,
  wrongPassword,
  invalidCredential,
  invalidEmail,
  networkRequestFailed,
  tooManyRequests,
  operationNotAllowed,
  authUnavailable,
  unknown,
}

class RuniacAuthException implements Exception {
  const RuniacAuthException({
    required this.code,
    required this.userMessage,
    this.firebaseCode,
  });

  factory RuniacAuthException.fromFirebaseCode(String firebaseCode) {
    final code = _RuniacFirebaseAuthErrorMapper.mapCode(firebaseCode);
    return RuniacAuthException(
      code: code,
      userMessage: _RuniacFirebaseAuthErrorMapper.userMessage(code),
      firebaseCode: firebaseCode,
    );
  }

  final RuniacAuthErrorCode code;
  final String userMessage;
  final String? firebaseCode;

  @override
  String toString() {
    return 'RuniacAuthException(code: $code, firebaseCode: $firebaseCode)';
  }
}

abstract interface class RuniacAuthRepository {
  Stream<RuniacAuthUser?> authStateChanges();

  RuniacAuthUser? get currentUser;

  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<RuniacAuthUser> signInWithGoogle();

  Future<void> sendPasswordResetEmail({required String email});

  Future<void> sendEmailVerification();

  Future<void> signOut();
}

class _RuniacFirebaseAuthErrorMapper {
  const _RuniacFirebaseAuthErrorMapper._();

  static RuniacAuthErrorCode mapCode(String firebaseCode) {
    return switch (firebaseCode.trim().toLowerCase()) {
      'weak-password' => RuniacAuthErrorCode.weakPassword,
      'email-already-in-use' => RuniacAuthErrorCode.emailAlreadyInUse,
      'user-not-found' => RuniacAuthErrorCode.userNotFound,
      'wrong-password' => RuniacAuthErrorCode.wrongPassword,
      'invalid-credential' => RuniacAuthErrorCode.invalidCredential,
      'invalid-email' => RuniacAuthErrorCode.invalidEmail,
      'network-request-failed' => RuniacAuthErrorCode.networkRequestFailed,
      'too-many-requests' => RuniacAuthErrorCode.tooManyRequests,
      'operation-not-allowed' => RuniacAuthErrorCode.operationNotAllowed,
      _ => RuniacAuthErrorCode.unknown,
    };
  }

  static String userMessage(RuniacAuthErrorCode code) {
    return switch (code) {
      RuniacAuthErrorCode.weakPassword =>
        'Use a stronger password with at least 8 characters.',
      RuniacAuthErrorCode.emailAlreadyInUse =>
        'An account already exists for this email. Try logging in.',
      RuniacAuthErrorCode.userNotFound =>
        'No Runiac account was found for this email.',
      RuniacAuthErrorCode.wrongPassword ||
      RuniacAuthErrorCode.invalidCredential =>
        'That email and password do not match.',
      RuniacAuthErrorCode.invalidEmail => 'Enter a valid email address.',
      RuniacAuthErrorCode.networkRequestFailed =>
        'Check your connection and try again.',
      RuniacAuthErrorCode.tooManyRequests =>
        'Too many attempts. Please wait a moment and try again.',
      RuniacAuthErrorCode.operationNotAllowed =>
        'Email and password sign-in is not available yet.',
      RuniacAuthErrorCode.authUnavailable =>
        'Runiac sign-in is only available in the local Firebase emulator right now.',
      RuniacAuthErrorCode.unknown =>
        'We could not complete that auth step. Please try again.',
    };
  }
}
