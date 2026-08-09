import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../paywall/presentation/premium_paywall_sheet.dart';
import '../../profile/presentation/widgets/runner_profile_avatar_link.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_countdown.dart';
import '../domain/models/active_challenge.dart';
import '../domain/models/challenge_distance_format.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_participant_row.dart';
import '../domain/repositories/challenge_repository.dart';
import 'widgets/challenge_badge_image.dart';
import 'widgets/challenge_premium_lapse_banner.dart';
import 'widgets/challenge_widgets.dart';

/// The active-challenge Progress surface: team-progress ring, personal-minimum
/// mini bar, participant roster, and the single role-appropriate exit control.
///
/// Every number rendered here is a backend-owned value read back verbatim
/// (`teamMeters`, `targetMeters`, `creditedMeters`, `personalMinimumMeters`).
/// The client never recomputes target progress, eligibility, or completion, and
/// never renders routes, coordinates, run timestamps, or activity history — only
/// the privacy-safe participant snapshot fields.
class ChallengeProgressScreen extends StatefulWidget {
  const ChallengeProgressScreen({
    required this.challengeId,
    required this.repository,
    required this.onBack,
    this.clock,
    this.ticker,
    super.key,
  });

  final String challengeId;
  final ChallengeRepository repository;
  final VoidCallback onBack;
  final DateTime Function()? clock;
  final ChallengeTicker? ticker;

  @override
  State<ChallengeProgressScreen> createState() =>
      _ChallengeProgressScreenState();
}

