import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../paywall/presentation/premium_gate.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_countdown.dart';
import '../domain/models/challenge_invitation_summary.dart';
import '../domain/repositories/challenge_repository.dart';
import 'challenge_friend_picker_screen.dart';
import 'challenge_lobby_screen.dart';
import 'widgets/challenge_badge_image.dart';
import 'widgets/challenge_widgets.dart';

/// Pending-invitations inbox. Tapping a row opens its detail; accepting there
/// routes to the lobby member view.
class ChallengeInvitationsScreen extends StatefulWidget {
  const ChallengeInvitationsScreen({
    required this.repository,
    required this.onBack,
    this.slotHeld = false,
    this.invitableFriendsLoader = noChallengeInvitableFriends,
    this.clock,
    super.key,
  });

  final ChallengeRepository repository;
  final VoidCallback onBack;
  final bool slotHeld;
  final ChallengeInvitableFriendsLoader invitableFriendsLoader;
  final DateTime Function()? clock;

  @override
  State<ChallengeInvitationsScreen> createState() =>
      _ChallengeInvitationsScreenState();
}

class _ChallengeInvitationsScreenState
    extends State<ChallengeInvitationsScreen> {
  List<ChallengeInvitationSummary>? _invitations;
  bool _loading = true;
  String? _error;
  StreamSubscription<List<ChallengeInvitationSummary>>? _subscription;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  /// Subscribes to the live pending-invitations view. Cancels any prior
  /// subscription first so retry/re-subscribe never leaks a listener.
  Future<void> _subscribe() async {
    unawaited(_subscription?.cancel());
    setState(() {
      _loading = _invitations == null;
      _error = null;
    });
    _subscription = widget.repository.watchInvitations().listen(
      (invitations) {
        if (!mounted) {
          return;
        }
        setState(() {
          _invitations = invitations;
          _loading = false;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        // Once we already have data, a transient stream error is ignored
        // rather than replacing a working list with an error state.
        if (_invitations != null) {
          return;
        }
        setState(() {
          _loading = false;
          _error = error is ChallengeFailure
              ? ChallengeCopy.failureMessage(error.reason)
              : ChallengeCopy.failureMessage('UNKNOWN');
        });
      },
    );
  }

  Future<void> _openDetail(ChallengeInvitationSummary invite) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChallengeInvitationDetailScreen(
          invitation: invite,
          repository: widget.repository,
          slotHeld: widget.slotHeld,
          invitableFriendsLoader: widget.invitableFriendsLoader,
          clock: widget.clock,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    // No manual refetch: the live subscription already reflects any change
    // (accept/decline) made from the detail screen.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: ChallengeCopy.invitationsTitle,
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
    final invitations = _invitations;
    if (invitations == null) {
      return ChallengeErrorState(
        message: _error ?? ChallengeCopy.exploreError,
        onRetry: _subscribe,
      );
    }
    if (invitations.isEmpty) {
      return const ChallengeEmptyState(
        title: ChallengeCopy.invitationsEmpty,
        icon: Icons.mail_outline,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: invitations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final invite = invitations[index];
        return _InvitationRow(
          invitation: invite,
          now: _now,
          onTap: () => _openDetail(invite),
        );
      },
    );
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({
    required this.invitation,
    required this.now,
    required this.onTap,
  });

  final ChallengeInvitationSummary invitation;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = ChallengeCountdown.remaining(
      now: now,
      scheduledEndsAt: invitation.expiresAt,
    );
    return RuniacTappableSurface(
      onTap: onTap,
      semanticLabel: 'Challenge invitation ${challengeTierTitle(invitation.tierId)}',
      borderRadius: BorderRadius.circular(18),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          ChallengeBadgeImage(tierId: invitation.tierId, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  challengeTierTitle(invitation.tierId),
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ChallengeCopy.expiresIn(ChallengeCountdown.formatHms(remaining)),
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: RuniacColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Detail for a single pending invitation: rules card + Accept/Decline.
class ChallengeInvitationDetailScreen extends StatefulWidget {
  const ChallengeInvitationDetailScreen({
    required this.invitation,
    required this.repository,
    required this.onBack,
    this.slotHeld = false,
    this.invitableFriendsLoader = noChallengeInvitableFriends,
    this.clock,
    super.key,
  });

  final ChallengeInvitationSummary invitation;
  final ChallengeRepository repository;
  final bool slotHeld;
  final ChallengeInvitableFriendsLoader invitableFriendsLoader;
  final DateTime Function()? clock;
  final VoidCallback onBack;

  @override
  State<ChallengeInvitationDetailScreen> createState() =>
      _ChallengeInvitationDetailScreenState();
}

class _ChallengeInvitationDetailScreenState
    extends State<ChallengeInvitationDetailScreen> {
  bool _busy = false;

  Future<void> _respond({required bool accept}) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.repository.respondToInvitation(
        inviteId: widget.invitation.inviteId,
        accept: accept,
      );
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      if (result.accepted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => ChallengeLobbyScreen(
              challengeId: result.challengeId,
              repository: widget.repository,
              onBack: () => Navigator.of(context).pop(),
              invitableFriendsLoader: widget.invitableFriendsLoader,
              clock: widget.clock,
            ),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    } on ChallengeFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      if (failure.reason == 'PREMIUM_REQUIRED') {
        // Premium-only tiers now require premium of invited members too, and
        // the invite path is deliberately not gated (that would tell the owner
        // which friends are not paying), so this is where a Basic recipient
        // first learns of it. Same treatment as tier detail: prefer the
        // paywall, fall back to copy when the sheet cannot show.
        if (!interceptWithPaywallIfBasic(context)) {
          _showError(ChallengeCopy.failureMessage(failure.reason));
        }
        return;
      }
      _showError(ChallengeCopy.failureMessage(failure.reason));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _showError(ChallengeCopy.failureMessage('UNKNOWN'));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invitation;
    final rules = invite.rules;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: challengeTierTitle(invite.tierId),
              onBack: widget.onBack,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ChallengeBadgeImage(tierId: invite.tierId, size: 108),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        challengeTierTitle(invite.tierId),
                        style: const TextStyle(
                          color: RuniacColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'A friend invited you to this challenge',
                        style: TextStyle(
                          color: RuniacColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (rules != null)
                      ChallengeRulesCard(
                        targetMeters: rules.targetMeters,
                        durationDays: rules.durationDays,
                        maxParticipants: rules.maxParticipants,
                        personalMinimumMeters: rules.personalMinimumMeters,
                      ),
                    const SizedBox(height: 20),
                    if (widget.slotHeld) ...[
                      const Text(
                        ChallengeCopy.alreadyHaveChallengeInProgress,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: RuniacColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: RuniacButtonStyles.primary(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: widget.slotHeld || _busy
                            ? null
                            : () => _respond(accept: true),
                        child: const Text(ChallengeCopy.accept),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _respond(accept: false),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(ChallengeCopy.decline),
                      ),
                    ),
                    if (widget.slotHeld) ...[
                      const SizedBox(height: 4),
                      const Center(
                        child: Text(
                          ChallengeCopy.viewCurrentChallenge,
                          style: TextStyle(
                            color: RuniacColors.primaryBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
