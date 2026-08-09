import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/haptics/runiac_haptics.dart';

/// A [RuniacHaptics] fake that records invoked method names instead of
/// dispatching real platform haptics. Reusable by other feature tests that
/// need to assert a haptic was (or was not) requested for a given action.
class RecordingRuniacHaptics implements RuniacHaptics {
  final List<String> calls = <String>[];
  bool enabled = true;

  @override
  void selection() => calls.add('selection');

  @override
  void impactLight() => calls.add('impactLight');

  @override
  void impactMedium() => calls.add('impactMedium');

  @override
  void impactHeavy() => calls.add('impactHeavy');

  @override
  void error() => calls.add('error');

  @override
  void setEnabled(bool enabled) {
    this.enabled = enabled;
    calls.add('setEnabled($enabled)');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final frameworkCalls = <MethodCall>[];
  final androidCalls = <MethodCall>[];

  void mockFrameworkChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          frameworkCalls.add(call);
          return null;
        });
  }

  void mockAndroidChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(runiacAndroidHapticsChannel, (call) async {
          androidCalls.add(call);
          return null;
        });
  }

  setUp(() {
    frameworkCalls.clear();
    androidCalls.clear();
    mockFrameworkChannel();
    mockAndroidChannel();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, null)
      ..setMockMethodCallHandler(runiacAndroidHapticsChannel, null);
  });

  group('SystemRuniacHaptics on Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('plays every level through the Runiac vibrator channel', () async {
      final haptics = SystemRuniacHaptics();

      haptics.selection();
      await Future<void>.delayed(Duration.zero);
      expect(androidCalls, hasLength(1));
      expect(androidCalls.single.method, runiacAndroidHapticsPlayMethod);
      expect(androidCalls.single.arguments, runiacAndroidHapticSelection);
      androidCalls.clear();

      haptics.impactLight();
      await Future<void>.delayed(Duration.zero);
      expect(androidCalls.single.arguments, runiacAndroidHapticLightImpact);
      androidCalls.clear();

      haptics.impactMedium();
      await Future<void>.delayed(Duration.zero);
      expect(androidCalls.single.arguments, runiacAndroidHapticMediumImpact);
      androidCalls.clear();

      haptics.impactHeavy();
      await Future<void>.delayed(Duration.zero);
      expect(androidCalls.single.arguments, runiacAndroidHapticHeavyImpact);
      androidCalls.clear();

      haptics.error();
      await Future<void>.delayed(Duration.zero);
      expect(androidCalls.single.arguments, runiacAndroidHapticError);

      // The weak `performHapticFeedback` path this capsule replaces must not
      // fire in addition to the vibrator channel.
      expect(frameworkCalls, isEmpty);
    });

    test(
      'falls back to the framework channel when the native handler is missing',
      () async {
        // Throwing MissingPluginException from the mock handler is what makes
        // `send` resolve to null, which is exactly how a channel with no
        // native handler surfaces. Clearing the handler instead would leave
        // the message to the test engine's unimplemented path, whose timing
        // differs per host and made this assertion flaky on CI.
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(runiacAndroidHapticsChannel, (
              call,
            ) async {
              androidCalls.add(call);
              throw MissingPluginException('No implementation registered');
            });
        final haptics = SystemRuniacHaptics();

        haptics.impactMedium();
        // The fallback runs a second async hop after the channel rejects, so
        // drain the queue rather than a single microtask turn.
        await pumpEventQueue();

        // The vibrator channel is still attempted first; only after it reports
        // no implementation does the framework path run.
        expect(androidCalls, hasLength(1));
        expect(androidCalls.single.arguments, runiacAndroidHapticMediumImpact);
        expect(frameworkCalls, hasLength(1));
        expect(frameworkCalls.single.method, 'HapticFeedback.vibrate');
        expect(
          frameworkCalls.single.arguments,
          'HapticFeedbackType.mediumImpact',
        );
      },
    );

    test('disabled fires no platform calls', () async {
      final haptics = SystemRuniacHaptics(enabled: false);
      expect(haptics.enabled, isFalse);

      haptics.selection();
      haptics.impactLight();
      haptics.impactMedium();
      haptics.impactHeavy();
      haptics.error();
      await Future<void>.delayed(Duration.zero);

      expect(androidCalls, isEmpty);
      expect(frameworkCalls, isEmpty);
    });

    test('calls never throw when the platform channel fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(runiacAndroidHapticsChannel, (call) async {
            throw PlatformException(code: 'boom');
          });
      final haptics = SystemRuniacHaptics();

      expect(() => haptics.selection(), returnsNormally);
      expect(() => haptics.impactLight(), returnsNormally);
      expect(() => haptics.impactMedium(), returnsNormally);
      expect(() => haptics.impactHeavy(), returnsNormally);
      expect(() => haptics.error(), returnsNormally);

      // Flush the rejected futures so the failure is observed (and
      // swallowed) here rather than surfacing as an unhandled error later.
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('SystemRuniacHaptics off Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test(
      'enabled fires the mapped platform haptic call for each method',
      () async {
        final haptics = SystemRuniacHaptics();

        haptics.selection();
        await Future<void>.delayed(Duration.zero);
        expect(frameworkCalls, hasLength(1));
        expect(frameworkCalls.single.method, 'HapticFeedback.vibrate');
        expect(
          frameworkCalls.single.arguments,
          'HapticFeedbackType.selectionClick',
        );
        frameworkCalls.clear();

        haptics.impactLight();
        await Future<void>.delayed(Duration.zero);
        expect(
          frameworkCalls.single.arguments,
          'HapticFeedbackType.lightImpact',
        );
        frameworkCalls.clear();

        haptics.impactMedium();
        await Future<void>.delayed(Duration.zero);
        expect(
          frameworkCalls.single.arguments,
          'HapticFeedbackType.mediumImpact',
        );
        frameworkCalls.clear();

        haptics.impactHeavy();
        await Future<void>.delayed(Duration.zero);
        expect(
          frameworkCalls.single.arguments,
          'HapticFeedbackType.heavyImpact',
        );
        frameworkCalls.clear();

        haptics.error();
        await Future<void>.delayed(Duration.zero);
        expect(frameworkCalls.single.method, 'HapticFeedback.vibrate');
        expect(frameworkCalls.single.arguments, isNull);

        // The Android-only vibrator channel must stay untouched off Android.
        expect(androidCalls, isEmpty);
      },
    );

    test('disabled fires no platform calls', () async {
      final haptics = SystemRuniacHaptics(enabled: false);
      expect(haptics.enabled, isFalse);

      haptics.selection();
      haptics.impactLight();
      haptics.impactMedium();
      haptics.impactHeavy();
      haptics.error();
      await Future<void>.delayed(Duration.zero);

      expect(frameworkCalls, isEmpty);
      expect(androidCalls, isEmpty);
    });

    test(
      'setEnabled(false) then setEnabled(true) flips behavior live',
      () async {
        final haptics = SystemRuniacHaptics();
        expect(haptics.enabled, isTrue);

        haptics.setEnabled(false);
        expect(haptics.enabled, isFalse);
        haptics.selection();
        await Future<void>.delayed(Duration.zero);
        expect(frameworkCalls, isEmpty);

        haptics.setEnabled(true);
        expect(haptics.enabled, isTrue);
        haptics.selection();
        await Future<void>.delayed(Duration.zero);
        expect(frameworkCalls, hasLength(1));
        expect(frameworkCalls.single.method, 'HapticFeedback.vibrate');
      },
    );

    test('calls never throw when the platform channel fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            throw PlatformException(code: 'boom');
          });
      final haptics = SystemRuniacHaptics();

      expect(() => haptics.selection(), returnsNormally);
      expect(() => haptics.impactLight(), returnsNormally);
      expect(() => haptics.impactMedium(), returnsNormally);
      expect(() => haptics.impactHeavy(), returnsNormally);
      expect(() => haptics.error(), returnsNormally);

      await Future<void>.delayed(Duration.zero);
    });

    test('calls never throw when no platform handler is registered', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      final haptics = SystemRuniacHaptics();

      expect(() => haptics.selection(), returnsNormally);
      expect(() => haptics.error(), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('RecordingRuniacHaptics', () {
    test('records each semantic call and setEnabled by name', () {
      final recorder = RecordingRuniacHaptics();

      recorder.selection();
      recorder.impactLight();
      recorder.impactMedium();
      recorder.impactHeavy();
      recorder.error();
      recorder.setEnabled(false);

      expect(recorder.calls, [
        'selection',
        'impactLight',
        'impactMedium',
        'impactHeavy',
        'error',
        'setEnabled(false)',
      ]);
      expect(recorder.enabled, isFalse);
    });
  });
}