class _ChallengeProgressScreenState extends State<ChallengeProgressScreen> {
  ActiveChallenge? _challenge;
  ChallengeCountdownController? _countdown;
  DateTime? _countdownEndsAt;
  bool? _countdownSettling;
  bool _loading = true;
  bool _ended = false;
  bool _busy = false;
  String? _error;
  StreamSubscription<ActiveChallenge?>? _subscription;

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
  /// subscription first so retry/re-subscribe (including the post-race
  /// re-read in [_runExit]) never leaks a listener.
  Future<void> _subscribe() async {
    unawaited(_subscription?.cancel());
    setState(() {
      _loading = _challenge == null && !_ended;
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
    final isThisLiveChallenge = challenge != null &&
        challenge.challengeId == widget.challengeId &&
        (challenge.status == ChallengeInstanceStatus.active ||
            challenge.status == ChallengeInstanceStatus.settling);
    if (!isThisLiveChallenge) {
      _countdown?.dispose();
      _countdown = null;
      setState(() {
        _challenge = null;
        _loading = false;
        _ended = true;
        _error = null;
      });
      return;
    }
    // The countdown controller is recreated only when the deadline or the
    // settling flag changes, so a progress-only emission (metres, roster)
    // never restarts its ticker.
    if (_countdown == null ||
        _countdownEndsAt != challenge.scheduledEndsAt ||
        _countdownSettling != challenge.isSettling) {
      _countdown?.dispose();
      _countdown = ChallengeCountdownController(
        clock: widget.clock ?? DateTime.now,
        ticker: widget.ticker,
        scheduledEndsAt: challenge.scheduledEndsAt,
        isSettling: challenge.isSettling,
      );
      _countdownEndsAt = challenge.scheduledEndsAt;
      _countdownSettling = challenge.isSettling;
    }
    setState(() {
      _challenge = challenge;
      _loading = false;
      _ended = false;
      _error = null;
    });
  }

  void _handleStreamError(Object error) {
    if (!mounted) {
      return;
    }
    // Once we already have data, a transient stream error is ignored rather
    // than replacing a working progress view with an error state.
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

  ChallengeParticipantRow? get _currentUserRow {
    final challenge = _challenge;
    if (challenge == null) {
      return null;
    }
    for (final row in challenge.participants) {
      if (row.isCurrentUser) {
        return row;
      }
    }
    return null;
  }

  /// ACTIVE participants: the current user first, then everyone else by
  /// credited metres descending. A current user who has LEFT drops to the
  /// muted "Left the challenge" group instead.
  List<ChallengeParticipantRow> get _activeRoster {
    final challenge = _challenge;
    if (challenge == null) {
      return const <ChallengeParticipantRow>[];
    }
    final active = challenge.participants
        .where((row) => row.status == ChallengeParticipantStatus.active)
        .toList()
      ..sort((a, b) => b.creditedMeters.compareTo(a.creditedMeters));
    active.sort((a, b) {
      if (a.isCurrentUser == b.isCurrentUser) {
        return 0;
      }
      return a.isCurrentUser ? -1 : 1;
    });
    return active;
  }

  List<ChallengeParticipantRow> get _leftRoster {
    final challenge = _challenge;
    if (challenge == null) {
      return const <ChallengeParticipantRow>[];
    }
    return challenge.participants.where((row) => row.hasLeft).toList()
      ..sort((a, b) => b.creditedMeters.compareTo(a.creditedMeters));
  }

  Future<void> _runExit(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on ChallengeFailure catch (failure) {
      if (mounted) {
        _showSnack(ChallengeCopy.failureMessage(failure.reason));
        // A race rejection (CHALLENGE_NOT_ACTIVE, etc.) means our snapshot is
        // stale — re-subscribe to re-read the trusted state rather than
        // trusting local UI.
        await _subscribe();
      }
    } catch (_) {
      if (mounted) {
        _showSnack(ChallengeCopy.failureMessage('UNKNOWN'));
        await _subscribe();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmLeave() async {
    final myMeters = _currentUserRow?.creditedMeters ?? 0;
    final confirmed = await _showConfirmSheet(
      title: ChallengeCopy.leaveChallenge,
      message: 'Your ${ChallengeDistanceFormat.kilometresLabel(myMeters)} '
          "stays with the team, but you can't rejoin and you won't earn the "
          'badge even if the team succeeds.',
      confirmLabel: ChallengeCopy.leaveChallenge,
    );
    if (confirmed != true) {
      return;
    }
    await _runExit(() async {
      await widget.repository.leave(challengeId: widget.challengeId);
      if (mounted) {
        Navigator.of(context).pop();
        _showSnack(ChallengeCopy.leftTheChallenge);
      }
    });
  }

  Future<void> _confirmAbandon() async {
    final runners = _challenge?.rosterUids.length ?? 0;
    final confirmed = await _showConfirmSheet(
      title: ChallengeCopy.abandonChallenge,
      message: 'This cancels the challenge for all $runners runners. '
          'No one will earn the badge.',
      confirmLabel: ChallengeCopy.abandonChallenge,
    );
    if (confirmed != true) {
      return;
    }
    await _runExit(() async {
      await widget.repository.abandon(challengeId: widget.challengeId);
      if (mounted) {
        Navigator.of(context).pop();
        _showSnack(_challengeCancelledSnack);
      }
    });
  }

  Future<bool?> _showConfirmSheet({
    required String title,
    required String message,
    required String confirmLabel,
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
                      tone: RuniacButtonTone.orange,
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
    final challenge = _challenge;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: challenge == null
                  ? ChallengeCopy.challengeTitle
                  : challengeTierTitle(challenge.tierId),
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
      return const ChallengeLoadingState(label: ChallengeCopy.inProgress);
    }
    if (_ended) {
      return const ChallengeEmptyState(
        title: _challengeEndedTitle,
        icon: Icons.flag_circle_outlined,
      );
    }
    final challenge = _challenge;
    if (challenge == null) {
      return ChallengeErrorState(
        message: _error ?? ChallengeCopy.exploreError,
        onRetry: _subscribe,
      );
    }
    return _buildProgress(challenge);
  }

  Widget _buildProgress(ActiveChallenge challenge) {
    final isSolo = challenge.mode == ChallengeMode.solo;
    final targetMeters = challenge.rules.targetMeters;
    final teamFraction = targetMeters <= 0
        ? 0.0
        : (challenge.teamMeters / targetMeters).clamp(0.0, 1.0);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              // Above the ring on purpose: a runner about to lose the challenge
              // should see that before they see their progress in it.
              ChallengePremiumLapseBanner(
                hold: challenge.premiumHold,
                onUpgrade: () => PremiumPaywallSheet.show(context),
              ),
              Center(
                child: _TeamProgressRing(
                  tierId: challenge.tierId,
                  fraction: teamFraction.toDouble(),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                ChallengeDistanceFormat.teamProgressLabel(
                  teamMetres: challenge.teamMeters,
                  targetMetres: targetMeters,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              _TimeLeftLine(controller: _countdown),
              const SizedBox(height: 22),
              if (!isSolo) ...[
                _MyDistanceBlock(
                  myMeters: _currentUserRow?.creditedMeters ?? 0,
                  personalMinimumMeters: challenge.rules.personalMinimumMeters,
                ),
                const SizedBox(height: 22),
              ],
              if (isSolo)
                const Text(
                  ChallengeCopy.soloChallenge,
                  style: TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                ..._rosterChildren(),
            ],
          ),
        ),
        // The exit control is pinned at the bottom so it is always reachable
        // regardless of roster length.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _buildExitControl(),
        ),
      ],
    );
  }

  List<Widget> _rosterChildren() {
    final active = _activeRoster;
    final left = _leftRoster;
    return <Widget>[
      ...active.map((row) => _ParticipantTile(row: row)),
      if (left.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text(
          ChallengeCopy.leftTheChallenge,
          style: TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ...left.map((row) => _ParticipantTile(row: row, muted: true)),
      ],
    ];
  }

  Widget _buildExitControl() {
    final challenge = _challenge;
    if (challenge == null) {
      return const SizedBox.shrink();
    }
    // Exactly one exit control per role: owners abandon, members leave.
    final isOwner = challenge.isCurrentUserOwner;
    final label =
        isOwner ? ChallengeCopy.abandonChallenge : ChallengeCopy.leaveChallenge;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        key: ValueKey<String>(
          isOwner ? 'challengeAbandonButton' : 'challengeLeaveButton',
        ),
        onPressed: _busy ? null : (isOwner ? _confirmAbandon : _confirmLeave),
        style: OutlinedButton.styleFrom(
          foregroundColor: RuniacColors.errorRed,
          side: const BorderSide(color: RuniacColors.errorRed),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MyDistanceBlock extends StatelessWidget {
  const _MyDistanceBlock({
    required this.myMeters,
    required this.personalMinimumMeters,
  });

  final int myMeters;
  final int personalMinimumMeters;

  @override
  Widget build(BuildContext context) {
    final met = myMeters >= personalMinimumMeters;
    final fraction = personalMinimumMeters <= 0
        ? 1.0
        : (myMeters / personalMinimumMeters).clamp(0.0, 1.0).toDouble();
    return ChallengeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My distance ${ChallengeDistanceFormat.kilometresLabel(myMeters)}',
            style: const TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _MinimumBar(fraction: fraction, met: met),
          const SizedBox(height: 8),
          if (met)
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: RuniacColors.successGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  _minimumReachedLabel,
                  style: const TextStyle(
                    color: RuniacColors.successGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            Text(
              ChallengeCopy.personalMinimum(
                _kilometresValue(personalMinimumMeters),
              ),
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _MinimumBar extends StatelessWidget {
  const _MinimumBar({required this.fraction, required this.met});

  final double fraction;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color =
        met ? RuniacColors.successGreen : RuniacColors.primaryBlue;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: RuniacColors.sectionSurfaceStrong),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single roster row on the Progress screen. The avatar links to the
/// runner's public profile — except the current user's own row, which is
/// never tappable.
///
/// Limitation: the backend's co-member gate for opening a profile reads
/// `challengeSlots/{caller}`, which only holds the caller's ACTIVE challenge.
/// So opening a participant from a settled (no-longer-active) challenge falls
/// through to the discoverability branch (public/friends visibility) rather
/// than the co-member allowance, or is denied entirely if neither applies.
class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.row, this.muted = false});

  final ChallengeParticipantRow row;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final isOwner = row.role == ChallengeParticipantRole.owner;
    final name = row.isCurrentUser ? 'You' : row.displayNameSnapshot;
    final nameColor =
        muted ? RuniacColors.textSecondary : RuniacColors.textPrimary;
    return Opacity(
      opacity: muted ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        // `explicitChildNodes: true` keeps the avatar's nested
        // `RunnerProfileAvatarLink` button semantics from merging upward into
        // whatever ancestor node happens to be the nearest semantics
        // boundary (this row has none of its own otherwise), which would
        // otherwise fold its "View <name> profile" label into an unrelated
        // combined node.
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: ChallengeCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                RunnerProfileAvatarLink(
                  uid: row.uid,
                  displayName: row.displayNameSnapshot,
                  avatarInitials: row.avatarInitialsSnapshot,
                  avatarUrl: row.avatarUrlSnapshot,
                  enabled: !row.isCurrentUser,
                  child: ChallengeInitialsAvatar(
                    initials: row.avatarInitialsSnapshot,
                    highlighted: row.isCurrentUser && !muted,
                    photoUrl: row.avatarUrlSnapshot,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: nameColor,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 8),
                        const ChallengeStatusChip(
                          label: 'Owner',
                          color: RuniacColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ChallengeDistanceFormat.kilometresLabel(row.creditedMeters),
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeLeftLine extends StatelessWidget {
  const _TimeLeftLine({required this.controller});

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
        final value = controller.value;
        if (value.isSettling) {
          return const Text(
            ChallengeCopy.calculatingResults,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          );
        }
        return Text(
          '${ChallengeCopy.timeLeft} ${value.label}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

/// Circular team-progress ring: a blue track with an orange arc (round caps),
/// clamped 0..1 from the trusted team/target metres, with the tier badge PNG
/// centered inside. The arc is never animated past the server value.
class _TeamProgressRing extends StatelessWidget {
  const _TeamProgressRing({required this.tierId, required this.fraction});

  final ChallengeTierId tierId;
  final double fraction;

  static const double _size = 176;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(_size),
            painter: _TeamProgressRingPainter(fraction: fraction),
          ),
          ChallengeBadgeImage(tierId: tierId, size: _size * 0.56),
        ],
      ),
    );
  }
}

class _TeamProgressRingPainter extends CustomPainter {
  const _TeamProgressRingPainter({required this.fraction});

  static const double _strokeWidth = 12;
  static const double _startAngle = -math.pi / 2;

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = RuniacColors.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, track);

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped > 0) {
      final arc = Paint()
        ..color = RuniacColors.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _strokeWidth;
      canvas.drawArc(rect, _startAngle, 2 * math.pi * clamped, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _TeamProgressRingPainter oldDelegate) {
    return oldDelegate.fraction != fraction;
  }
}

const String _challengeEndedTitle = 'This challenge has ended';
const String _challengeCancelledSnack = 'Challenge cancelled';
const String _minimumReachedLabel = 'Minimum reached';

String _kilometresValue(int metres) => (metres / 1000).toStringAsFixed(1);
