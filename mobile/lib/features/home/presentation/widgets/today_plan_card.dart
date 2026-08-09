import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/home_dashboard_demo_snapshots.dart';

/// The card on Home that says what today's session is, and starts it.
///
/// Two actions on purpose: **View plan** for the runner who wants context, and
/// **Quick start** for the one who just wants to go. The card also has to read
/// well on a rest day and on a day the session is already done, which is what
/// [_GoalModeBadge] and the copy block distinguish.
class TodayPlanCard extends StatelessWidget {
  const TodayPlanCard({
    required this.onViewPlan,
    required this.onQuickStart,
    super.key,
  });

  final VoidCallback onViewPlan;
  final VoidCallback onQuickStart;

  @override
  Widget build(BuildContext context) {
    const snapshot = homeTodayPlanDemoSnapshot;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        const cardHeight = 236.0;
        final horizontalPadding = cardWidth < 360 ? 18.0 : 22.0;
        final contentMaxWidth = cardWidth < 360
            ? cardWidth * 0.68
            : cardWidth * 0.62;

        return SizedBox(
          height: cardHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                snapshot.heroAssetPath,
                key: const ValueKey('today_plan_hero_image'),
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
              const _HeroBlueOverlay(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMaxWidth),
                      child: const _TodayPlanCopy(snapshot: snapshot),
                    ),
                    const Spacer(),
                    _TodayPlanActions(
                      onViewPlan: onViewPlan,
                      onQuickStart: onQuickStart,
                      snapshot: snapshot,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroBlueOverlay extends StatelessWidget {
  const _HeroBlueOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                RuniacColors.primaryBlue.withValues(alpha: 0.96),
                const Color(0xFF193B95).withValues(alpha: 0.88),
                const Color(0xFF2858B8).withValues(alpha: 0.48),
                Colors.transparent,
              ],
              stops: const [0, 0.38, 0.66, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                const Color(0xFF081D54).withValues(alpha: 0.42),
                Colors.transparent,
              ],
              stops: const [0, 0.58],
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayPlanCopy extends StatelessWidget {
  const _TodayPlanCopy({required this.snapshot});

  final HomeTodayPlanDemoSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                snapshot.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            snapshot.headline,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.02,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _GoalModeBadge(label: snapshot.badgeLabel),
        const SizedBox(height: 8),
        Text(
          snapshot.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.24,
          ),
        ),
      ],
    );
  }
}

class _GoalModeBadge extends StatelessWidget {
  const _GoalModeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            color: Color(0xFFFFC445),
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayPlanActions extends StatelessWidget {
  const _TodayPlanActions({
    required this.onViewPlan,
    required this.onQuickStart,
    required this.snapshot,
  });

  final VoidCallback onViewPlan;
  final VoidCallback onQuickStart;
  final HomeTodayPlanDemoSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onViewPlan,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.72)),
              backgroundColor: Colors.white.withValues(alpha: 0.04),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(snapshot.secondaryActionLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onQuickStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 24),
            label: Text(snapshot.primaryActionLabel),
            style: FilledButton.styleFrom(
              foregroundColor: RuniacColors.primaryBlue,
              backgroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
