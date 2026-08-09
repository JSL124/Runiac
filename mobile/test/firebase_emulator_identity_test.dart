import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/firebase/runiac_firebase_bootstrap.dart';
import 'package:runiac_app/features/run/data/run_repository_factory.dart';

/// App Check is the one Firebase component that never talks to the emulator:
/// it always exchanges its token with the real backend. An emulator run that
/// boots with the placeholder project therefore cannot mint a token, and the
/// iOS Firestore SDK turns that failure into a watch-stream error — every read
/// then fails with "client is offline". These tests pin the identity rule that
/// keeps a local emulator run usable.
void main() {
  group('firebaseOptionsForEmulator', () {
    test('uses the real project identity when production defines are set', () {
      const config = RuniacFirebaseRuntimeConfig(
        useFirebaseEmulator: true,
        useProductionFirebase: true,
        productionApiKey: 'api-key',
        productionAppId: '1:299427653807:ios:abc',
        productionMessagingSenderId: '299427653807',
        productionProjectId: 'runiac-fypp',
        productionStorageBucket: 'runiac-fypp.appspot.com',
      );

      final options = RuniacFirebaseBootstrap.firebaseOptionsForEmulator(
        config,
      );

      expect(options.projectId, 'runiac-fypp');
      expect(options.appId, '1:299427653807:ios:abc');
      expect(options.storageBucket, 'runiac-fypp.appspot.com');
    });

    test('falls back to the placeholder project without those defines', () {
      const config = RuniacFirebaseRuntimeConfig(useFirebaseEmulator: true);

      final options = RuniacFirebaseBootstrap.firebaseOptionsForEmulator(
        config,
      );

      expect(options.projectId, 'demo-runiac-feed');
      expect(options, RuniacFirebaseBootstrap.emulatorFirebaseOptions);
    });

    test('never silently accepts a half-configured production identity', () {
      const config = RuniacFirebaseRuntimeConfig(
        useFirebaseEmulator: true,
        useProductionFirebase: true,
        productionApiKey: 'api-key',
      );

      expect(
        () => RuniacFirebaseBootstrap.firebaseOptionsForEmulator(config),
        throwsA(isA<StateError>()),
      );
    });
  });
}
