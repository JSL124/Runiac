import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/infrastructure/flutter_tts_port.dart';
import 'package:runiac_app/features/run/voice/infrastructure/flutter_tts_run_speech_output.dart';

class _FakeFlutterTtsPort implements FlutterTtsPort {
  /// Ordered log of the audio-session setup calls, so a test can assert the
  /// category is applied before the session is activated.
  final List<String> setupCalls = [];
  final List<String> languageCalls = [];
  final List<double> rateCalls = [];
  final List<double> volumeCalls = [];
  final List<bool> awaitSpeakCompletionCalls = [];
  int duckConfiguredCount = 0;
  int audioSessionActivatedCount = 0;
  final List<String> spokenMessages = [];
  int stopCallCount = 0;
  bool languageAvailableResult = true;
  bool duckResult = true;
  bool activateResult = true;

  @override
  Future<void> setLanguage(String language) async {
    languageCalls.add(language);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    rateCalls.add(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeCalls.add(volume);
  }

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    awaitSpeakCompletionCalls.add(awaitCompletion);
  }

  @override
  Future<bool> configureIosAudioDucking() async {
    duckConfiguredCount += 1;
    setupCalls.add('configureIosAudioDucking');
    return duckResult;
  }

  @override
  Future<bool> activateAudioSession() async {
    audioSessionActivatedCount += 1;
    setupCalls.add('activateAudioSession');
    return activateResult;
  }

  @override
  Future<bool> isLanguageAvailable(String language) async {
    return languageAvailableResult;
  }

  @override
  Future<void> speak(String message) async {
    spokenMessages.add(message);
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }
}

void main() {
  group('FlutterTtsRunSpeechOutput', () {
    test('constructing the adapter does not create a port (lazy init)', () {
      var factoryCallCount = 0;
      final fake = _FakeFlutterTtsPort();
      FlutterTtsRunSpeechOutput(
        portFactory: () {
          factoryCallCount += 1;
          return fake;
        },
      );

      expect(factoryCallCount, 0);
    });

    test('initialize() creates the port once and configures it', () async {
      var factoryCallCount = 0;
      final fake = _FakeFlutterTtsPort();
      final output = FlutterTtsRunSpeechOutput(
        portFactory: () {
          factoryCallCount += 1;
          return fake;
        },
      );

      await output.initialize();
      await output.initialize();

      expect(factoryCallCount, 1);
      expect(fake.awaitSpeakCompletionCalls, [true]);
      expect(fake.rateCalls, [0.48]);
      expect(fake.volumeCalls, [1.0]);
      expect(fake.duckConfiguredCount, 1);
      expect(fake.audioSessionActivatedCount, 1);
    });

    test(
      'initialize() applies the playback category before activating the '
      'audio session',
      () async {
        // Activating first would activate the *default* ambient category, which
        // the hardware mute switch silences — so the order is load-bearing, not
        // incidental.
        final fake = _FakeFlutterTtsPort();
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.initialize();

        expect(fake.setupCalls, [
          'configureIosAudioDucking',
          'activateAudioSession',
        ]);
      },
    );

    test(
      'initialize() still completes when the audio session cannot be brought '
      'up, so a failed session never blocks the run',
      () async {
        final fake = _FakeFlutterTtsPort()
          ..duckResult = false
          ..activateResult = false;
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.initialize();
        await output.speak('hello', languageTag: 'en-US');

        expect(fake.spokenMessages, ['hello']);
      },
    );

    test(
      'speak() initializes, sets the requested language, then speaks',
      () async {
        final fake = _FakeFlutterTtsPort();
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.speak('안녕', languageTag: 'ko-KR');

        expect(fake.duckConfiguredCount, 1);
        expect(fake.languageCalls, ['ko-KR']);
        expect(fake.spokenMessages, ['안녕']);
      },
    );

    test(
      'speak() switches the language when the tag changes, and skips '
      'redundant setLanguage calls for a repeated tag',
      () async {
        final fake = _FakeFlutterTtsPort();
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.speak('안녕', languageTag: 'ko-KR');
        await output.speak('hi', languageTag: 'en-US');
        await output.speak('again', languageTag: 'en-US');

        expect(fake.languageCalls, ['ko-KR', 'en-US']);
        expect(fake.spokenMessages, ['안녕', 'hi', 'again']);
      },
    );

    test('stop() before any speak does not throw and is a no-op', () async {
      final fake = _FakeFlutterTtsPort();
      final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

      await output.stop();

      expect(fake.stopCallCount, 0);
    });

    test('stop() after speak forwards to the port', () async {
      final fake = _FakeFlutterTtsPort();
      final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

      await output.speak('hello', languageTag: 'en-US');
      await output.stop();

      expect(fake.stopCallCount, 1);
    });

    test(
      'speak() falls back to en-US when the requested language is '
      'unavailable',
      () async {
        final fake = _FakeFlutterTtsPort()..languageAvailableResult = false;
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.speak('안녕', languageTag: 'ko-KR');

        expect(fake.languageCalls, ['en-US']);
        expect(fake.spokenMessages, ['안녕']);
      },
    );

    test(
      'speak() sets the requested language when it is available',
      () async {
        final fake = _FakeFlutterTtsPort()..languageAvailableResult = true;
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.speak('안녕', languageTag: 'ko-KR');

        expect(fake.languageCalls, ['ko-KR']);
      },
    );

    test(
      'a cached requested language tag is not re-queried even after an '
      'unavailable fallback',
      () async {
        final fake = _FakeFlutterTtsPort()..languageAvailableResult = false;
        final output = FlutterTtsRunSpeechOutput(portFactory: () => fake);

        await output.speak('안녕', languageTag: 'ko-KR');
        await output.speak('또', languageTag: 'ko-KR');

        expect(fake.languageCalls, ['en-US']);
        expect(fake.spokenMessages, ['안녕', '또']);
      },
    );
  });
}
