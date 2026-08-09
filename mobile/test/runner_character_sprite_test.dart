import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/core/widgets/runner_character_sprite.dart';

void main() {
  testWidgets('every animated guide uses the Bolt display footprint', (
    WidgetTester tester,
  ) async {
    for (final character in RunnerCharacter.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RunnerCharacterSprite(
              character: character,
              assetPath: character.idleAnimationAssetPath,
              width: 193,
            ),
          ),
        ),
      );

      final spriteSize = tester.getSize(find.byType(RunnerCharacterSprite));
      expect(spriteSize.height, 289);
      expect(
        spriteSize.width,
        RunnerCharacterSprite.layoutWidthFor(
          assetPath: character.idleAnimationAssetPath,
          width: 193,
        ),
      );
      expect(
        tester.getRect(find.byType(ClipRect)),
        tester.getRect(find.byType(RunnerCharacterSprite)),
        reason: '${character.displayName} should clip to the Bolt footprint',
      );
      expect(
        tester.getSize(find.byType(Image)).aspectRatio,
        closeTo(character == RunnerCharacter.blue ? 193 / 289 : 1, 0.0001),
        reason: '${character.displayName} should preserve its source ratio',
      );
    }
  });

  testWidgets('every runner asset preserves its original aspect ratio', (
    WidgetTester tester,
  ) async {
    Future<void> expectRatio({
      required RunnerCharacter character,
      required String assetPath,
      required double expectedRatio,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RunnerCharacterSprite(
              character: character,
              assetPath: assetPath,
              width: 193,
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(Image)).aspectRatio,
        closeTo(expectedRatio, 0.0001),
        reason: '$assetPath should preserve its source ratio',
      );
    }

    for (final character in RunnerCharacter.values) {
      await expectRatio(
        character: character,
        assetPath: character.idleAnimationAssetPath,
        expectedRatio: character == RunnerCharacter.blue ? 193 / 289 : 1,
      );

      for (final facing in RunnerCharacterFacing.values) {
        await expectRatio(
          character: character,
          assetPath: character.assetPath(facing),
          expectedRatio: 350 / 280,
        );
      }

      if (character.hasRunAnimation) {
        for (final facing in const [
          RunnerCharacterFacing.left,
          RunnerCharacterFacing.right,
        ]) {
          await expectRatio(
            character: character,
            assetPath: character.runAnimationAssetPath(facing)!,
            expectedRatio: character == RunnerCharacter.blue ? 240 / 312 : 1,
          );
        }
      }
    }
  });
}
