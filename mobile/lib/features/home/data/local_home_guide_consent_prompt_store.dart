import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, device-only record of whether the one-time Home guide data-use
/// consent sheet has already been shown to a user.
///
/// This is a UI-nudge flag only: it decides whether to auto-present the consent
/// bottom sheet on first Home entry after onboarding. The authoritative consent
/// value lives server-side (see `HomeGuideConsentRepository`); this flag never
/// grants consent and never influences any backend-owned value.
abstract interface class HomeGuideConsentPromptStore {
  /// True when the consent sheet has already been shown for [uid].
  Future<bool> hasPrompted({required String? uid});

  /// Records that the consent sheet has been shown for [uid].
  Future<void> markPrompted({required String? uid});
}

/// Builds the per-user preference key. Falls back to an anonymous key when the
/// user has no uid (mirrors [selectedRunnerCharacterPreferenceKey]).
String homeGuideConsentPromptedPreferenceKey(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anonymous' : uid;
  return 'home_guide_consent_prompted_$scope';
}

/// [SharedPreferences]-backed implementation.
///
/// A missing platform plugin (common in pure unit tests) is treated as
/// "not yet prompted" rather than an error.
class SharedPreferencesHomeGuideConsentPromptStore
    implements HomeGuideConsentPromptStore {
  const SharedPreferencesHomeGuideConsentPromptStore();

  @override
  Future<bool> hasPrompted({required String? uid}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(homeGuideConsentPromptedPreferenceKey(uid)) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> markPrompted({required String? uid}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        homeGuideConsentPromptedPreferenceKey(uid),
        true,
      );
    } on MissingPluginException {
      // Optional local nudge flag; ignore when unavailable.
    }
  }
}

/// In-memory implementation for tests and previews.
class MemoryHomeGuideConsentPromptStore implements HomeGuideConsentPromptStore {
  MemoryHomeGuideConsentPromptStore();

  final Set<String> _prompted = <String>{};

  @override
  Future<bool> hasPrompted({required String? uid}) async =>
      _prompted.contains(homeGuideConsentPromptedPreferenceKey(uid));

  @override
  Future<void> markPrompted({required String? uid}) async {
    _prompted.add(homeGuideConsentPromptedPreferenceKey(uid));
  }
}
