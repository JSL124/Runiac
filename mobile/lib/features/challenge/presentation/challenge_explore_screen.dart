import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../domain/challenge_copy.dart';
import '../domain/models/active_challenge.dart';
import '../domain/models/challenge_badge_ownership.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_tier.dart';
import '../domain/repositories/challenge_repository.dart';
import '../../paywall/presentation/premium_gate.dart';
import 'challenge_friend_picker_screen.dart';
import 'challenge_invitations_screen.dart';
import 'challenge_lobby_screen.dart';
import 'challenge_progress_screen.dart';
import 'challenge_tier_detail_screen.dart';
import 'widgets/challenge_badge_image.dart';
import 'widgets/challenge_widgets.dart';

/// Snapshot of everything the hub renders in one load.
class _ExploreData {
  const _ExploreData({
    required this.catalog,
    required this.premiumOnlyTierIds,
    required this.active,
    required this.invitationCount,
    required this.ownedBadges,
  });

  final List<ChallengeTier> catalog;

  /// Backend-designated premium-gated tiers (display-only lock UI; lobby
  /// creation is enforced server-side via `PREMIUM_REQUIRED`).
  final Set<ChallengeTierId> premiumOnlyTierIds;

  final ActiveChallenge? active;
  final int invitationCount;

  /// Null when the badge read store is not wired — the hub then degrades to
  /// rendering no earned marks rather than failing.
  final ChallengeBadgeOwnership? ownedBadges;
}

/// The Challenge hub landing: a 3x3 badge grid over the versioned catalog with
/// header actions for Invitations (pending-count badge) and History.
class ChallengeExploreScreen extends StatefulWidget {
  const ChallengeExploreScreen({
    required this.repository,
    required this.onBack,
    this.onOpenHistory,
    this.invitableFriendsLoader = noChallengeInvitableFriends,
    this.clock,
    super.key,
  });

  final ChallengeRepository repository;
  final VoidCallback onBack;
  final VoidCallback? onOpenHistory;
  final ChallengeInvitableFriendsLoader invitableFriendsLoader;
  final DateTime Function()? clock;

  @override
  State<ChallengeExploreScreen> createState() => _ChallengeExploreScreenState();
}

class _ChallengeExploreScreenState extends State<ChallengeExploreScreen> {
  _ExploreData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.repository.catalog();
      final active = await widget.repository.activeChallenge();
      final invitations = await widget.repository.invitations();
      final owned = await _loadOwnedBadges();
      if (!mounted) {
        return;
      }
      setState(() {
        _data = _ExploreData(
          catalog: catalog.tiers,
          premiumOnlyTierIds: catalog.premiumOnlyTierIds,
          active: _liveOrNull(active),
          invitationCount: invitations.length,
          ownedBadges: owned,
        );
        _loading = false;
      });
    } on ChallengeFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = ChallengeCopy.failureMessage(failure.reason);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = ChallengeCopy.exploreError;
      });
    }
  }

  /// Badge ownership degrades gracefully: an unavailable read store yields no
  /// earned marks rather than blocking the whole hub.
  Future<ChallengeBadgeOwnership?> _loadOwnedBadges() async {
    try {
      return await widget.repository.ownedBadges();
    } on ChallengeFailure {
      return null;
    } catch (_) {
      return null;
    }
  }

  ActiveChallenge? _liveOrNull(ActiveChallenge? active) {
    if (active == null || active.status.isTerminal) {
      return null;
    }
    return active;
  }

  bool get _slotHeld => _data?.active != null;

  Future<void> _openTierDetail(ChallengeTier tier) async {
    final owned = _data?.ownedBadges?.isOwned(tier.tierId) ?? false;
    final premiumOnly =
        _data?.premiumOnlyTierIds.contains(tier.tierId) ?? false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChallengeTierDetailScreen(
          tier: tier,
          repository: widget.repository,
          slotHeld: _slotHeld,
          earned: owned,
          premiumOnly: premiumOnly,
          onViewCurrentChallenge:
              _slotHeld ? () => _openCurrentChallenge(popFirst: true) : null,
          invitableFriendsLoader: widget.invitableFriendsLoader,
          clock: widget.clock,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _openInvitations() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChallengeInvitationsScreen(
          repository: widget.repository,
          slotHeld: _slotHeld,
          invitableFriendsLoader: widget.invitableFriendsLoader,
          clock: widget.clock,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _openCurrentChallenge({bool popFirst = false}) async {
    final active = _data?.active;
    if (active == null) {
      return;
    }
    if (popFirst && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    final route = active.status == ChallengeInstanceStatus.recruiting
        ? MaterialPageRoute<void>(
            builder: (context) => ChallengeLobbyScreen(
              challengeId: active.challengeId,
              repository: widget.repository,
              invitableFriendsLoader: widget.invitableFriendsLoader,
              clock: widget.clock,
              onBack: () => Navigator.of(context).pop(),
            ),
          )
        : MaterialPageRoute<void>(
            builder: (context) => ChallengeProgressScreen(
              challengeId: active.challengeId,
              repository: widget.repository,
              clock: widget.clock,
              onBack: () => Navigator.of(context).pop(),
            ),
          );
    await Navigator.of(context).push(route);
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitationCount = _data?.invitationCount ?? 0;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: ChallengeCopy.challengeTitle,
              onBack: widget.onBack,
              trailingWidth: 104,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InvitationsAction(
                    count: invitationCount,
                    onTap: _openInvitations,
                  ),
                  RuniacIconTileButton(
                    icon: Icons.history,
                    semanticLabel: ChallengeCopy.historyTitle,
                    onPressed: widget.onOpenHistory ?? () {},
                  ),
                ],
              ),
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
    final data = _data;
    if (data == null) {
      return ChallengeErrorState(
        message: _error ?? ChallengeCopy.exploreError,
        onRetry: _load,
      );
    }
    // One gate read for the whole grid; registers the account/paywall scope
    // dependencies so tiles unlock live when the trusted tier resolves.
    final paywallGate = watchShouldShowPaywall(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (data.active != null) ...[
          _SlotBanner(onView: () => _openCurrentChallenge()),
          const SizedBox(height: 14),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: data.catalog.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.64,
          ),
          itemBuilder: (context, index) {
            final tier = data.catalog[index];
            final inProgress = data.active?.tierId == tier.tierId;
            final earned = data.ownedBadges?.isOwned(tier.tierId) ?? false;
            // In-progress and earned override the lock: a lapsed Premium
            // runner keeps their badge and their running challenge — the
            // gate only stops NEW lobby creation (mirrors the backend).
            final locked = paywallGate &&
                data.premiumOnlyTierIds.contains(tier.tierId) &&
                !inProgress &&
                !earned;
            return _TierTile(
              tier: tier,
              inProgress: inProgress,
              earned: earned,
              locked: locked,
              onTap: () => _openTierDetail(tier),
            );
          },
        ),
      ],
    );
  }
}

