import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/phone_motion_run_cadence_provider.dart';
import 'package:runiac_app/features/run/domain/models/run_cadence_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_cadence_sample.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PhoneMotionRunCadenceProvider', () {
    const channel = MethodChannel('test/phone_motion_cadence');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('unavailable path returns no fake cadence', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return false;
            }
            return 'denied';
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final subscription = provider.cadenceStream.listen(samples.add);

      await provider.start();
      nativeEvents.add({
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 170,
        'confidence': 'estimated',
      });
      await Future<void>.delayed(Duration.zero);

      expect(await provider.isAvailable(), isFalse);
      expect(samples, isEmpty);

      await subscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('emits phoneMotion provenance from native samples', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return true;
            }
            if (call.method == 'requestPermission') {
              return 'granted';
            }
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final subscription = provider.cadenceStream.listen(samples.add);

      await provider.start();
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 95,
        'confidence': 'estimated',
      });
      nativeEvents.add({'stepsPerMinute': double.nan});
      await Future<void>.delayed(Duration.zero);

      expect(samples, hasLength(1));
      expect(samples.single.source, CadenceSource.phoneMotion);
      expect(samples.single.confidence, CadenceConfidence.estimated);
      expect(samples.single.stepsPerMinute, 95);

      await provider.pause();
      nativeEvents.add({
        'recordedAtMillis': 1782284410000,
        'stepsPerMinute': 174,
      });
      await Future<void>.delayed(Duration.zero);
      expect(samples, hasLength(1));

      await subscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('reports cadence permission denied diagnostics', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return true;
            }
            if (call.method == 'requestPermission') {
              return 'denied';
            }
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final diagnostics = <RunCadenceDiagnostics>[];
      final sampleSubscription = provider.cadenceStream.listen(samples.add);
      final diagnosticSubscription = provider.diagnosticsStream.listen(
        diagnostics.add,
      );

      await provider.start();
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 172,
        'confidence': 'estimated',
      });
      await Future<void>.delayed(Duration.zero);

      expect(samples, isEmpty);
      expect(diagnostics, isNotEmpty);
      expect(
        diagnostics.last.permissionStatus,
        RunCadencePermissionStatus.denied,
      );
      expect(
        diagnostics.last.latestReason,
        RunCadenceDiagnosticReason.permissionDenied,
      );

      await sampleSubscription.cancel();
      await diagnosticSubscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('reports filtered native cadence diagnostics', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return true;
            }
            if (call.method == 'requestPermission') {
              return 'granted';
            }
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final diagnostics = <RunCadenceDiagnostics>[];
      final sampleSubscription = provider.cadenceStream.listen(samples.add);
      final diagnosticSubscription = provider.diagnosticsStream.listen(
        diagnostics.add,
      );

      await provider.start();
      nativeEvents.add({
        'type': 'diagnostic',
        'reason': 'filteredOutOfRange',
        'stepsPerMinute': 90,
        'filteredCadenceCount': 1,
      });
      await Future<void>.delayed(Duration.zero);

      expect(samples, isEmpty);
      expect(
        diagnostics.last.latestReason,
        RunCadenceDiagnosticReason.filteredOutOfRange,
      );
      expect(diagnostics.last.filteredCadenceCount, 1);
      expect(diagnostics.last.latestFilteredCadenceSpm, 90);

      await sampleSubscription.cancel();
      await diagnosticSubscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('reports native cadence stream startup diagnostics', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return true;
            }
            if (call.method == 'requestPermission') {
              return 'granted';
            }
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final diagnostics = <RunCadenceDiagnostics>[];
      final diagnosticSubscription = provider.diagnosticsStream.listen(
        diagnostics.add,
      );

      await provider.start();
      nativeEvents.add({
        'type': 'diagnostic',
        'reason': 'streamStarted',
        'availabilityStatus': 'available',
        'permissionStatus': 'granted',
        'filteredCadenceCount': 0,
        'nativeErrorCount': 0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        diagnostics.last.latestReason,
        RunCadenceDiagnosticReason.streamStarted,
      );
      expect(
        diagnostics.last.availabilityStatus,
        RunCadenceAvailabilityStatus.available,
      );
      expect(
        diagnostics.last.permissionStatus,
        RunCadencePermissionStatus.granted,
      );

      await diagnosticSubscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('reports malformed and native error cadence diagnostics', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return true;
            }
            if (call.method == 'requestPermission') {
              return 'granted';
            }
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final diagnostics = <RunCadenceDiagnostics>[];
      final diagnosticSubscription = provider.diagnosticsStream.listen(
        diagnostics.add,
      );

      await provider.start();
      nativeEvents.add({'type': 'sample', 'stepsPerMinute': double.nan});
      nativeEvents.add({
        'type': 'diagnostic',
        'reason': 'nativeError',
        'errorCode': 'CMPedometerDenied',
        'errorMessage': 'Motion access denied.',
        'nativeErrorCount': 1,
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        diagnostics.map((diagnostic) => diagnostic.latestReason),
        containsAll([
          RunCadenceDiagnosticReason.malformedEvent,
          RunCadenceDiagnosticReason.nativeError,
        ]),
      );
      expect(diagnostics.last.nativeErrorCount, 1);
      expect(diagnostics.last.latestNativeErrorCode, 'CMPedometerDenied');

      await diagnosticSubscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('rejects a native sample with a non-finite timestamp', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') {
              return true;
            }
            if (call.method == 'requestPermission') {
              return 'granted';
            }
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final diagnostics = <RunCadenceDiagnostics>[];
      final sampleSubscription = provider.cadenceStream.listen(samples.add);
      final diagnosticSubscription = provider.diagnosticsStream.listen(
        diagnostics.add,
      );

      await provider.start();
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': double.nan,
        'stepsPerMinute': 172,
        'confidence': 'estimated',
      });
      await Future<void>.delayed(Duration.zero);

      expect(samples, isEmpty);
      expect(
        diagnostics.last.latestReason,
        RunCadenceDiagnosticReason.malformedEvent,
      );
      expect(diagnostics.last.malformedEventCount, 1);

      await sampleSubscription.cancel();
      await diagnosticSubscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test('accepts the exact Dart DateTime millisecond boundary', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'requestPermission') return 'granted';
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final subscription = provider.cadenceStream.listen(samples.add);

      await provider.start();
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': 8640000000000000,
        'stepsPerMinute': 120,
      });
      await Future<void>.delayed(Duration.zero);

      expect(samples, hasLength(1));
      expect(
        samples.single.recordedAt.millisecondsSinceEpoch,
        8640000000000000,
      );

      await subscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });

    test(
      'requests first-run permission before native availability gate',
      () async {
        var permissionRequested = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'isAvailable') {
                return permissionRequested;
              }
              if (call.method == 'requestPermission') {
                permissionRequested = true;
                return 'granted';
              }
              return null;
            });
        final nativeEvents = StreamController<Object?>.broadcast();
        final provider = PhoneMotionRunCadenceProvider(
          methodChannel: channel,
          nativeEvents: nativeEvents.stream,
        );
        final samples = <RunCadenceSample>[];
        final subscription = provider.cadenceStream.listen(samples.add);

        await provider.start();
        nativeEvents.add({
          'type': 'sample',
          'recordedAtMillis': 1782284400000,
          'stepsPerMinute': 176,
          'confidence': 'estimated',
        });
        await Future<void>.delayed(Duration.zero);

        expect(permissionRequested, isTrue);
        expect(samples.single.stepsPerMinute, 176);

        await subscription.cancel();
        await provider.dispose();
        nativeEvents.close();
      },
    );

    test(
      'treats unknown first-run permission as provisional and subscribes',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'isAvailable') {
                return true;
              }
              if (call.method == 'requestPermission') {
                return 'unknown';
              }
              return null;
            });
        final nativeEvents = StreamController<Object?>.broadcast();
        final provider = PhoneMotionRunCadenceProvider(
          methodChannel: channel,
          nativeEvents: nativeEvents.stream,
        );
        final samples = <RunCadenceSample>[];
        final diagnostics = <RunCadenceDiagnostics>[];
        final sampleSubscription = provider.cadenceStream.listen(samples.add);
        final diagnosticSubscription = provider.diagnosticsStream.listen(
          diagnostics.add,
        );

        await provider.start();
        nativeEvents.add({
          'type': 'sample',
          'recordedAtMillis': 1782284400000,
          'stepsPerMinute': 176,
          'confidence': 'estimated',
        });
        await Future<void>.delayed(Duration.zero);

        expect(samples.single.stepsPerMinute, 176);
        expect(
          diagnostics.map((diagnostic) => diagnostic.latestReason),
          contains(RunCadenceDiagnosticReason.permissionUnknown),
        );

        await sampleSubscription.cancel();
        await diagnosticSubscription.cancel();
        await provider.dispose();
        nativeEvents.close();
      },
    );

    test('rejects adversarial native sample fields as malformed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isAvailable') return true;
            if (call.method == 'requestPermission') return 'granted';
            return null;
          });
      final nativeEvents = StreamController<Object?>.broadcast();
      final provider = PhoneMotionRunCadenceProvider(
        methodChannel: channel,
        nativeEvents: nativeEvents.stream,
      );
      final samples = <RunCadenceSample>[];
      final diagnostics = <RunCadenceDiagnostics>[];
      final sampleSubscription = provider.cadenceStream.listen(samples.add);
      final diagnosticSubscription = provider.diagnosticsStream.listen(
        diagnostics.add,
      );

      await provider.start();
      nativeEvents.add({
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 170,
      });
      nativeEvents.add({
        'type': 'other',
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 170,
      });
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': 8640000000000001,
        'stepsPerMinute': 170,
      });
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 241,
      });
      nativeEvents.add({
        'type': 'sample',
        'recordedAtMillis': 1782284400000,
        'stepsPerMinute': 170,
        'acceptedCadenceCount': -1,
      });
      nativeEvents.add({
        'type': 'diagnostic',
        'reason': 'streamStarted',
        'filteredCadenceCount': -1,
      });
      await Future<void>.delayed(Duration.zero);

      expect(samples, isEmpty);
      expect(diagnostics.last.malformedEventCount, 6);
      expect(
        diagnostics.last.latestReason,
        RunCadenceDiagnosticReason.malformedEvent,
      );

      await sampleSubscription.cancel();
      await diagnosticSubscription.cancel();
      await provider.dispose();
      nativeEvents.close();
    });
  });
}
