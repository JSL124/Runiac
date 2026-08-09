import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Voice coaching depends on two pieces of native manifest configuration that
/// no Dart test can otherwise reach, and whose absence produces silence with
/// no error anywhere — the platform reports both failures by return code
/// rather than by throwing, and the Dart layers above swallow those.
///
/// Both were missing when voice coaching shipped: neither the iOS nor the
/// Android manifest was touched by any of the four voice commits. These are
/// cheap textual guards so a future manifest edit cannot silently remove them
/// again.
void main() {
  group('iOS Info.plist', () {
    late String plist;

    setUpAll(() {
      plist = File('ios/Runner/Info.plist').readAsStringSync();
    });

    test('declares the audio background mode', () {
      // Voice coaching speaks while a run is in progress, which is exactly
      // when the screen is locked and the phone is in a pocket. `location`
      // alone keeps the process alive but grants no audio playback, so every
      // announcement after the screen locks is silenced without this.
      final backgroundModes = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist);

      expect(
        backgroundModes,
        isNotNull,
        reason: 'UIBackgroundModes must be present for run tracking',
      );
      expect(
        backgroundModes!.group(1),
        contains('<string>audio</string>'),
        reason: 'without `audio`, voice coaching is silent once backgrounded',
      );
    });

    test('keeps the location background mode for run tracking', () {
      final backgroundModes = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist);

      expect(backgroundModes!.group(1), contains('<string>location</string>'));
    });
  });

  group('Android manifest', () {
    late String manifest;

    setUpAll(() {
      manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
    });

    test('declares the TTS_SERVICE query', () {
      // With targetSdk 30+, Android package-visibility filtering hides the
      // text-to-speech engine unless it is declared here, and TextToSpeech
      // init then fails outright — voice can never work on Android 11+.
      // The flutter_tts plugin's own manifest is empty and cannot supply it.
      final queries = RegExp(
        r'<queries>(.*?)</queries>',
        dotAll: true,
      ).firstMatch(manifest);

      expect(queries, isNotNull, reason: '<queries> must exist');
      expect(
        queries!.group(1),
        contains('android.intent.action.TTS_SERVICE'),
        reason: 'without this, TTS init fails on every Android 11+ device',
      );
    });
  });
}
