import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Central seam for haptic feedback across the app.
///
/// Feature code should trigger haptics through this abstraction (reached via
/// `RuniacHapticsScope`) instead of calling `HapticFeedback` directly, so a
/// single place governs whether haptics are enabled (mirroring the user's
/// Settings > App comfort > Haptic feedback preference) and so tests can
/// substitute a recording fake.
abstract class RuniacHaptics {
  /// A subtle "selection changed" haptic (e.g. toggles, segmented controls).
  void selection();

  /// A light impact haptic (e.g. minor taps and confirmations).
  void impactLight();

  /// A medium impact haptic (e.g. standard confirmations).
  void impactMedium();

  /// A heavy impact haptic (e.g. significant milestones).
  void impactHeavy();

  /// An error haptic (e.g. failed actions, invalid input).
  void error();

  /// Enables or disables all haptic feedback dispatched through this
  /// instance.
  void setEnabled(bool enabled);
}

/// Channel that plays Runiac's haptics through `RuniacHaptics.kt` on Android.
///
/// Flutter's own `HapticFeedback` maps every level onto
/// `View.performHapticFeedback` touch-tick constants on Android, which are the
/// same class of effect the software keyboard uses: barely perceptible on an
/// LRA device and frequently a no-op on rotational (ERM) motors. Driving the
/// platform vibrator instead is what makes the levels distinguishable on real
/// Android hardware. iOS keeps using the framework path, where the levels
/// already map onto the distinct `UIFeedbackGenerator` classes.
@visibleForTesting
const MethodChannel runiacAndroidHapticsChannel = MethodChannel(
  'runiac/haptics',
);

/// Method invoked on [runiacAndroidHapticsChannel]; the argument is one of the
/// wire names below.
@visibleForTesting
const String runiacAndroidHapticsPlayMethod = 'play';

/// Wire names accepted by the Android channel. These must stay in sync with
/// `RuniacHapticKind` in `RuniacHaptics.kt`.
@visibleForTesting
const String runiacAndroidHapticSelection = 'selection';

/// See [runiacAndroidHapticSelection].
@visibleForTesting
const String runiacAndroidHapticLightImpact = 'lightImpact';

/// See [runiacAndroidHapticSelection].
@visibleForTesting
const String runiacAndroidHapticMediumImpact = 'mediumImpact';

/// See [runiacAndroidHapticSelection].
@visibleForTesting
const String runiacAndroidHapticHeavyImpact = 'heavyImpact';

/// See [runiacAndroidHapticSelection].
@visibleForTesting
const String runiacAndroidHapticError = 'error';

/// [RuniacHaptics] implementation backed by the platform.
///
/// On Android every level is played through [runiacAndroidHapticsChannel]; on
/// every other platform it goes through the framework's [HapticFeedback]
/// channel.
///
/// Haptics are a non-critical comfort feature, so every call here is
/// fail-safe: platform channel failures (missing plugin implementation,
/// unsupported platform, no binary messenger registered in a test) are
/// swallowed rather than allowed to propagate to the caller.
class SystemRuniacHaptics implements RuniacHaptics {
  // The public parameter is `enabled` while the backing field is private
  // (`_enabled`) behind a getter/setter, so an initializing formal cannot apply.
  // ignore: prefer_initializing_formals
  SystemRuniacHaptics({bool enabled = true}) : _enabled = enabled;

  bool _enabled;

  /// Whether haptic feedback is currently enabled.
  bool get enabled => _enabled;

  /// Whether this instance routes through the Android vibrator channel.
  ///
  /// Read per call (rather than cached) so a test can flip
  /// `debugDefaultTargetPlatformOverride` between platforms.
  bool get _usesAndroidChannel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  @override
  void selection() {
    _dispatch(runiacAndroidHapticSelection, HapticFeedback.selectionClick);
  }

  @override
  void impactLight() {
    _dispatch(runiacAndroidHapticLightImpact, HapticFeedback.lightImpact);
  }

  @override
  void impactMedium() {
    _dispatch(runiacAndroidHapticMediumImpact, HapticFeedback.mediumImpact);
  }

  @override
  void impactHeavy() {
    _dispatch(runiacAndroidHapticHeavyImpact, HapticFeedback.heavyImpact);
  }

  @override
  void error() {
    _dispatch(runiacAndroidHapticError, HapticFeedback.vibrate);
  }

  /// Plays [androidKind] on Android and [frameworkFallback] elsewhere.
  ///
  /// The fallback is also used when Android reports the channel as
  /// unimplemented, so an engine without the native handler registered keeps
  /// the previous (weak but present) behaviour instead of going silent.
  void _dispatch(
    String androidKind,
    Future<void> Function() frameworkFallback,
  ) {
    if (!_enabled) {
      return;
    }
    if (!_usesAndroidChannel) {
      _fire(frameworkFallback);
      return;
    }
    _fire(() async {
      try {
        await runiacAndroidHapticsChannel.invokeMethod<void>(
          runiacAndroidHapticsPlayMethod,
          androidKind,
        );
      } on MissingPluginException {
        await frameworkFallback();
      }
    });
  }

  /// Fires a platform haptic call, guarding both the synchronous call site
  /// and the returned future so a platform failure never surfaces to the
  /// caller.
  void _fire(Future<void> Function() call) {
    try {
      unawaited(call().catchError((_) {}));
    } catch (_) {
      // Never let a haptic failure affect the calling feature flow.
    }
  }
}
