import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_avatar_photo.dart';
import '../../../../core/widgets/runiac_back_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../profile/presentation/runner_public_profile_scope.dart';
import '../../domain/models/leaderboard_read_model.dart';
import '../leaderboard_status_copy.dart';
import '../models/leaderboard_display_models.dart';
import 'leaderboard_empty_state.dart';
import 'leaderboard_rank_row_helpers.dart';
import 'runner_achievement_profile_screen.dart';

/// Routed "View More Ranking" page: a top-3 podium plus a nearby/top runners
/// list. Display-only. All rank, score, and XP values are read verbatim from
/// the backend-produced [LeaderboardDetailDisplaySnapshot]; nothing is
/// computed on the client.
class LeaderboardRankingScreen extends StatelessWidget {
  const LeaderboardRankingScreen({super.key, required this.snapshot});

  final LeaderboardDetailDisplaySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // Scaffold (not a bare ColoredBox) so the pushed route has a Material
    // ancestor; without one, every Text renders with debug yellow underlines.
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: snapshot.regionName,
              tooltip: 'Back to Leaderboard',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PeriodHeader(
                        periodLabel: resolveLeaderboardPeriodLabelForDisplay(
                          periodLabel: snapshot.periodLabel,
                          fallbackPeriodLabel: snapshot.fallbackPeriodLabel,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._buildBody(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    switch (snapshot.status) {
      case LeaderboardReadStatus.empty:
        return [_emptyCard()];
      case LeaderboardReadStatus.updating:
        return const [_UpdatingCard()];
      case LeaderboardReadStatus.ineligiblePremium:
        return [
          LeaderboardEmptyState(
            title: snapshot.regionName,
            body: leaderboardIneligibleBody,
          ),
        ];
      case LeaderboardReadStatus.ineligibleMinRuns:
        return [
          LeaderboardEmptyState(
            title: snapshot.regionName,
            body: leaderboardIneligibleMinRunsBody,
          ),
        ];
      case LeaderboardReadStatus.data:
      case LeaderboardReadStatus.unranked:
      case LeaderboardReadStatus.regionRequired:
        break;
    }

    if (snapshot.topRanks.isEmpty) {
      return [_emptyCard()];
    }

    return [
      _Podium(
        rows: snapshot.topRanks,
        onProfileSelected: (profile) => _openProfile(context, profile),
      ),
      const SizedBox(height: 22),
      ..._buildListSection(context),
    ];
  }

  Widget _emptyCard() {
    return LeaderboardEmptyState(
      key: const Key('leaderboard_empty_state'),
      title: leaderboardEmptyStateTitle,
      body: leaderboardEmptyStateBody(snapshot.regionName),
    );
  }

  List<Widget> _buildListSection(BuildContext context) {
    return [
      _LeaderboardRankListCard(
        title: snapshot.topRanksTitle,
        rows: snapshot.topRanks,
        keyPrefix: 'leaderboard_detail_top_rank_row',
        onProfileSelected: (profile) => _openProfile(context, profile),
      ),
      if (snapshot.isUserRegion) ...[
        const SizedBox(height: 14),
        _LeaderboardNearbyDivider(title: snapshot.nearbyRanksTitle),
        const SizedBox(height: 10),
        if (!snapshot.hasCurrentUserRank || snapshot.nearbyRanks.isEmpty)
          const LeaderboardEmptyState(
            title: 'Not ranked yet',
            body: leaderboardUnrankedBody,
            compact: true,
          )
        else
          _LeaderboardRankListCard(
            rows: snapshot.nearbyRanks,
            keyPrefix: 'leaderboard_detail_nearby_rank_row',
            onProfileSelected: (profile) => _openProfile(context, profile),
          ),
      ],
    ];
  }

  void _openProfile(
    BuildContext context,
    RunnerAchievementProfileSnapshot profile,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => RunnerAchievementProfileScreen(
          profile: profile,
          onBack: () => Navigator.of(routeContext).pop(),
          publicProfileRepository: RunnerPublicProfileScope.of(context),
        ),
      ),
    );
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.periodLabel});

  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 22,
          decoration: BoxDecoration(
            color: RuniacColors.primaryBlue,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Monthly — $periodLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.rows, required this.onProfileSelected});

  final List<LeaderboardRankRowDisplaySnapshot> rows;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    final podium = rows.take(3).toList();
    final first = podium[0];
    final second = podium.length > 1 ? podium[1] : null;
    final third = podium.length > 2 ? podium[2] : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: second == null
              ? const SizedBox.shrink()
              : _PodiumSlot(
                  row: second,
                  rank: 2,
                  onProfileSelected: onProfileSelected,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PodiumSlot(
            row: first,
            rank: 1,
            onProfileSelected: onProfileSelected,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: third == null
              ? const SizedBox.shrink()
              : _PodiumSlot(
                  row: third,
                  rank: 3,
                  onProfileSelected: onProfileSelected,
                ),
        ),
      ],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.row,
    required this.rank,
    required this.onProfileSelected,
  });

  final LeaderboardRankRowDisplaySnapshot row;
  final int rank;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  static RegionPreviewMedalTone _toneForRank(int rank) {
    return switch (rank) {
      1 => RegionPreviewMedalTone.gold,
      2 => RegionPreviewMedalTone.silver,
      _ => RegionPreviewMedalTone.bronze,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final colors = resolveRegionPreviewMedalColors(_toneForRank(rank));
    final avatarSize = isFirst ? 76.0 : 58.0;

    return Semantics(
      button: true,
      label: 'Open ${row.name} runner profile',
      child: Column(
        key: ValueKey('leaderboard_podium_rank_$rank'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFirst)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Icon(
                Icons.emoji_events,
                key: Key('leaderboard_podium_crown'),
                color: RuniacColors.accentOrange,
                size: 26,
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onProfileSelected(row.profile),
            child: _PodiumAvatar(
              name: row.name,
              photoUrl: row.photoUrl,
              rank: rank,
              size: avatarSize,
              ringColor: colors.foreground,
              discColor: colors.background,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            row.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: isFirst ? 14 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            row.xpLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RuniacColors.primaryBlue,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumAvatar extends StatelessWidget {
  const _PodiumAvatar({
    required this.name,
    required this.photoUrl,
    required this.rank,
    required this.size,
    required this.ringColor,
    required this.discColor,
  });

  final String name;

  /// Raw, not-yet-sanitised avatar photo URL for this podium runner, same
  /// value the list row below renders. Empty — or anything the sanitiser in
  /// `runiac_avatar_photo.dart` rejects — falls back to the initial disc.
  final String photoUrl;

  final int rank;
  final double size;
  final Color ringColor;
  final Color discColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 12,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            key: ValueKey('leaderboard_podium_avatar_$rank'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: discColor,
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 3),
            ),
            child: RuniacAvatarPhotoDisc(
              photoUrl: photoUrl,
              fallback: Text(
                _initialLabel(name),
                maxLines: 1,
                style: TextStyle(
                  color: ringColor,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: size - 10,
            child: _PodiumRankChip(rank: rank, color: ringColor),
          ),
        ],
      ),
    );
  }
}

class _PodiumRankChip extends StatelessWidget {
  const _PodiumRankChip({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RuniacColors.white, width: 2),
      ),
      child: Text(
        '$rank',
        style: const TextStyle(
          color: RuniacColors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _LeaderboardRankListCard extends StatelessWidget {
  const _LeaderboardRankListCard({
    required this.rows,
    required this.keyPrefix,
    required this.onProfileSelected,
    this.title,
  });

  final String? title;
  final List<LeaderboardRankRowDisplaySnapshot> rows;
  final String keyPrefix;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: const TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: RuniacColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDDE3F8)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  _LeaderboardRankRow(
                    key: ValueKey('${keyPrefix}_$index'),
                    row: rows[index],
                    onProfileSelected: onProfileSelected,
                  ),
                  if (index != rows.length - 1)
                    const Divider(height: 1, color: Color(0xFFE4E9FA)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardRankRow extends StatelessWidget {
  const _LeaderboardRankRow({
    super.key,
    required this.row,
    required this.onProfileSelected,
  });

  final LeaderboardRankRowDisplaySnapshot row;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    final background = row.isCurrentUser
        ? const Color(0xFFFFF1EA)
        : Colors.transparent;

    return Semantics(
      button: true,
      label: 'Open ${row.name} runner profile',
      child: Material(
        color: background,
        child: InkWell(
          onTap: () => onProfileSelected(row.profile),
          child: Container(
            key: row.isCurrentUser
                ? const Key('leaderboard_detail_current_user_row')
                : null,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                _RankBadge(row: row),
                const SizedBox(width: 12),
                LeaderboardInitialBadge(
                  name: row.name,
                  levelLabel: row.levelBadgeLabel,
                  isCurrentUser: row.isCurrentUser,
                  photoUrl: row.photoUrl,
                  levelProgressFraction: row.levelProgressFraction,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: row.isCurrentUser
                              ? RuniacColors.primaryBlue
                              : RuniacColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  row.xpLabel,
                  style: const TextStyle(
                    color: RuniacColors.primaryBlue,
                    fontSize: 16,
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

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.row});

  final LeaderboardRankRowDisplaySnapshot row;

  @override
  Widget build(BuildContext context) {
    final medalTone = row.medalTone;
    if (medalTone != null) {
      final colors = resolveRegionPreviewMedalColors(medalTone);

      return Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(
          Icons.emoji_events_outlined,
          color: colors.foreground,
          size: 22,
        ),
      );
    }

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: row.trophy
            ? const Color(0xFFFFF2E9)
            : RuniacColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: row.trophy
          ? const Icon(
              Icons.emoji_events_outlined,
              color: RuniacColors.accentOrange,
              size: 22,
            )
          : Text(
              row.rankLabel,
              style: TextStyle(
                color: row.isCurrentUser
                    ? RuniacColors.accentOrange
                    : RuniacColors.primaryBlue,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}

class _LeaderboardNearbyDivider extends StatelessWidget {
  const _LeaderboardNearbyDivider({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: RuniacColors.primaryBlue.withValues(alpha: 0.18),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            color: RuniacColors.primaryBlue.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

class _UpdatingCard extends StatelessWidget {
  const _UpdatingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            Row(
              children: const [
                SkeletonDot(),
                SizedBox(width: 12),
                Expanded(child: SkeletonLine()),
                SizedBox(width: 12),
                SkeletonLine(width: 40),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            leaderboardUpdatingBody,
            style: TextStyle(
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

String _initialLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'R';
  }
  return trimmed.characters.first.toUpperCase();
}
