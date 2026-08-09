import 'package:firebase_app_check/firebase_app_check.dart';

typedef RuniacAppCheckActivator =
    Future<void> Function({
      required AndroidAppCheckProvider androidProvider,
      required AppleAppCheckProvider appleProvider,
    });

class RuniacAppCheckBootstrap {
  const RuniacAppCheckBootstrap._();

  /// [debugToken] pins the App Check debug token instead of letting the SDK
  /// mint a random per-device one, so a token already registered in the
  /// Firebase console keeps working across devices. Runtime-only (dart-define),
  /// never committed, and ignored outside debug providers.
  static Future<void> activate({
    required bool useDebugProviders,
    String? debugToken,
    RuniacAppCheckActivator? activator,
  }) {
    final androidProvider = useDebugProviders
        ? AndroidDebugProvider(debugToken: debugToken)
        : const AndroidPlayIntegrityProvider();
    final appleProvider = useDebugProviders
        ? AppleDebugProvider(debugToken: debugToken)
        : const AppleAppAttestWithDeviceCheckFallbackProvider();
    return (activator ?? _activateFirebase)(
      androidProvider: androidProvider,
      appleProvider: appleProvider,
    );
  }

  static Future<void> _activateFirebase({
    required AndroidAppCheckProvider androidProvider,
    required AppleAppCheckProvider appleProvider,
  }) {
    return FirebaseAppCheck.instance.activate(
      providerAndroid: androidProvider,
      providerApple: appleProvider,
    );
  }
}
