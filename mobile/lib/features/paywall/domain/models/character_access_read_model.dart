// Display-only view of the backend-owned `config/characterAccess` document:
// which guide characters the Platform Administrator has gated behind Premium.
// The character picker locks these for Basic runners. The character is
// cosmetic, device-local personalization — this model never affects XP, level,
// rank, streak, or leaderboard values, and the lock is presentation only.

import 'package:flutter/foundation.dart';

import '../../../../core/characters/runner_character.dart';

/// Premium-gated characters from `config/characterAccess.premiumOnlyCharacters`.
@immutable
class CharacterAccessReadModel {
  const CharacterAccessReadModel({this.premiumOnlyCharacters = _defaultSet});

  static const defaults = CharacterAccessReadModel();

  /// Shipped defaults: Cap and Ivy are Premium; Bolt and Mila are open. Mirrors
  /// functions `DEFAULT_CHARACTER_ACCESS_CONFIG` and the admin console.
  static const _defaultSet = <RunnerCharacter>{
    RunnerCharacter.cap,
    RunnerCharacter.purple,
  };

  /// The characters whose selection requires a Premium subscription.
  final Set<RunnerCharacter> premiumOnlyCharacters;

  bool isPremiumOnly(RunnerCharacter character) =>
      premiumOnlyCharacters.contains(character);

  /// Maps the trusted raw document. A missing document or a malformed
  /// `premiumOnlyCharacters` field resolves to [defaults] (the never-configured
  /// state), matching the backend loader. A present-but-empty list is a
  /// legitimate "every character open" state and is honoured as such — unknown
  /// ids are skipped rather than failing the whole parse.
  factory CharacterAccessReadModel.fromMap(Map<String, Object?>? data) {
    final raw = data?['premiumOnlyCharacters'];
    if (raw is! List) {
      return defaults;
    }
    final characters = <RunnerCharacter>{};
    for (final entry in raw) {
      final character = runnerCharacterFromId(entry is String ? entry : null);
      if (character != null) {
        characters.add(character);
      }
    }
    return CharacterAccessReadModel(
      premiumOnlyCharacters: Set.unmodifiable(characters),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharacterAccessReadModel &&
        setEquals(other.premiumOnlyCharacters, premiumOnlyCharacters);
  }

  @override
  int get hashCode => Object.hashAll(premiumOnlyCharacters);
}
