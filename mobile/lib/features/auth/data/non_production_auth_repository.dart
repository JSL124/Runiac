import '../domain/runiac_auth_service.dart';

class NonProductionAuthRepository implements RuniacAuthRepository {
  const NonProductionAuthRepository();

  static const unavailableException = RuniacAuthException(
    code: RuniacAuthErrorCode.authUnavailable,
    userMessage:
        'Runiac sign-in is only available in the local Firebase emulator right now.',
  );

  @override
  Stream<RuniacAuthUser?> authStateChanges() {
    return Stream<RuniacAuthUser?>.value(null);
  }

  @override
  RuniacAuthUser? get currentUser => null;

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _unavailable();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    return _unavailable();
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() {
    return _unavailable();
  }

  @override
  Future<void> sendEmailVerification() {
    return _unavailable();
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _unavailable();
  }

  @override
  Future<void> signOut() {
    return _unavailable();
  }

  Future<T> _unavailable<T>() async {
    throw unavailableException;
  }
}
