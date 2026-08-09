import '../domain/repositories/run_repository.dart';
import 'firebase_run_repository.dart';
import 'flutterfire_complete_cool_down_callable.dart';
import 'flutterfire_complete_run_callable.dart';
import 'static_run_repository.dart';

typedef CompleteRunCallableFactory = CompleteRunCallable Function();
typedef CompleteCoolDownCallableFactory = CompleteCoolDownCallable Function();

class RuniacFirebaseRuntimeConfig {
  const RuniacFirebaseRuntimeConfig({
    required this.useFirebaseEmulator,
    this.emulatorHost = defaultEmulatorHost,
    this.useProductionFirebase = false,
    this.productionApiKey = '',
    this.productionAppId = '',
    this.productionMessagingSenderId = '',
    this.productionProjectId = '',
    this.productionStorageBucket = '',
    this.enableIosPushNotifications = false,
  });

  factory RuniacFirebaseRuntimeConfig.fromEnvironment() {
    return const RuniacFirebaseRuntimeConfig(
      useFirebaseEmulator: bool.fromEnvironment('RUNIAC_FIREBASE_EMULATOR'),
      emulatorHost: String.fromEnvironment(
        'RUNIAC_FIREBASE_EMULATOR_HOST',
        defaultValue: defaultEmulatorHost,
      ),
      useProductionFirebase: bool.fromEnvironment('RUNIAC_FIREBASE_PRODUCTION'),
      productionApiKey: String.fromEnvironment('RUNIAC_FIREBASE_API_KEY'),
      productionAppId: String.fromEnvironment('RUNIAC_FIREBASE_APP_ID'),
      productionMessagingSenderId: String.fromEnvironment(
        'RUNIAC_FIREBASE_MESSAGING_SENDER_ID',
      ),
      productionProjectId: String.fromEnvironment('RUNIAC_FIREBASE_PROJECT_ID'),
      productionStorageBucket: String.fromEnvironment(
        'RUNIAC_FIREBASE_STORAGE_BUCKET',
      ),
      enableIosPushNotifications: bool.fromEnvironment(
        'RUNIAC_ENABLE_IOS_PUSH',
      ),
    );
  }

  static const defaultEmulatorHost = '127.0.0.1';

  final bool useFirebaseEmulator;
  final String emulatorHost;
  final bool useProductionFirebase;
  final String productionApiKey;
  final String productionAppId;
  final String productionMessagingSenderId;
  final String productionProjectId;
  final String productionStorageBucket;
  final bool enableIosPushNotifications;
}

class RunRepositoryFactory {
  const RunRepositoryFactory._();

  static RunRepository create({
    RuniacFirebaseRuntimeConfig? config,
    CompleteRunCallableFactory completeRunCallableFactory =
        _defaultCompleteRunCallableFactory,
    CompleteCoolDownCallableFactory coolDownCallableFactory =
        _defaultCompleteCoolDownCallableFactory,
  }) {
    final runtimeConfig =
        config ?? RuniacFirebaseRuntimeConfig.fromEnvironment();
    if (runtimeConfig.useFirebaseEmulator ||
        runtimeConfig.useProductionFirebase) {
      return FirebaseRunRepository(
        callable: completeRunCallableFactory(),
        coolDownCallable: coolDownCallableFactory(),
      );
    }

    return const StaticRunRepository();
  }

  static CompleteRunCallable _defaultCompleteRunCallableFactory() {
    return FlutterFireCompleteRunCallable();
  }

  static CompleteCoolDownCallable _defaultCompleteCoolDownCallableFactory() {
    return FlutterFireCompleteCoolDownCallable();
  }
}
