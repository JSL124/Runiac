import 'package:flutter/material.dart';

import '../../../core/characters/runner_character.dart';
import 'character_selection_screen.dart';

/// Inserts the guide-character selection step between profile setup and the
/// onboarding question flow.
///
/// When [active] is true and the [store] has no selection yet, this shows the
/// [CharacterSelectionScreen]. Once a character is confirmed (or when a stored
/// choice was already restored into [store]), the gate transparently renders
/// [child] — the onboarding flow — so existing onboarding behavior is intact.
///
/// The selection is display-only personalization. [onCharacterConfirmed] is
/// responsible only for local persistence; nothing here writes to Firestore or
/// affects XP, level, rank, streak, or leaderboard values.
class RuniacCharacterSelectionGate extends StatelessWidget {
  const RuniacCharacterSelectionGate({
    required this.active,
    required this.store,
    required this.onCharacterConfirmed,
    required this.child,
    super.key,
  });

  final bool active;
  final SelectedRunnerCharacterStore store;
  final ValueChanged<RunnerCharacter> onCharacterConfirmed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return child;
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.hasSelection) {
          return child;
        }
        return CharacterSelectionScreen(
          onConfirm: (character) {
            onCharacterConfirmed(character);
            store.select(character);
          },
        );
      },
    );
  }
}
