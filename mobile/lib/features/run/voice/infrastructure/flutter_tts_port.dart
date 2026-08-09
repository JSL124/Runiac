import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the `flutter_tts` plugin so higher layers can be
/// unit-tested without exercising a platform `MethodChannel`.
///
/// `flutter_tts` must be imported ONLY in this file; every other file in the
/// voice feature depends on this abstraction instead.
abstract interface class FlutterTtsPort {
  Future<void> setLanguage(String language);

  Future<void> setSpeechRate(double rate);

  Future<void> setVolume(double volume);

  Future<void> awaitSpeakCompletion(bool awaitCompletion);

  /// Activates the shared `AVAudioSession` on iOS. Returns whether activation
  /// succeeded (always true on non-iOS, where there is nothing to activate).
  Future<bool> activateAudioSession();

  /// Applies the playback audio category on iOS. Returns whether the category
  /// was applied (always true on non-iOS, where there is nothing to apply).
  Future<bool> configureIosAudioDucking();

  Future<bool> isLanguageAvailable(String language);

  Future<void> speak(String message);

  Future<void> stop();
}

/// Production [FlutterTtsPort] backed by a real `FlutterTts` plugin
/// instance.
///
/// Every plugin call is guarded so a platform that lacks (or misbehaves on)
/// a given API degrades gracefully instead of crashing an in-progress run.
class PluginFlutterTtsPort implements FlutterTtsPort {
  PluginFlutterTtsPort(this._tts);

  final FlutterTts _tts;

  @override
  Future<void> setLanguage(String language) async {
    try {
      await _tts.setLanguage(language);
    } catch (_) {
      // Unsupported/unavailable language on this platform: no-op.
    }
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {
      // Rate control unsupported on this platform: no-op.
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _tts.setVolume(volume);
    } catch (_) {
      // Volume control unsupported on this platform: no-op.
    }
  }

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    try {
      await _tts.awaitSpeakCompletion(awaitCompletion);
    } catch (_) {
      // Unsupported on this platform: no-op.
    }
  }

  /// Activates the shared `AVAudioSession`.
  ///
  /// Setting the category is not enough on its own: `setIosAudioCategory`
  /// only calls `AVAudioSession.setCategory`, and the session must also be
  /// made active before `AVSpeechSynthesizer` output is reliably audible.
  /// The plugin exposes activation as this separate call.
  @override
  Future<bool> activateAudioSession() async {
    if (!Platform.isIOS) {
      return true;
    }
    try {
      // The plugin signals failure by returning 0 rather than by throwing.
      final result = await _tts.setSharedInstance(true);
      return _isPluginSuccess(result);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> configureIosAudioDucking() async {
    if (!Platform.isIOS) {
      return true;
    }
    try {
      // `.playback` is what lets voice coaching be heard while the ring/silent
      // switch is on. If this call fails the session stays on the default
      // ambient category, which the mute switch silences.
      final result = await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
      );
      return _isPluginSuccess(result);
    } catch (_) {
      // Audio category configuration is a best-effort convenience: no-op if
      // the installed plugin/platform version doesn't support it.
      return false;
    }
  }

  /// `flutter_tts` reports success as `1` and failure as `0`, typed loosely as
  /// `dynamic`. A null result means the call returned nothing rather than
  /// failing, which every platform does for at least one of these methods, so
  /// it is treated as success.
  static bool _isPluginSuccess(Object? result) {
    if (result == null) {
      return true;
    }
    if (result is bool) {
      return result;
    }
    if (result is num) {
      return result != 0;
    }
    return true;
  }

  @override
  Future<bool> isLanguageAvailable(String language) async {
    try {
      final result = await _tts.isLanguageAvailable(language);
      if (result is bool) {
        return result;
      }
      if (result is num) {
        return result != 0;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> speak(String message) async {
    try {
      final result = await _tts.speak(message);
      if (!_isPluginSuccess(result)) {
        // The plugin reports a refused utterance by returning 0 instead of
        // throwing, so without this the run is silent with no trace anywhere.
        developer.log(
          'RUNIAC_VOICE speak refused by the platform',
          name: 'PluginFlutterTtsPort',
        );
      }
    } catch (error, stackTrace) {
      // Speak failures are handled by the caller; degrade to no-op here so
      // a single bad platform call cannot crash the run session.
      developer.log(
        'RUNIAC_VOICE speak failed',
        name: 'PluginFlutterTtsPort',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop / unsupported: no-op.
    }
  }
}