class _SlotBanner extends StatelessWidget {
  const _SlotBanner({required this.onView});

  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: RuniacColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: RuniacColors.accentOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              ChallengeCopy.alreadyHaveChallengeInProgress,
              style: TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          TextButton(
            onPressed: onView,
            child: const Text(ChallengeCopy.viewCurrentChallenge),
          ),
        ],
      ),
    );
  }
}

class _InvitationsAction extends StatelessWidget {
  const _InvitationsAction({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = count > 0
        ? '${ChallengeCopy.invitationsTitle}, $count pending'
        : ChallengeCopy.invitationsTitle;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        RuniacIconTileButton(
          icon: Icons.mail_outline,
          semanticLabel: semantic,
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: RuniacColors.accentOrange,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: RuniacColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TierTile extends StatelessWidget {
  const _TierTile({
    required this.tier,
    required this.inProgress,
    required this.earned,
    required this.locked,
    required this.onTap,
  });

  final ChallengeTier tier;
  final bool inProgress;
  final bool earned;

  /// Premium-gated for this (Basic) runner: badge renders desaturated with a
  /// lock overlay. Display-only — the tile stays tappable so the detail
  /// screen can upsell, and the backend enforces creation.
  final bool locked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final badgeSize = constraints.maxWidth * 0.88;
        final semanticLabel =
            'Challenge ${challengeTierTitle(tier.tierId)} ${tier.difficultyLabel}';
        return RuniacTappableSurface(
          key: ValueKey<String>('challenge-tier-${tier.tierId.wireValue}'),
          onTap: onTap,
          semanticLabel: locked
              ? '$semanticLabel, ${ChallengeCopy.premiumTier}'
              : semanticLabel,
          borderRadius: BorderRadius.circular(18),
          decoration: BoxDecoration(
            color: RuniacColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: inProgress
                  ? RuniacColors.accentOrange
                  : RuniacColors.cardBorder,
              width: inProgress ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ChallengeLockableBadge(
                    tierId: tier.tierId,
                    size: badgeSize,
                    locked: locked,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    challengeTierTitle(tier.tierId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tier.difficultyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (inProgress)
                const Positioned(
                  left: 0,
                  top: 0,
                  child: ChallengeStatusChip(
                    label: ChallengeCopy.inProgress,
                    color: RuniacColors.accentOrange,
                    filled: true,
                  ),
                ),
              if (earned)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: RuniacColors.successGreen,
                    size: 18,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
