import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_avatar_photo.dart';
import '../../domain/challenge_copy.dart';
import '../../domain/models/challenge_distance_format.dart';

/// Centered loading state (spinner + label) for Challenge surfaces.
class ChallengeLoadingState extends StatelessWidget {
  const ChallengeLoadingState({this.label = ChallengeCopy.exploreLoading, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen offline/error state with a retry action.
class ChallengeErrorState extends StatelessWidget {
  const ChallengeErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: RuniacColors.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text(ChallengeCopy.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered empty state (icon + title) for lists with no items.
class ChallengeEmptyState extends StatelessWidget {
  const ChallengeEmptyState({
    required this.title,
    this.icon = Icons.emoji_events_outlined,
    super.key,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RuniacColors.textSecondary, size: 40),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text-bearing status chip. State is never colour-only — the label always
/// carries the meaning.
class ChallengeStatusChip extends StatelessWidget {
  const ChallengeStatusChip({
    required this.label,
    required this.color,
    this.filled = false,
    super.key,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? RuniacColors.white : color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// A 42px initials avatar built from a backend-authored initials snapshot. No
/// level, XP, or trusted progress is rendered here.
class ChallengeInitialsAvatar extends StatelessWidget {
  const ChallengeInitialsAvatar({
    required this.initials,
    this.size = 42,
    this.highlighted = false,
    this.photoUrl,
    super.key,
  });

  final String initials;
  final double size;
  final bool highlighted;

  /// Raw, not-yet-sanitised avatar photo URL. Renders the initials when
  /// absent, when it fails the client-side sanitiser in
  /// `runiac_avatar_photo.dart`, or if the image fails to load.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final base = highlighted
        ? RuniacColors.primaryBlue
        : RuniacColors.sectionSurfaceStrong;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: base,
          shape: BoxShape.circle,
          border: Border.all(color: RuniacColors.cardBorder),
        ),
        child: RuniacAvatarPhotoDisc(
          photoUrl: photoUrl,
          fallback: Text(
            initials,
            style: TextStyle(
              color: highlighted
                  ? RuniacColors.white
                  : RuniacColors.primaryBlue,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

/// A radius-18 white card with the standard card border.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// The tier rules card shared by tier detail and invitation detail. All values
/// are backend-owned integers rendered display-only; nothing is recomputed.
class ChallengeRulesCard extends StatelessWidget {
  const ChallengeRulesCard({
    required this.targetMeters,
    required this.durationDays,
    required this.maxParticipants,
    required this.personalMinimumMeters,
    super.key,
  });

  final int targetMeters;
  final int durationDays;
  final int maxParticipants;
  final int personalMinimumMeters;

  @override
  Widget build(BuildContext context) {
    final targetLabel = ChallengeDistanceFormat.kilometresLabel(targetMeters);
    final minimumLabel =
        ChallengeDistanceFormat.kilometresLabel(personalMinimumMeters);
    return ChallengeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RuleRow(
            icon: Icons.flag_outlined,
            label: ChallengeCopy.ruleTargetDistance,
            value: targetLabel,
          ),
          const _RuleDivider(),
          _RuleRow(
            icon: Icons.calendar_today_outlined,
            label: ChallengeCopy.ruleDuration,
            value: ChallengeCopy.durationWeeksLabel(durationDays),
          ),
          const _RuleDivider(),
          _RuleRow(
            icon: Icons.group_outlined,
            label: ChallengeCopy.ruleParticipants,
            value: ChallengeCopy.participantsRule(maxParticipants),
          ),
          const _RuleDivider(),
          _RuleRow(
            icon: Icons.directions_run_outlined,
            label: ChallengeCopy.rulePersonalMinimum,
            value: ChallengeCopy.personalMinimumRule(minimumLabel),
          ),
          const _RuleDivider(),
          _RuleRow(
            icon: Icons.groups_2_outlined,
            label: ChallengeCopy.ruleGroupGoal,
            value: ChallengeCopy.groupCombinedRule,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RuniacColors.accentOrange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: RuniacColors.accentOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ChallengeCopy.soloWarning(targetLabel),
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
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

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: RuniacColors.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
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

class _RuleDivider extends StatelessWidget {
  const _RuleDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: RuniacColors.border);
  }
}
