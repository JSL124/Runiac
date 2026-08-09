import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/firebase/runiac_app_check_bootstrap.dart';

void main() {
  test('uses debug providers for debug and emulator launches', () async {
    AndroidAppCheckProvider? android;
    AppleAppCheckProvider? apple;

    await RuniacAppCheckBootstrap.activate(
      useDebugProviders: true,
      activator: ({required androidProvider, required appleProvider}) async {
        android = androidProvider;
        apple = appleProvider;
      },
    );

    expect(android, isA<AndroidDebugProvider>());
    expect(apple, isA<AppleDebugProvider>());
  });

  test('forwards a pinned debug token to the debug providers', () async {
    AndroidAppCheckProvider? android;
    AppleAppCheckProvider? apple;

    await RuniacAppCheckBootstrap.activate(
      useDebugProviders: true,
      debugToken: 'pinned-debug-token',
      activator: ({required androidProvider, required appleProvider}) async {
        android = androidProvider;
        apple = appleProvider;
      },
    );

    expect(
      (android as AndroidDebugProvider).debugToken,
      'pinned-debug-token',
    );
    expect((apple as AppleDebugProvider).debugToken, 'pinned-debug-token');
  });

  test('mints a random per-device token when no debug token is pinned', () async {
    AndroidAppCheckProvider? android;
    AppleAppCheckProvider? apple;

    await RuniacAppCheckBootstrap.activate(
      useDebugProviders: true,
      activator: ({required androidProvider, required appleProvider}) async {
        android = androidProvider;
        apple = appleProvider;
      },
    );

    expect((android as AndroidDebugProvider).debugToken, isNull);
    expect((apple as AppleDebugProvider).debugToken, isNull);
  });

  test('uses production attestation providers for release launches', () async {
    AndroidAppCheckProvider? android;
    AppleAppCheckProvider? apple;

    await RuniacAppCheckBootstrap.activate(
      useDebugProviders: false,
      activator: ({required androidProvider, required appleProvider}) async {
        android = androidProvider;
        apple = appleProvider;
      },
    );

    expect(android, isA<AndroidPlayIntegrityProvider>());
    expect(apple, isA<AppleAppAttestWithDeviceCheckFallbackProvider>());
  });
}
