import 'dart:async';

import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';

class FakeRuniacAuthRepository implements RuniacAuthRepository {
  FakeRuniacAuthRepository({
    this.signInError,
    this.createUserError,
    this.googleSignInError,
    this.resetError,
    this.emailVerificationError,
  });

  final _controller = StreamController<RuniacAuthUser?>.broadcast();
  final RuniacAuthException? signInError;
  final RuniacAuthException? createUserError;
  final RuniacAuthException? googleSignInError;
  final RuniacAuthException? resetError;
  final RuniacAuthException? emailVerificationError;

  RuniacAuthUser? _currentUser;
  Completer<RuniacAuthUser>? _heldSignIn;
  Completer<RuniacAuthUser>? _heldGoogleSignIn;
  Completer<void>? _pendingSignOut;

  int authStateListenCount = 0;
  int signInCalls = 0;
  int createUserCalls = 0;
  int googleSignInCalls = 0;
  int resetCalls = 0;
  int sendEmailVerificationCalls = 0;
  int signOutCalls = 0;
  String? lastSignInEmail;
  String? lastSignInPassword;
  String? lastCreateUserEmail;
  String? lastCreateUserPassword;
  String? lastResetEmail;

  @override
  Stream<RuniacAuthUser?> authStateChanges() {
    authStateListenCount += 1;
    return _controller.stream;
  }

  @override
  RuniacAuthUser? get currentUser => _currentUser;

  void dispose() {
    _controller.close();
  }

  void emitSignedIn({
    bool emailVerified = true,
    String uid = 'test-auth-user-1',
  }) {
    _currentUser = RuniacAuthUser(
      uid: uid,
      email: 'runner@runiac.app',
      emailVerified: emailVerified,
    );
    _controller.add(_currentUser);
  }

  void emitSignedOut() {
    _currentUser = null;
    _controller.add(null);
  }

  void holdNextSignIn() {
    _heldSignIn = Completer<RuniacAuthUser>();
  }

  void holdNextGoogleSignIn() {
    _heldGoogleSignIn = Completer<RuniacAuthUser>();
  }

  void completeHeldSignIn() {
    final completer = _heldSignIn;
    if (completer == null || completer.isCompleted) {
      return;
    }
    emitSignedIn();
    completer.complete(_currentUser!);
  }

  void completeHeldGoogleSignIn() {
    final completer = _heldGoogleSignIn;
    if (completer == null || completer.isCompleted) {
      return;
    }
    emitSignedIn();
    completer.complete(_currentUser!);
  }

  void holdNextSignOut() {
    _pendingSignOut = Completer<void>();
  }

  void completePendingSignOut() {
    _pendingSignOut?.complete();
    _pendingSignOut = null;
  }

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    createUserCalls += 1;
    lastCreateUserEmail = email;
    lastCreateUserPassword = password;
    final error = createUserError;
    if (error != null) {
      throw error;
    }
    emitSignedIn();
    return _currentUser!;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetCalls += 1;
    lastResetEmail = email;
    final error = resetError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    sendEmailVerificationCalls += 1;
    final error = emailVerificationError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCalls += 1;
    lastSignInEmail = email;
    lastSignInPassword = password;
    final error = signInError;
    if (error != null) {
      throw error;
    }
    final heldSignIn = _heldSignIn;
    if (heldSignIn != null) {
      return heldSignIn.future;
    }
    emitSignedIn();
    return _currentUser!;
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() async {
    googleSignInCalls += 1;
    final error = googleSignInError;
    if (error != null) {
      throw error;
    }
    final heldGoogleSignIn = _heldGoogleSignIn;
    if (heldGoogleSignIn != null) {
      return heldGoogleSignIn.future;
    }
    emitSignedIn();
    return _currentUser!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    final pendingSignOut = _pendingSignOut;
    if (pendingSignOut != null) {
      await pendingSignOut.future;
    }
    emitSignedOut();
  }
}
