import 'package:flutter/foundation.dart';

import '../../../core/characters/runner_character.dart';
import '../../profile/presentation/current_session_user_account.dart';
import '../domain/models/character_access_read_model.dart';
import 'current_session_character_access.dart';
import 'current_session_paywall_config.dart';

/// Drops a premium-only guide character back to a free one when the runner is
/// no longer Premium.
///
/// The picker gates *selection*, but the choice then lives in device-local
/// preferences indefinitely, so a runner who picked Cap while subscribed kept
/// Cap after the subscription lapsed. This closes that window: the trusted
/// `users/{uid}` account state is already watched live by
/// [CurrentSessionUserAccount], so an expiry (or an admin-side downgrade)
/// reverts the buddy with no restart and no re-login.
///
/// The character is cosmetic, device-local personalization. This class only
/// rewrites that local preference — it never reads, computes, or writes XP,
/// level, rank, streak, subscription privilege, or leaderboard values, and it
/// never decides entitlement itself: it relays the trusted account tier and the
/// administrator's published character list.
///
/// Deliberately fails OPEN, the opposite of the selection-time gate. Reverting
/// overwrites a stored preference the runner cannot get back without
/// re-picking, so every input must be *confirmed* before it fires:
///
/// - the account snapshot has arrived and says the runner is not Premium (an
///   unresolved account would strip a Premium runner's buddy on every cold
///   start),
/// - `config/characterAccess` has actually loaded (its pre-load defaults would
///   strip a buddy the administrator had opened to everyone), and
/// - `config/paywall` has loaded and its `enabled` kill switch is on (with the
///   paywall switched off, every character is open to everyone).
class PremiumCharacterEntitlement {
  PremiumCharacterEntitlement({
    required this.account,
    required this.paywallConfig,
    required this.characterAccess,
    required this.selectedCharacter,
    required this.onReverted,
  });

  /// Trusted `users/{uid}` tier, watched live.
  final CurrentSessionUserAccount account;

  /// Supplies the `enabled` kill switch.
  final CurrentSessionPaywallConfig paywallConfig;

  /// The administrator's published premium-character list.
  final CurrentSessionCharacterAccess characterAccess;

  /// The session-wide guide selection this reverts.
  final SelectedRunnerCharacterStore selectedCharacter;

  /// Called with the free character the guide was reset to, so the caller can
  /// persist it over the stored premium-only choice.
  final ValueChanged<RunnerCharacter> onReverted;

  var _started = false;

  /// Begins watching. Safe to call once; the first check runs immediately so a
  /// selection restored from storage is vetted as soon as the tier is known.
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    account.addListener(_enforce);
    paywallConfig.addListener(_enforce);
    characterAccess.addListener(_enforce);
    selectedCharacter.addListener(_enforce);
    _enforce();
  }

  void dispose() {
    if (!_started) {
      return;
    }
    _started = false;
    account.removeListener(_enforce);
    paywallConfig.removeListener(_enforce);
    characterAccess.removeListener(_enforce);
    selectedCharacter.removeListener(_enforce);
  }

  void _enforce() {
    final selected = selectedCharacter.selected;
    if (selected == null) {
      return;
    }

    final trustedAccount = account.account;
    // Unresolved, or Premium: there is nothing to take away.
    if (trustedAccount == null || trustedAccount.isPremium) {
      return;
    }

    // Only a confirmed Basic runner holding a selection pays for these two
    // config reads; a Premium runner never triggers them. Both stores are
    // one-shot and session-cached, and each completion notifies us back here.
    paywallConfig.ensureLoaded();
    characterAccess.ensureLoaded();
    if (!paywallConfig.hasResolved || !characterAccess.hasResolved) {
      return;
    }
    if (!paywallConfig.config.enabled) {
      return;
    }

    final access = characterAccess.characterAccess;
    if (!access.isPremiumOnly(selected)) {
      return;
    }

    final fallback = _freeCharacter(access);
    if (fallback == selected) {
      return;
    }
    // Session store first so every surface showing the guide repaints, then the
    // device-local preference so the next launch agrees. The re-entrant
    // notification this triggers settles on the first check above.
    selectedCharacter.select(fallback);
    onReverted(fallback);
  }

  /// Bolt is the app-wide default guide, so it is the natural landing spot.
  /// Falling through to the first open character keeps this correct if an
  /// administrator ever puts Bolt behind Premium too.
  RunnerCharacter _freeCharacter(CharacterAccessReadModel access) {
    if (!access.isPremiumOnly(RunnerCharacter.blue)) {
      return RunnerCharacter.blue;
    }
    return RunnerCharacter.values.firstWhere(
      (character) => !access.isPremiumOnly(character),
      // Every character gated is a nonsense config; leaving the runner on the
      // default beats leaving them with no guide at all.
      orElse: () => RunnerCharacter.blue,
    );
  }
}
