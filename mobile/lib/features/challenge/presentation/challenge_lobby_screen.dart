import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../../core/widgets/runiac_level_profile_badge.dart';
import '../../paywall/presentation/premium_paywall_sheet.dart';
import '../../profile/presentation/widgets/runner_profile_avatar_link.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_countdown.dart';
import '../domain/models/active_challenge.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_invitation_summary.dart';
import '../domain/models/challenge_participant_row.dart';
import '../domain/repositories/challenge_repository.dart';
import 'challenge_friend_picker_screen.dart';
import 'challenge_progress_screen.dart';
import 'widgets/challenge_badge_image.dart';
import 'widgets/challenge_premium_lapse_banner.dart';
import 'widgets/challenge_widgets.dart';

/// The RECRUITING lobby: roster, closes-in countdown, owner start/cancel/invite
/// or member leave. Solo vs group is resolved at start via a confirm sheet.
///
/// [pendingInvitations] is an owner-facing seam for Pending/Declined chips.
/// `getActiveChallenge` does not surface the owner's sent invitations, so it
/// defaults to empty until such a read exists; accepted members always render
/// from the trusted participant roster.
class ChallengeLobbyScreen extends StatefulWidget {
  const ChallengeLobbyScreen({
    required this.challengeId,
    required this.repository,
    required this.onBack,
    this.invitableFriendsLoader = noChallengeInvitableFriends,
    this.pendingInvitations = const <ChallengeInvitationSummary>[],
    this.clock,
    this.ticker,
    super.key,
  });

  final String challengeId;
  final ChallengeRepository repository;
  final VoidCallback onBack;
  final ChallengeInvitableFriendsLoader invitableFriendsLoader;
  final List<ChallengeInvitationSummary> pendingInvitations;
  final DateTime Function()? clock;
  final ChallengeTicker? ticker;

  @override
  State<ChallengeLobbyScreen> createState() => _ChallengeLobbyScreenState();
}

class _ChallengeLobbyScreenState extends State<ChallengeLobbyScreen> {
  ActiveChallenge? _challenge;
  ChallengeCountdownController? _countdown;
  DateTime? _countdownEndsAt;
  bool _loading = true;
  bool _expired = false;
  bool _busy = false;
  String? _error;
  StreamSubscription<ActiveChallenge?>? _subscription;

