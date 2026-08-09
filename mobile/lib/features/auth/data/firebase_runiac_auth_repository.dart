import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/runiac_auth_service.dart';

class FirebaseRuniacAuthRepository implements RuniacAuthRepository {
  FirebaseRuniacAuthRepository({
    required this.firebaseAuth,
    RuniacGoogleAuthClient? googleAuthClient,
  }) : googleAuthClient = googleAuthClient ?? GoogleSignInRuniacAuthClient();

  final FirebaseAuth firebaseAuth;
  final RuniacGoogleAuthClient googleAuthClient;

  @override
  Stream<RuniacAuthUser?> authStateChanges() {
    return firebaseAuth.authStateChanges().map(_mapUser);
  }

  @override
  RuniacAuthUser? get currentUser => _mapUser(firebaseAuth.currentUser);

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _runAuthOperation(
      () => firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await firebaseAuth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (error) {
      throw RuniacAuthException.fromFirebaseCode(error.code);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = firebaseAuth.currentUser;
    if (user == null) {
      throw const RuniacAuthException(
        code: RuniacAuthErrorCode.userNotFound,
        userMessage: 'Please sign in again before verifying your email.',
      );
    }
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw RuniacAuthException.fromFirebaseCode(error.code);
    }
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() async {
    try {
      final credential = await googleAuthClient.signInCredential();
      if (credential == null) {
        throw const RuniacAuthException(
          code: RuniacAuthErrorCode.authUnavailable,
          userMessage: 'Google sign-in was cancelled.',
        );
      }
      return _mapCredential(
        await firebaseAuth.signInWithCredential(credential),
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const RuniacAuthException(
          code: RuniacAuthErrorCode.authUnavailable,
          userMessage: 'Google sign-in was cancelled.',
        );
      }
      throw const RuniacAuthException(
        code: RuniacAuthErrorCode.unknown,
        userMessage: 'We could not complete Google sign-in. Please try again.',
      );
    } on FirebaseAuthException catch (error) {
      throw RuniacAuthException.fromFirebaseCode(error.code);
    } on RuniacAuthException {
      rethrow;
    } catch (_) {
      throw const RuniacAuthException(
        code: RuniacAuthErrorCode.unknown,
        userMessage: 'We could not complete Google sign-in. Please try again.',
      );
    }
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _runAuthOperation(
      () => firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await firebaseAuth.signOut();
    } on FirebaseAuthException catch (error) {
      throw RuniacAuthException.fromFirebaseCode(error.code);
    }
  }

  Future<RuniacAuthUser> _runAuthOperation(
    Future<UserCredential> Function() operation,
  ) async {
    try {
      return _mapCredential(await operation());
    } on FirebaseAuthException catch (error) {
      throw RuniacAuthException.fromFirebaseCode(error.code);
    }
  }

  RuniacAuthUser _mapCredential(UserCredential credential) {
    final user = credential.user;
    if (user == null) {
      throw const RuniacAuthException(
        code: RuniacAuthErrorCode.unknown,
        userMessage: 'We could not complete that auth step. Please try again.',
      );
    }
    return _mapUser(user)!;
  }

  RuniacAuthUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }
    return RuniacAuthUser(
      uid: user.uid,
      email: user.email,
      emailVerified: user.emailVerified,
    );
  }
}

abstract interface class RuniacGoogleAuthClient {
  Future<AuthCredential?> signInCredential();
}

class GoogleSignInRuniacAuthClient implements RuniacGoogleAuthClient {
  GoogleSignInRuniacAuthClient({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  @override
  Future<AuthCredential?> signInCredential() async {
    await _ensureInitialized();
    final account = await _googleSignIn.authenticate();
    final authentication = account.authentication;
    return GoogleAuthProvider.credential(idToken: authentication.idToken);
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _googleSignIn.initialize();
  }
}
