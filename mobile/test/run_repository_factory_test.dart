import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/run/data/firebase_run_repository.dart';
import 'package:runiac_app/features/run/data/run_repository_factory.dart';
import 'package:runiac_app/features/run/data/static_run_repository.dart';

void main() {
  setUp(() {
    // RunLaunchScreen reads voice-coaching settings from the real
    // SharedPreferences-backed repository (no fake is injected by these
    // widget tests). Without mock initial values, SharedPreferences.
    // getInstance() never resolves in the test harness (no platform-channel
    // responder), which would hang `_startRun`'s settings reload forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('RunRepositoryFactory', () {
    test('selects StaticRunRepository when emulator flag is missing', () {
      final repository = RunRepositoryFactory.create(
        config: const RuniacFirebaseRuntimeConfig(useFirebaseEmulator: false),
        completeRunCallableFactory: _FakeCallable.new,
      );

      expect(repository, isA<StaticRunRepository>());
    });

    test('selects FirebaseRunRepository when emulator flag is enabled', () {
      final repository = RunRepositoryFactory.create(
        config: const RuniacFirebaseRuntimeConfig(useFirebaseEmulator: true),
        completeRunCallableFactory: _FakeCallable.new,
        coolDownCallableFactory: _FakeCoolDownCallable.new,
      );

      expect(repository, isA<FirebaseRunRepository>());
    });

    test('selects FirebaseRunRepository when production flag is enabled', () {
      final repository = RunRepositoryFactory.create(
        config: const RuniacFirebaseRuntimeConfig(
          useFirebaseEmulator: false,
          useProductionFirebase: true,
        ),
        completeRunCallableFactory: _FakeCallable.new,
        coolDownCallableFactory: _FakeCoolDownCallable.new,
      );

      expect(repository, isA<FirebaseRunRepository>());
    });
  });

  testWidgets('Run UI works with StaticRunRepository fallback', (tester) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        runRepository: StaticRunRepository(),
      ),
    );

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(find.text('Pause'), findsOneWidget);
    expect(find.byType(FlutterError), findsNothing);
  });
}

class _FakeCallable implements CompleteRunCallable {
  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) {
    throw UnimplementedError();
  }
}

class _FakeCoolDownCallable implements CompleteCoolDownCallable {
  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) {
    throw UnimplementedError();
  }
}
