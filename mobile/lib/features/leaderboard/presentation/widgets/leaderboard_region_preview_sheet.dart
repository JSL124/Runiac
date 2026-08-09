import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_bottom_sheet_handle.dart';
import '../../domain/models/leaderboard_read_model.dart';
import '../leaderboard_status_copy.dart';
import '../models/leaderboard_display_models.dart';
import 'leaderboard_empty_state.dart';
import 'leaderboard_rank_row_helpers.dart';
import 'leaderboard_refresh_countdown.dart';
import 'leaderboard_visual_cta.dart';

// Display-only sheet copy. These labels never encode backend-owned rank, XP,
// or score values; the numeric values still come from the read model.
const String _rankPreviewTitle = 'My Rank Preview';
const String _primaryActionLabel = 'View More Ranking';
const String _secondaryActionLabel = 'Share My Rank';

class LeaderboardRegionPreviewSheet extends StatelessWidget {
  const LeaderboardRegionPreviewSheet({
    super.key,
    required this.snapshot,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onViewMoreRanking,
    required this.onShareMyRank,
    required this.onProfileSelected,
    required this.onHeightMeasured,
    this.clock,
  });

  final LeaderboardDetailDisplaySnapshot snapshot;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final VoidCallback onViewMoreRanking;
  final VoidCallback onShareMyRank;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  /// Reports the height the sheet actually laid out to. The sheet hugs its
  /// content, so the collapse animation and the drag maths cannot be derived
  /// from a constant; the owner feeds this measurement back into both.
  final ValueChanged<double> onHeightMeasured;