  /// Guards the started-remotely navigation so an emission that arrives after
  /// this device already pushed the progress screen (via [_confirmStart])
  /// never pushes a second time.
  bool _navigatedToProgress = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _countdown?.dispose();
    super.dispose();
  }

  /// Subscribes to the live active-challenge view. Cancels any prior
  /// subscription first so retry/re-subscribe never leaks a listener.
  Future<void> _subscribe() async {
    unawaited(_subscription?.cancel());
    setState(() {
      _loading = _challenge == null && !_expired;
      _error = null;
    });
    _subscription = widget.repository.watchActiveChallenge().listen(
      _handleChallenge,
      onError: _handleStreamError,
    );
  }

  void _handleChallenge(ActiveChallenge? challenge) {
    if (!mounted) {
      return;
    }
    if (challenge == null ||
        challenge.challengeId != widget.challengeId ||
        challenge.status == ChallengeInstanceStatus.expired ||
        challenge.status.isTerminal) {
      _countdown?.dispose();
      _countdown = null;
      setState(() {
        _challenge = null;
        _loading = false;
        _expired = true;
        _error = null;
      });
      return;
    }
    if (challenge.status == ChallengeInstanceStatus.active ||
        challenge.status == ChallengeInstanceStatus.settling) {
      // The owner started the challenge (possibly from another device, or
      // this device's own confirm already pushed) — move to Progress exactly
      // once.
      if (!_navigatedToProgress) {
        _navigatedToProgress = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => ChallengeProgressScreen(
              challengeId: widget.challengeId,
              repository: widget.repository,
              clock: widget.clock,
              ticker: widget.ticker,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
      return;
    }
    // RECRUITING: live roster/status/headcount update. The countdown
    // controller is recreated only when the deadline actually changes, so a
    // roster-only emission never restarts its ticker.
    final scheduledEndsAt =
        DateTime.fromMillisecondsSinceEpoch(challenge.lobbyExpiresAtMs);
    if (_countdown == null || _countdownEndsAt != scheduledEndsAt) {
      _countdown?.dispose();
      _countdown = ChallengeCountdownController(
        clock: widget.clock ?? DateTime.now,
        ticker: widget.ticker,
        scheduledEndsAt: scheduledEndsAt,
      );
      _countdownEndsAt = scheduledEndsAt;
    }
    setState(() {
      _challenge = challenge;
      _loading = false;
      _expired = false;
      _error = null;
    });
  }

  void _handleStreamError(Object error) {
    if (!mounted) {
      return;
    }
    // Once we already have data, a transient stream error is ignored rather
    // than replacing a working lobby view with an error state.
    if (_challenge != null) {
      return;
    }
    setState(() {
      _loading = false;
      _error = error is ChallengeFailure
          ? ChallengeCopy.failureMessage(error.reason)
          : ChallengeCopy.failureMessage('UNKNOWN');
    });
  }

  List<ChallengeParticipantRow> get _roster {
    final challenge = _challenge;
    if (challenge == null) {
      return const <ChallengeParticipantRow>[];
    }
    final owner = <ChallengeParticipantRow>[];
    final others = <ChallengeParticipantRow>[];
    for (final row in challenge.participants) {
      if (row.role == ChallengeParticipantRole.owner) {
        owner.add(row);
      } else {
        others.add(row);
      }
    }
    return <ChallengeParticipantRow>[...owner, ...others];
  }

  int get _acceptedInviteeCount => _roster
      .where((row) => row.role == ChallengeParticipantRole.member && !row.hasLeft)
      .length;

  int get _pendingInviteeCount => widget.pendingInvitations
      .where((invite) => invite.status == ChallengeInvitationStatus.pending)
      .length;

  int get _inviteCap => _challenge?.rules.maxInvitedFriends ?? 0;

  /// People currently in the lobby: the owner (always present) plus every
  /// accepted invitee who has not left. Pending invites are not counted.
  int get _presentHeadcount => 1 + _acceptedInviteeCount;

  /// Maximum runners the challenge allows: the owner plus the invite cap.
  int get _lobbyCapacity => 1 + _inviteCap;

  bool get _canInvite =>
      (_acceptedInviteeCount + _pendingInviteeCount) < _inviteCap;

  bool get _isSoloStart => _acceptedInviteeCount == 0;

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on ChallengeFailure catch (failure) {
      if (mounted) {
        _showError(ChallengeCopy.failureMessage(failure.reason));
      }
    } catch (_) {
      if (mounted) {
        _showError(ChallengeCopy.failureMessage('UNKNOWN'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openInvitePicker() async {
    final friends = await widget.invitableFriendsLoader();
    if (!mounted) {
      return;
    }
    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (context) => ChallengeFriendPickerScreen(
          friends: friends,
          cap: _inviteCap,
          alreadyInvited: _acceptedInviteeCount + _pendingInviteeCount,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (!mounted || selected == null || selected.isEmpty) {
      return;
    }
    await _runAction(() async {
      await widget.repository
          .invite(challengeId: widget.challengeId, uids: selected);
      // No manual refetch: the live subscription already reflects the
      // updated pending-invite state once the write lands.
    });
  }

  Future<void> _confirmStart() async {
    final solo = _isSoloStart;
    final message = solo
        ? ChallengeCopy.startSoloConfirm
        : ChallengeCopy.startGroupConfirm(_roster.length);
    final confirmed = await _showConfirmSheet(
      title: ChallengeCopy.startChallenge,
      message: message,
      confirmLabel: ChallengeCopy.startChallenge,
    );
    if (confirmed != true) {
      return;
    }
    await _runAction(() async {
      await widget.repository.start(challengeId: widget.challengeId);
      if (!mounted || _navigatedToProgress) {
        return;
      }
      // Set the guard before pushing so a live emission racing this success
      // path (the stream also observes the now-ACTIVE status) never pushes a
      // second time.
      _navigatedToProgress = true;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => ChallengeProgressScreen(
            challengeId: widget.challengeId,
            repository: widget.repository,
            clock: widget.clock,
            ticker: widget.ticker,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    });
  }

  Future<void> _confirmCancel() async {
    final confirmed = await _showConfirmSheet(
      title: ChallengeCopy.cancelChallenge,
      message: ChallengeCopy.cancelChallengeConfirm,
      confirmLabel: ChallengeCopy.cancelChallenge,
      destructive: true,
    );
    if (confirmed != true) {
      return;
    }
    await _runAction(() async {
      await widget.repository.cancelLobby(challengeId: widget.challengeId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _leaveLobby() async {
    final confirmed = await _showConfirmSheet(
      title: ChallengeCopy.leaveLobby,
      message: 'Leave this lobby? You can be invited again later.',
      confirmLabel: ChallengeCopy.leaveLobby,
      destructive: true,
    );
    if (confirmed != true) {
      return;
    }
    await _runAction(() async {
      await widget.repository.withdraw(challengeId: widget.challengeId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<bool?> _showConfirmSheet({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: RuniacColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: RuniacButtonStyles.primary(
                      tone: destructive
                          ? RuniacButtonTone.orange
                          : RuniacButtonTone.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(confirmLabel),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: _challenge == null
                  ? ChallengeCopy.challengeTitle
                  : challengeTierTitle(_challenge!.tierId),
              onBack: widget.onBack,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ChallengeLoadingState();
    }
    if (_expired) {
      return const ChallengeEmptyState(
        title: ChallengeCopy.lobbyExpiredTitle,
        icon: Icons.hourglass_disabled_outlined,
      );
    }
    final challenge = _challenge;
    if (challenge == null) {
      return ChallengeErrorState(
        message: _error ?? ChallengeCopy.exploreError,
        onRetry: _subscribe,
      );
    }
    return _buildLobby(challenge);
  }

  Widget _buildLobby(ActiveChallenge challenge) {
    final isOwner = challenge.isCurrentUserOwner;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // A lapse inside a still-recruiting lobby is the same 24h window, and
        // for an owner the stakes are higher: with no eligible member to
        // inherit it, the lobby is cancelled rather than handed over.
        ChallengePremiumLapseBanner(
          hold: challenge.premiumHold,
          onUpgrade: () => PremiumPaywallSheet.show(context),
        ),
        Row(
          children: [
            ChallengeBadgeImage(tierId: challenge.tierId, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challengeTierTitle(challenge.tierId),
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _ClosesIn(controller: _countdown),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CapacityLine(
          present: _presentHeadcount,
          capacity: _lobbyCapacity,
        ),
        const SizedBox(height: 10),
        ..._roster.map(_rosterTile),
        ...widget.pendingInvitations.map(_invitationTile),
        const SizedBox(height: 20),
        if (isOwner) ...[
          OutlinedButton.icon(
            onPressed: _busy || !_canInvite ? null : _openInvitePicker,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text(ChallengeCopy.inviteFriends),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: RuniacButtonStyles.primary(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: _busy ? null : _confirmStart,
              child: const Text(ChallengeCopy.startChallenge),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : _confirmCancel,
            style: TextButton.styleFrom(
              foregroundColor: RuniacColors.errorRed,
            ),
            child: const Text(ChallengeCopy.cancelChallenge),
          ),
        ] else ...[
          const Text(
            ChallengeCopy.waitingForOwner,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _busy ? null : _leaveLobby,
              style: OutlinedButton.styleFrom(
                foregroundColor: RuniacColors.errorRed,
                side: const BorderSide(color: RuniacColors.errorRed),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(ChallengeCopy.leaveLobby),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rosterTile(ChallengeParticipantRow row) {
    final isOwner = row.role == ChallengeParticipantRole.owner;
    // "You" is a viewer-relative marker: only the current user sees it on their
    // own row. The owner reads "You · Owner" for themselves and a plain "Owner"
    // to everyone else; a non-owner current user reads "You".
    final String? subtitle = isOwner
        ? (row.isCurrentUser
            ? ChallengeCopy.ownerSelfLabel
            : ChallengeCopy.ownerLabel)
        : (row.isCurrentUser ? ChallengeCopy.youLabel : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // `explicitChildNodes: true` keeps the avatar's nested
      // `RunnerProfileAvatarLink` button semantics from merging upward into
      // whatever ancestor node happens to be the nearest semantics boundary
      // (this row has none of its own otherwise), which would otherwise fold
      // its "View <name> profile" label into an unrelated combined node.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: ChallengeCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              _rosterBadge(
                initials: row.avatarInitialsSnapshot,
                levelLabel: row.levelLabelSnapshot,
                uid: row.uid,
                displayName: row.displayNameSnapshot,
                photoUrl: row.avatarUrlSnapshot,
                levelProgressPercent: row.levelProgressPercentSnapshot,
                enabled: !row.isCurrentUser,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.displayNameSnapshot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: RuniacColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isOwner) ...[
                const SizedBox(width: 8),
                row.hasLeft
                    ? const ChallengeStatusChip(
                        label: ChallengeCopy.leftTheChallenge,
                        color: RuniacColors.textSecondary,
                      )
                    : const ChallengeStatusChip(
                        label: ChallengeCopy.chipAccepted,
                        color: RuniacColors.successGreen,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _invitationTile(ChallengeInvitationSummary invite) {
    final declined = invite.status == ChallengeInvitationStatus.declined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ChallengeCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            _rosterBadge(initials: '…'),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Invited runner',
                style: TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ChallengeStatusChip(
              label: declined
                  ? ChallengeCopy.chipDeclined
                  : ChallengeCopy.chipPending,
              color: RuniacColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Same profile-circle + XP-ring + level-pill badge Friends and the invite
/// picker use, rendered with the app-wide blue profile disc so every roster
/// avatar matches how a runner's profile reads elsewhere. [levelLabel] is the
/// backend-owned level snapshot read back verbatim; an empty label falls back
/// to the display-only 'Lv.0' placeholder Friends uses.
/// [levelProgressPercent] is the backend-owned 0..100 progress resolved beside
/// that label, converted here into the ring's 0.0..1.0 — the one arithmetic
/// step, the same one Friends and Feed rows perform. It defaults to 0 (an
/// empty ring) for the pending-invitation tile, whose runner is anonymous and
/// therefore carries no level at all.
///
/// Wrapped in [RunnerProfileAvatarLink] so tapping another runner's badge
/// opens their public profile. [uid]/[displayName] default to empty, which
/// makes the link inert (`ExcludeSemantics`-only) — used by the
/// pending-invitation tile, where the invited runner is anonymous by design.
/// [enabled] additionally disables the link for the current user's own row.
Widget _rosterBadge({
  required String initials,
  String levelLabel = '',
  String uid = '',
  String displayName = '',
  String photoUrl = '',
  int levelProgressPercent = 0,
  bool enabled = true,
}) {
  return RunnerProfileAvatarLink(
    uid: uid,
    displayName: displayName,
    avatarInitials: initials,
    avatarUrl: photoUrl,
    levelBadgeLabel: levelLabel,
    enabled: enabled,
    child: ExcludeSemantics(
      child: RuniacLevelProfileBadge.row(
        initials: initials,
        levelLabel: levelLabel.trim().isEmpty ? 'Lv.0' : levelLabel,
        progressFraction: (levelProgressPercent / 100).clamp(0.0, 1.0),
        photoUrl: photoUrl,
      ),
    ),
  );
}

class _ClosesIn extends StatelessWidget {
  const _ClosesIn({required this.controller});

  final ChallengeCountdownController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final label = ChallengeCountdown.formatHms(controller.value.remaining);
        return Text(
          ChallengeCopy.lobbyClosesIn(label),
          style: const TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

class _CapacityLine extends StatelessWidget {
  const _CapacityLine({required this.present, required this.capacity});

  final int present;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    return Text(
      ChallengeCopy.lobbyHeadcount(present, capacity),
      style: const TextStyle(
        color: RuniacColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
