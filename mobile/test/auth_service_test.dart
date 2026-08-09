// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:runiac_app/core/firebase/runiac_firestore_gateway.dart';
import 'package:runiac_app/core/firebase/runiac_firebase_bootstrap.dart';
import 'package:runiac_app/features/auth/data/firebase_runiac_auth_repository.dart';
import 'package:runiac_app/features/auth/data/non_production_auth_repository.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/run/data/firebase_run_repository.dart';
import 'package:runiac_app/features/run/data/run_repository_factory.dart';
import 'package:runiac_app/features/run/data/static_run_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(_EmptyFirebaseCoreHostApi());

  group('Runiac auth service', () {
    test('emulator Firebase API key has the native SDK-required shape', () {
      final options = RuniacFirebaseBootstrap.emulatorFirebaseOptions;
      final apiKey = options.apiKey;

      expect(apiKey, hasLength(39));
      expect(apiKey, startsWith('A'));
      expect(options.storageBucket, isNotEmpty);
    });

    test('maps FirebaseAuthException codes to beginner-friendly errors', () {
      const cases = <_FirebaseAuthErrorCase>[
        _FirebaseAuthErrorCase(
          firebaseCode: 'weak-password',
          appCode: RuniacAuthErrorCode.weakPassword,
          message: 'Use a stronger password with at least 8 characters.',
        ),
        _FirebaseAuthErrorCase(
          firebaseCode: 'email-already-in-use',
          appCode: RuniacAuthErrorCode.emailAlreadyInUse,
          message: 'An account already exists for this email. Try logging in.',
        ),
        _FirebaseAuthErrorCase(
          firebaseCode: 'user-not-found',
          appCode: RuniacAuthErrorCode.userNotFound,
          message: 'No Runiac account was found for this email.',
        ),
        _FirebaseAuthErrorCase(
          firebaseCode: 'wrong-password',
          appCode: RuniacAuthErrorCode.wrongPassword,
          message: 'That email and password do not match.',
        ),
        _FirebaseAuthErrorCase(
          firebaseCode: 'invalid-credential',
          appCode: RuniacAuthErrorCode.invalidCredential,
          message: 'That email and password do not match.',
        ),
        _FirebaseAuthErrorCase(
          firebaseCode: 'not-a-real-code',
          appCode: RuniacAuthErrorCode.unknown,
          message: 'We could not complete that auth step. Please try again.',
        ),
      ];

      for (final testCase in cases) {
        final error = RuniacAuthException.fromFirebaseCode(
          testCase.firebaseCode,
        );

        expect(error.code, testCase.appCode, reason: testCase.firebaseCode);
        expect(
          error.userMessage,
          testCase.message,
          reason: testCase.firebaseCode,
        );
        expect(error.firebaseCode, testCase.firebaseCode);
      }
    });

    test('Google cancellation maps to a cancelled auth message', () async {
      final bootstrap = await RuniacFirebaseBootstrap.initialize(
        config: _productionConfig,
      );
      final repository = FirebaseRuniacAuthRepository(
        firebaseAuth: FirebaseAuth.instance,
        googleAuthClient: const _ThrowingGoogleAuthClient(
          GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
      );

      expect(bootstrap.authRepository, isA<FirebaseRuniacAuthRepository>());
      await expectLater(
        repository.signInWithGoogle(),
        throwsA(
          isA<RuniacAuthException>()
              .having(
                (error) => error.code,
                'code',
                RuniacAuthErrorCode.authUnavailable,
              )
              .having(
                (error) => error.userMessage,
                'message',
                'Google sign-in was cancelled.',
              ),
        ),
      );
    });

    test(
      'Google provider errors map to generic Google auth feedback',
      () async {
        await RuniacFirebaseBootstrap.initialize(config: _productionConfig);
        final repository = FirebaseRuniacAuthRepository(
          firebaseAuth: FirebaseAuth.instance,
          googleAuthClient: const _ThrowingGoogleAuthClient(
            GoogleSignInException(
              code: GoogleSignInExceptionCode.providerConfigurationError,
            ),
          ),
        );

        await expectLater(
          repository.signInWithGoogle(),
          throwsA(
            isA<RuniacAuthException>()
                .having(
                  (error) => error.code,
                  'code',
                  RuniacAuthErrorCode.unknown,
                )
                .having(
                  (error) => error.userMessage,
                  'message',
                  'We could not complete Google sign-in. Please try again.',
                ),
          ),
        );
      },
    );

    test(
      'non-production auth fallback stays signed out and unavailable',
      () async {
        const repository = NonProductionAuthRepository();
        final observed = <RuniacAuthUser?>[];
        final subscription = repository.authStateChanges().listen(observed.add);
        addTearDown(subscription.cancel);

        await pumpEventQueue();

        expect(repository.currentUser, isNull);
        expect(observed, <RuniacAuthUser?>[null]);

        await expectLater(
          repository.createUserWithEmailAndPassword(
            email: 'runner@runiac.app',
            password: 'password123',
          ),
          throwsA(
            isA<RuniacAuthException>().having(
              (error) => error.code,
              'code',
              RuniacAuthErrorCode.authUnavailable,
            ),
          ),
        );
        await expectLater(
          repository.signInWithEmailAndPassword(
            email: 'runner@runiac.app',
            password: 'password123',
          ),
          throwsA(
            isA<RuniacAuthException>().having(
              (error) => error.userMessage,
              'message',
              'Runiac sign-in is only available in the local Firebase emulator right now.',
            ),
          ),
        );
        await expectLater(
          repository.sendPasswordResetEmail(email: 'runner@runiac.app'),
          throwsA(isA<RuniacAuthException>()),
        );
        await expectLater(
          repository.signOut(),
          throwsA(isA<RuniacAuthException>()),
        );
        expect(repository.currentUser, isNull);
      },
    );

    test(
      'bootstrap uses non-production auth outside emulator by default',
      () async {
        final bootstrap = await RuniacFirebaseBootstrap.initialize(
          config: const RuniacFirebaseRuntimeConfig(useFirebaseEmulator: false),
        );

        expect(bootstrap.runRepository, isA<StaticRunRepository>());
        expect(bootstrap.authRepository, isA<NonProductionAuthRepository>());
        expect(bootstrap.firestoreGateway, isA<RuniacFirestoreGateway>());
        expect(bootstrap.firestoreGateway.usesEmulator, isFalse);
      },
    );

    test(
      'production bootstrap uses Firebase auth only with explicit config',
      () async {
        final bootstrap = await RuniacFirebaseBootstrap.initialize(
          config: _productionConfig,
          enableAnonymousEmulatorSignIn: false,
        );

        expect(bootstrap.runRepository, isA<FirebaseRunRepository>());
        expect(bootstrap.authRepository, isA<FirebaseRuniacAuthRepository>());
        expect(bootstrap.firestoreGateway.usesEmulator, isFalse);
        expect(
          bootstrap.authRepository,
          isNot(isA<NonProductionAuthRepository>()),
        );
      },
    );
  });
}

const _productionConfig = RuniacFirebaseRuntimeConfig(
  useFirebaseEmulator: false,
  useProductionFirebase: true,
  productionApiKey: 'test-api-key',
  productionAppId: '1:000000000000:ios:test',
  productionMessagingSenderId: '000000000000',
  productionProjectId: 'runiac-test',
);

class _EmptyFirebaseCoreHostApi implements TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: initializeAppRequest,
      pluginConstants: {},
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    return const <CoreInitializeResponse>[];
  }

  @override
  Future<CoreFirebaseOptions> optionsFromResource() {
    throw UnimplementedError();
  }
}

class _FirebaseAuthErrorCase {
  const _FirebaseAuthErrorCase({
    required this.firebaseCode,
    required this.appCode,
    required this.message,
  });

  final String firebaseCode;
  final RuniacAuthErrorCode appCode;
  final String message;
}

class _ThrowingGoogleAuthClient implements RuniacGoogleAuthClient {
  const _ThrowingGoogleAuthClient(this.error);

  final GoogleSignInException error;

  @override
  Future<AuthCredential?> signInCredential() {
    throw error;
  }
}
