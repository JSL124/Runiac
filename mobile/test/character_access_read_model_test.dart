import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/paywall/domain/models/character_access_read_model.dart';

void main() {
  group('CharacterAccessReadModel.fromMap', () {
    test('defaults gate Cap and Ivy', () {
      expect(
        CharacterAccessReadModel.defaults.premiumOnlyCharacters,
        {RunnerCharacter.cap, RunnerCharacter.purple},
      );
      expect(
        CharacterAccessReadModel.defaults.isPremiumOnly(RunnerCharacter.blue),
        isFalse,
      );
    });

    test('a null document falls back to defaults', () {
      final model = CharacterAccessReadModel.fromMap(null);
      expect(model, CharacterAccessReadModel.defaults);
    });

    test('a missing/malformed list falls back to defaults', () {
      expect(
        CharacterAccessReadModel.fromMap(<String, Object?>{}),
        CharacterAccessReadModel.defaults,
      );
      expect(
        CharacterAccessReadModel.fromMap(<String, Object?>{
          'premiumOnlyCharacters': 'cap',
        }),
        CharacterAccessReadModel.defaults,
      );
    });

    test('a present list REPLACES defaults, skipping unknown ids', () {
      final model = CharacterAccessReadModel.fromMap(<String, Object?>{
        'premiumOnlyCharacters': ['purple', 'not-a-character', 42],
      });
      expect(model.premiumOnlyCharacters, {RunnerCharacter.purple});
      expect(model.isPremiumOnly(RunnerCharacter.cap), isFalse);
      expect(model.isPremiumOnly(RunnerCharacter.purple), isTrue);
    });

    test('a present-but-empty list opens every character', () {
      final model = CharacterAccessReadModel.fromMap(<String, Object?>{
        'premiumOnlyCharacters': <Object?>[],
      });
      expect(model.premiumOnlyCharacters, isEmpty);
      for (final character in RunnerCharacter.values) {
        expect(model.isPremiumOnly(character), isFalse);
      }
    });
  });
}
