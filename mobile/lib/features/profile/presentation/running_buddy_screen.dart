import 'package:flutter/material.dart';

import '../../../core/characters/local_selected_runner_character_storage.dart';
import '../../../core/characters/runner_character.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_success_check_overlay.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../../onboarding/presentation/character_selection_screen.dart';

/// Account → "Running buddy": lets an existing user swap the guide character
/// they picked during onboarding.
///
/// The buddy is display-only, device-local personalization, so confirming here
/// updates the session store and the local preference only. Nothing is written
/// to Firestore, and XP, level, rank, streak, and leaderboard values are
/// untouched.
///
/// Premium gating is inherited from [CharacterSelectionScreen]: buddies the
/// Platform Administrator listed in `config/characterAccess` show a lock for a
/// Basic runner and open the paywall instead of being selected, exactly as they
/// do during onboarding. A buddy the runner already owns stays selectable, so a
/// pick made before a tier change is never taken away.
class RunningBuddyScreen extends StatelessWidget {
  const RunningBuddyScreen({
    required this.authRepository,
    this.characterStorage =
        const SharedPreferencesSelectedRunnerCharacterStorage(),
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final LocalSelectedRunnerCharacterStorage characterStorage;

  Future<void> _confirm(BuildContext context, RunnerCharacter character) async {
    final navigator = Navigator.of(context);
    // Update the in-session store first so every surface showing the buddy
    // (home stage map, run summary, paywall art) repaints immediately, then
    // persist for the next launch.
    SelectedRunnerCharacterScope.maybeOf(context)?.select(character);
    await characterStorage.writeSelectedCharacter(
      uid: authRepository.currentUser?.uid,
      character: character,
    );
    if (!context.mounted) {
      return;
    }
    await showRuniacSuccessCheckOverlay(
      context,
      message: '${character.displayName} is your buddy now.',
    );
    if (!navigator.mounted) {
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = SelectedRunnerCharacterScope.maybeOf(context);
    return CharacterSelectionScreen(
      initialSelection: store?.selected,
      header: RuniacBackHeader(
        title: 'Running buddy',
        tooltip: 'Back to Account',
        onBack: () => Navigator.of(context).pop(),
      ),
      title: 'Switch your running buddy',
      subtitle:
          'Your buddy cheers you on around the app. Change guides whenever '
          'you like — this is just for fun and never changes your XP, level, '
          'or rank.',
      confirmLabelBuilder: (character) =>
          'Run with ${character.displayName} from now on',
      onConfirm: (character) => _confirm(context, character),
    );
  }
}
