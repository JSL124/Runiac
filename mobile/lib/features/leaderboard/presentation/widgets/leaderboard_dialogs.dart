import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/leaderboard_demo_snapshots.dart';
import '../models/leaderboard_display_models.dart';
import 'leaderboard_top_overlay.dart';

/// The explainer dialogs behind the leaderboard's help icons — how scoring
/// works, and what the league tiers mean.
///
/// Split out of the tab because they are pure copy: a runner who does not
/// understand why their rank moved will not trust the leaderboard, and these
/// two dialogs are the answer to that.
void showLeaderboardTipsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: RuniacColors.textPrimary.withValues(alpha: 0.38),
    builder: (context) => const _LeaderboardTipsDialog(),
  );
}

void showLeaderboardLeaguesDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: RuniacColors.textPrimary.withValues(alpha: 0.38),
    builder: (context) => const _LeaderboardLeaguesDialog(),
  );
}

class _LeaderboardTipsDialog extends StatelessWidget {
  const _LeaderboardTipsDialog();

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.sizeOf(context).height - 56;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 430, maxHeight: maxDialogHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF8FFFFFF),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x552F50C7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33172033),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Close tips',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: RuniacColors.textPrimary,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          leaderboardPreviewDemoSnapshot.tipsTitle,
                          style: const TextStyle(
                            color: RuniacColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 14),
                _TipsSection(
                  icon: Icons.emoji_events_outlined,
                  title: leaderboardPreviewDemoSnapshot.leaguesTipTitle,
                  body: leaderboardPreviewDemoSnapshot.leaguesTipBody,
                ),
                const SizedBox(height: 10),
                _TipsSection(
                  icon: Icons.calendar_month_outlined,
                  title: leaderboardPreviewDemoSnapshot.cadenceTipTitle,
                  body: leaderboardPreviewDemoSnapshot.cadenceTipBody,
                ),
                const SizedBox(height: 10),
                _TipsSection(
                  icon: Icons.verified_user_outlined,
                  title: leaderboardPreviewDemoSnapshot.readinessTipTitle,
                  body: leaderboardPreviewDemoSnapshot.readinessTipBody,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardLeaguesDialog extends StatelessWidget {
  const _LeaderboardLeaguesDialog();

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.sizeOf(context).height - 56;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 430, maxHeight: maxDialogHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF8FFFFFF),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x552F50C7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33172033),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Close leagues',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: RuniacColors.textPrimary,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          leaderboardLeagueDemoSnapshot.dialogTitle,
                          style: const TextStyle(
                            color: RuniacColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: RuniacColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDADDE1)),
                  ),
                  child: Column(
                    children: [
                      for (final entry
                          in leaderboardLeagueDemoSnapshot.entries) ...[
                        _LeagueTaxonomyRow(entry: entry),
                        if (entry != leaderboardLeagueDemoSnapshot.entries.last)
                          const Divider(height: 1, color: Color(0xFFE7E9EC)),
                      ],
                    ],
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

class _LeagueTaxonomyRow extends StatelessWidget {
  const _LeagueTaxonomyRow({required this.entry});

  final LeagueTaxonomyEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          LeaderboardLeagueMedalIcon(
            key: ValueKey<String>('leaderboard_league_emblem_${entry.name}'),
            assetPath: entry.assetPath,
            width: 32,
            height: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${entry.name} (${entry.range})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsSection extends StatelessWidget {
  const _TipsSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: RuniacColors.primaryBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: RuniacColors.primaryBlue.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3EC),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, color: RuniacColors.accentOrange, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
