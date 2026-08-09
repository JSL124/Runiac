import 'dart:developer' as developer;

import 'package:flutter_tts/flutter_tts.dart';

import '../domain/ports/run_speech_output.dart';
import 'flutter_tts_port.dart';

/// Production [RunSpeechOutput] backed by the `flutter_tts` plugin, reached
/// only through [FlutterTtsPort].
///
/// The underlying [FlutterTtsPort] is created lazily on first
/// [initialize]/[speak] call so merely constructing this adapter (and any
/// coordinator that holds it) never touches a platform channel. This keeps
/// it safe to construct unconditionally even when voice coaching is
/// disabled.
class FlutterTtsRunSpeechOutput implements RunSpeechOutput {
  FlutterTtsRunSpeechOutput({FlutterTtsPort Function()? portFactory})
    : _portFactory = portFactory ?? (() => PluginFlutterTtsPort(FlutterTts()));

  final FlutterTtsPort Function() _portFactory;

  FlutterTtsPort? _port;
  bool _initialized = false;
  String? _currentLanguageTag;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _port ??= _portFactory();
    await _port!.awaitSpeakCompletion(true);
    await _port!.setSpeechRate(0.48);
    await _port!.setVolume(1.0);
    // Order matters: the category must be set before the session is
    // activated, otherwise activation applies the default ambient category
    // and the hardware mute switch silences every announcement.
    final categoryApplied = await _port!.configureIosAudioDucking();
    final sessionActive = await _port!.activateAudioSession();
    if (!categoryApplied || !sessionActive) {
      // The platform reports these failures by return code rather than by
      // throwing, so this log is the only signal that voice will be silent.
      developer.log(
        'RUNIAC_VOICE audio session unavailable '
        '(category applied: $categoryApplied, session active: $sessionActive) '
        '- retrying on the next announcement',
        name: 'FlutterTtsRunSpeechOutput',
      );
      // Deliberately not latched. Audio can be unavailable for a moment at
      // run start — another app holding the session, a call ending — and
      // latching success there would leave the runner silent for the entire
      // run even once audio frees up. The setters above are idempotent, so
      // retrying costs one extra platform call per announcement at worst.
      return;
    }
    _initialized = true;
  }

  @override
  Future<void> speak(String message, {String? languageTag}) async {
    await initialize();
    if (languageTag != null && languageTag != _currentLanguageTag) {
      final available = await _port!.isLanguageAvailable(languageTag);
      final effective = available ? languageTag : 'en-US';
      await _port!.setLanguage(effective);
      _currentLanguageTag = languageTag;
    }
    await _port!.speak(message);
  }

  @override
  Future<void> stop() async {
    if (_port == null) {
      return;
    }
    await _port!.stop();
  }
}
