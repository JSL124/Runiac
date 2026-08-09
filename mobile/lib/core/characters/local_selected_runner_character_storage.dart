import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'runner_character.dart';

/// Local, device-only persistence for the user's chosen guide character.
///
/// The selection is display-only personalization. It is stored locally and
/// keyed per signed-in uid (with an anonymous fallback key for users who have
/// no uid yet). It must never be written to Firestore and must never influence
/// XP, level, rank, streak, or leaderboard values.
abstract interface class LocalSelectedRunnerCharacterStorage {
  /// Reads the stored character for [uid], or `null` when nothing is stored.
  Future<RunnerCharacter?> readSelectedCharacter({required String? uid});

  /// Persists [character] for [uid].
  Future<void> writeSelectedCharacter({
    required String? uid,
    required RunnerCharacter character,
  });
}

/// Builds the per-user preference key. Falls back to an anonymous key when the
/// user has no uid (e.g. before an account is confirmed).
String selectedRunnerCharacterPreferenceKey(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anonymous' : uid;
  return 'selected_runner_character_$scope';
}

/// [SharedPreferences]-backed implementation.
///
/// Reads and writes are defensive: a missing platform plugin (common in pure
/// unit tests that do not call [SharedPreferences.setMockInitialValues]) is
/// treated as "no stored selection" rather than an error, matching the app's
/// tolerance for absent local personalization.
class SharedPreferencesSelectedRunnerCharacterStorage
    implements LocalSelectedRunnerCharacterStorage {
  const SharedPreferencesSelectedRunnerCharacterStorage();

  @override
  Future<RunnerCharacter?> readSelectedCharacter({required String? uid}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedId = preferences.getString(
        selectedRunnerCharacterPreferenceKey(uid),
      );
      return runnerCharacterFromId(storedId);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> writeSelectedCharacter({
    required String? uid,
    required RunnerCharacter character,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        selectedRunnerCharacterPreferenceKey(uid),
        character.id,
      );
    } on MissingPluginException {
      // Local personalization storage is optional; ignore when unavailable.
    }
  }
}

/// In-memory implementation for tests and previews.
class MemorySelectedRunnerCharacterStorage
    implements LocalSelectedRunnerCharacterStorage {
  MemorySelectedRunnerCharacterStorage();

  final Map<String, RunnerCharacter> _byKey = <String, RunnerCharacter>{};

  @override
  Future<RunnerCharacter?> readSelectedCharacter({required String? uid}) async {
    return _byKey[selectedRunnerCharacterPreferenceKey(uid)];
  }

  @override
  Future<void> writeSelectedCharacter({
    required String? uid,
    required RunnerCharacter character,
  }) async {
    _byKey[selectedRunnerCharacterPreferenceKey(uid)] = character;
  }
}