  /// Injected clock so the live refresh countdown ticks deterministically in
  /// tests; production falls back to the system clock.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final currentUserRow = snapshot.nearbyRanks
        .where((row) => row.isCurrentUser)
        .firstOrNull;
    final hasMyRank = snapshot.hasCurrentUserRank && currentUserRow != null;
    final showMyRankSection =
        snapshot.isUserRegion &&
        (snapshot.status == LeaderboardReadStatus.data ||
            snapshot.status == LeaderboardReadStatus.unranked);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Content-sized, so a short state (a message card, a region with no
        // My Rank section) never leaves dead space under the actions. The cap
        // is the space the tab gives us, so an unusually tall state stops at
        // the top of the tab instead of running off it.
        final maxSheetHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : double.infinity;
        final previewList = _RegionPreviewList(
          snapshot: snapshot,
          onProfileSelected: onProfileSelected,
        );

        return GestureDetector(
          key: const Key('leaderboard_sheet_surface'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: onVerticalDragUpdate,
          onVerticalDragEnd: onVerticalDragEnd,
          child: _MeasuredHeight(
            onHeightMeasured: onHeightMeasured,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFAFFFFFF),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0x332F50C7)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x30172033),
                      blurRadius: 28,
                      offset: Offset(0, -12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _LeaderboardSheetHandleArea(),
                      const _LeaderboardAccentStrip(),
                      const SizedBox(height: 10),
                      Text(
                        snapshot.regionName,
                        style: const TextStyle(
                          color: RuniacColors.textPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LeaderboardRefreshCountdown(
                        periodEndsAt: snapshot.periodEndsAt,
                        staticLabel: snapshot.refreshLabel,
                        live: snapshot.refreshLabelIsLive,
                        clock: clock,
                        style: const TextStyle(
                          color: RuniacColors.primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // At an outsized text scale the rank list is what gives
                      // way, so the actions below it stay reachable. Flex is
                      // only legal against a bounded main axis.
                      if (constraints.hasBoundedHeight)
                        Flexible(child: previewList)
                      else
                        previewList,
                      if (showMyRankSection) ...[
                        const SizedBox(height: 12),
                        _MyRankPreviewCard(
                          snapshot: snapshot,
                          currentUserRow: hasMyRank ? currentUserRow : null,
                          onProfileSelected: onProfileSelected,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _RegionPreviewActions(
                        showShareMyRank: snapshot.isUserRegion,
                        onViewMoreRanking: onViewMoreRanking,
                        onShareMyRank: onShareMyRank,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reports its child's laid-out height to the owner after layout settles.
///
/// The sheet hugs its content, so its height is only known once it has been
/// laid out; the owner needs that number to place the collapsed sheet and to
/// scale drag deltas.
class _MeasuredHeight extends SingleChildRenderObjectWidget {
  const _MeasuredHeight({
    required this.onHeightMeasured,
    required Widget super.child,
  });

  final ValueChanged<double> onHeightMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHeight(onHeightMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredHeight renderObject,
  ) {
    renderObject.onHeightMeasured = onHeightMeasured;
  }
}

class _RenderMeasuredHeight extends RenderProxyBox {
  _RenderMeasuredHeight(this.onHeightMeasured);

  ValueChanged<double> onHeightMeasured;
  double? _reportedHeight;

  @override
  void performLayout() {
    super.performLayout();
    final measuredHeight = size.height;
    if (_reportedHeight == measuredHeight) {
      return;
    }
    _reportedHeight = measuredHeight;
    // The owner rebuilds on this callback, which layout itself may not
    // trigger, so hand the measurement over once the frame has finished.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) {
        onHeightMeasured(measuredHeight);
      }
    });
  }
}

class _LeaderboardAccentStrip extends StatelessWidget {
  const _LeaderboardAccentStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('leaderboard_region_accent_strip'),
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: RuniacColors.primaryBlue,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardSheetHandleArea extends StatelessWidget {
  const _LeaderboardSheetHandleArea();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: Key('leaderboard_sheet_handle_area'),
      height: 46,
      child: Center(child: _SheetHandle()),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return const RuniacBottomSheetHandle(
      key: Key('leaderboard_sheet_handle'),
      width: 44,
      height: 5,
      semanticLabel: 'Leaderboard sheet handle',
    );
  }
}

class _RegionPreviewList extends StatelessWidget {
  const _RegionPreviewList({
    required this.snapshot,
    required this.onProfileSelected,
  });

  final LeaderboardDetailDisplaySnapshot snapshot;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    switch (snapshot.status) {
      case LeaderboardReadStatus.updating:
        return const _RegionPreviewMessageCard(
          message: leaderboardUpdatingBody,
        );
      case LeaderboardReadStatus.ineligiblePremium:
        return const _RegionPreviewMessageCard(
          message: leaderboardIneligibleBody,
        );
      case LeaderboardReadStatus.ineligibleMinRuns:
        return const _RegionPreviewMessageCard(
          message: leaderboardIneligibleMinRunsBody,
        );
      case LeaderboardReadStatus.data:
      // Unranked keeps the real board visible; the My Rank Preview section
      // below carries the encouragement copy instead of hiding the rows.
      case LeaderboardReadStatus.unranked:
      case LeaderboardReadStatus.empty:
      case LeaderboardReadStatus.regionRequired:
        break;
    }

    if (snapshot.topRanks.isEmpty) {
      return LeaderboardEmptyState(
        compact: true,
        title: leaderboardEmptyStateTitle,
        body: leaderboardEmptyStateBody(snapshot.regionName),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RegionPreviewRankCard(
          rows: snapshot.topRanks.take(3).toList(),
          onProfileSelected: onProfileSelected,
          keyPrefix: 'leaderboard_region_top_rank_row',
          useTopMedals: true,
        ),
      ],
    );
  }
}

class _RegionPreviewRankCard extends StatelessWidget {
  const _RegionPreviewRankCard({
    required this.rows,
    required this.onProfileSelected,
    required this.keyPrefix,
    this.useTopMedals = false,
  });

  final List<LeaderboardRankRowDisplaySnapshot> rows;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;
  final String keyPrefix;
  final bool useTopMedals;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE3F8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              _RegionPreviewRankRow(
                key: ValueKey('${keyPrefix}_$index'),
                row: rows[index],
                medalTone: useTopMedals
                    ? RegionPreviewMedalTone.values[index]
                    : null,
                onProfileSelected: onProfileSelected,
              ),
              if (index != rows.length - 1)
                const Divider(height: 1, color: Color(0xFFE4E9FA)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RegionPreviewRankRow extends StatelessWidget {
  const _RegionPreviewRankRow({
    super.key,
    required this.row,
    required this.onProfileSelected,
    this.medalTone,
  });

  final LeaderboardRankRowDisplaySnapshot row;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;
  final RegionPreviewMedalTone? medalTone;

  @override
  Widget build(BuildContext context) {
    const rowMinHeight = 56.0;
    const horizontalPadding = 10.0;
    const verticalPadding = 7.0;
    const rankGap = 10.0;
    const nameGap = 10.0;
    const xpGap = 8.0;
    const badgeSize = 38.0;
    const nameFontSize = 14.0;
    const xpFontSize = 14.0;

    return Semantics(
      button: true,
      label: 'Open ${row.name} runner profile',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onProfileSelected(row.profile),
          child: Container(
            key: row.isCurrentUser
                ? const Key('leaderboard_region_current_user_row')
                : null,
            constraints: BoxConstraints(minHeight: rowMinHeight),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              children: [
                _RegionPreviewRankBadge(
                  row: row,
                  medalTone: medalTone,
                  size: badgeSize,
                ),
                SizedBox(width: rankGap),
                LeaderboardInitialBadge(
                  name: row.name,
                  levelLabel: row.levelBadgeLabel,
                  isCurrentUser: row.isCurrentUser,
                  photoUrl: row.photoUrl,
                  levelProgressFraction: row.levelProgressFraction,
                ),
                SizedBox(width: nameGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: row.isCurrentUser
                              ? RuniacColors.primaryBlue
                              : RuniacColors.textPrimary,
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: xpGap),
                Text(
                  row.xpLabel,
                  style: TextStyle(
                    color: RuniacColors.primaryBlue,
                    fontSize: xpFontSize,
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

class _RegionPreviewRankBadge extends StatelessWidget {
  const _RegionPreviewRankBadge({
    required this.row,
    required this.size,
    this.medalTone,
  });

  final LeaderboardRankRowDisplaySnapshot row;
  final double size;
  final RegionPreviewMedalTone? medalTone;

  @override
  Widget build(BuildContext context) {
    final tone = medalTone;
    if (tone != null) {
      final colors = resolveRegionPreviewMedalColors(tone);

      return Container(
        key: ValueKey<String>('leaderboard_region_rank_badge_${row.rankLabel}'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(
          Icons.emoji_events_outlined,
          color: colors.foreground,
          size: 21,
        ),
      );
    }

    return Container(
      key: row.isCurrentUser
          ? const Key('leaderboard_region_current_user_rank_badge')
          : ValueKey<String>('leaderboard_region_rank_badge_${row.rankLabel}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: row.isCurrentUser
            ? const Color(0xFFFFE2D2)
            : RuniacColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        row.rankLabel,
        style: TextStyle(
          color: row.isCurrentUser
              ? RuniacColors.accentOrange
              : RuniacColors.primaryBlue,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MyRankPreviewCard extends StatelessWidget {
  const _MyRankPreviewCard({
    required this.snapshot,
    required this.currentUserRow,
    required this.onProfileSelected,
  });

  final LeaderboardDetailDisplaySnapshot snapshot;

  // Backend-provided current-user row, or null when the runner has no rank.
  // Presence check only — no rank or score is computed on the client.
  final LeaderboardRankRowDisplaySnapshot? currentUserRow;
  final ValueChanged<RunnerAchievementProfileSnapshot> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    final row = currentUserRow;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _rankPreviewTitle,
          style: const TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        if (row == null)
          const _RegionPreviewMessageCard(
            key: Key('leaderboard_region_my_rank_encouragement'),
            message: leaderboardUnrankedBody,
          )
        else
          _RegionPreviewRankCard(
            rows: [row],
            onProfileSelected: onProfileSelected,
            keyPrefix: 'leaderboard_region_my_rank_row',
          ),
      ],
    );
  }
}

class _RegionPreviewMessageCard extends StatelessWidget {
  const _RegionPreviewMessageCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE3F8)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: RuniacColors.textSecondary,
          fontSize: 13,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RegionPreviewActions extends StatelessWidget {
  const _RegionPreviewActions({
    required this.showShareMyRank,
    required this.onViewMoreRanking,
    required this.onShareMyRank,
  });

  final bool showShareMyRank;
  final VoidCallback onViewMoreRanking;
  final VoidCallback onShareMyRank;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: showShareMyRank ? 1 : 2,
          child: LeaderboardVisualCta(
            key: const Key('leaderboard_view_more_ranking_button'),
            label: _primaryActionLabel,
            filled: true,
            onTap: onViewMoreRanking,
          ),
        ),
        if (showShareMyRank) ...[
          const SizedBox(width: 10),
          Expanded(
            child: LeaderboardVisualCta(
              key: const Key('leaderboard_share_my_rank_button'),
              label: _secondaryActionLabel,
              filled: false,
              onTap: onShareMyRank,
            ),
          ),
        ],
      ],
    );
  }
}
