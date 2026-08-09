import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../domain/challenge_copy.dart';
import '../domain/models/challenge_distance_format.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_history.dart';
import 'challenge_result_ceremony.dart';
import 'widgets/challenge_badge_image.dart';
import 'widgets/challenge_widgets.dart';

/// The full-screen, presented-once Challenge result surface.
///
/// Five variants are keyed entirely by the backend-owned [ChallengeResult]
/// outcome, never recomputed client-side:
///  1. SUCCEEDED  — badge earned (large full-colour badge, warm celebration).
///  2. INELIGIBLE — team reached the target, caller missed the personal minimum.
///  3. FAILED     — deadline passed without the target.
///  4. CANCELLED  — owner abandoned the challenge for everyone.
///  5. LEFT       — the caller left; their metres stayed with the team.
///
/// Every kilometre figure is rendered through the shared 0.1 km formatter; the
/// widget only displays the server outcome verbatim.
class ChallengeResultScreen extends StatelessWidget {
  const ChallengeResultScreen({
    required this.result,
    required this.onClose,
    this.onViewBadgeCollection,
    super.key,
  });

  final ChallengeResult result;

  /// Closes the result surface ("Done").
  final VoidCallback onClose;

  /// Routes to the Account badge collection. Wired by the composition only for
  /// the badge-earned variant; `null` hides the action.
  final VoidCallback? onViewBadgeCollection;

  _ResultVariant get _variant {
    switch (result.outcome) {
      case ChallengeParticipantStatus.succeeded:
        return _ResultVariant.badgeEarned;
      case ChallengeParticipantStatus.ineligible:
        return _ResultVariant.minimumMissed;
      case ChallengeParticipantStatus.failed:
        return _ResultVariant.deadlineFailed;
      case ChallengeParticipantStatus.cancelled:
        return _ResultVariant.cancelled;
      case ChallengeParticipantStatus.left:
        return _ResultVariant.left;
      case ChallengeParticipantStatus.accepted:
      case ChallengeParticipantStatus.active:
        return _ResultVariant.cancelled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final variant = _variant;
    final earned = variant == _ResultVariant.badgeEarned;
    final tierTitle = challengeTierTitle(result.tierId);
    final targetLabel = ChallengeDistanceFormat.kilometresLabel(
      result.targetMeters,
    );
    final teamLabel = ChallengeDistanceFormat.kilometresLabel(
      result.teamMeters,
    );
    final mineLabel = ChallengeDistanceFormat.kilometresLabel(
      result.creditedMeters,
    );
    final minimumLabel = ChallengeDistanceFormat.kilometresLabel(
      result.personalMinimumMeters,
    );

    final _ResultCopy copy = switch (variant) {
      _ResultVariant.badgeEarned => _ResultCopy(
        title: ChallengeCopy.badgeEarnedHeadline(tierTitle),
        body: ChallengeCopy.badgeEarnedSubtitle,
      ),
      _ResultVariant.minimumMissed => _ResultCopy(
        chip: ChallengeCopy.personalMinimumNotReached,
        title: ChallengeCopy.minimumMissedTitle,
        body: ChallengeCopy.minimumMissedBody(
          targetLabel: targetLabel,
          mineLabel: mineLabel,
          minimumLabel: minimumLabel,
        ),
        support: ChallengeCopy.stillAddedSupport(mineLabel),
      ),
      _ResultVariant.deadlineFailed => _ResultCopy(
        title: ChallengeCopy.deadlineFailedTitle,
        body: ChallengeCopy.deadlineFailedBody(
          teamLabel: teamLabel,
          targetLabel: targetLabel,
        ),
      ),
      _ResultVariant.cancelled => const _ResultCopy(
        title: ChallengeCopy.resultCancelledTitle,
        body: ChallengeCopy.resultCancelledBody,
      ),
      _ResultVariant.left => _ResultCopy(
        title: ChallengeCopy.resultLeftTitle,
        body: ChallengeCopy.resultLeftBody(mineLabel),
      ),
    };

    final accent = earned
        ? RuniacColors.accentOrange
        : RuniacColors.primaryBlue;

    return Scaffold(
      key: const ValueKey<String>('challenge-result-screen'),
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 6, 0),
                child: IconButton(
                  tooltip: ChallengeCopy.resultDone,
                  icon: const Icon(Icons.close_rounded),
                  color: RuniacColors.textSecondary,
                  onPressed: onClose,
                ),
              ),
            ),
            Expanded(
              // A plain scroll view shrink-wraps its child, so the column's
              // centering has no effect and the content pins to the top.
              // Give the child the viewport as a minimum height so the result
              // block sits vertically centred, while still scrolling when the
              // content is taller than the screen.
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: viewport.maxHeight - 16,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ResultBadge(tierId: result.tierId, earned: earned),
                        const SizedBox(height: 24),
                        if (copy.chip != null) ...[
                          ChallengeStatusChip(
                            label: copy.chip!,
                            color: RuniacColors.textSecondary,
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          copy.title,
                          key: const ValueKey<String>(
                            'challenge-result-headline',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: RuniacColors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                            letterSpacing: -0.2,
                            decorationColor: accent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          copy.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: RuniacColors.textSecondary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        if (copy.support != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: RuniacColors.sectionSurface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              copy.support!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: RuniacColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: _ResultActions(
                earned: earned,
                onClose: onClose,
                onViewBadgeCollection: onViewBadgeCollection,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ResultVariant {
  badgeEarned,
  minimumMissed,
  deadlineFailed,
  cancelled,
  left,
}

class _ResultCopy {
  const _ResultCopy({
    required this.title,
    required this.body,
    this.chip,
    this.support,
  });

  final String? chip;
  final String title;
  final String body;
  final String? support;
}

/// The tier badge. Earned plays the full dynamic celebration ceremony
/// ([ChallengeBadgeCeremony], which itself skips to its final frame under
/// reduced motion); every other outcome renders the same PNG small and
/// desaturated via [ChallengeBadgeImage.dimmed].
class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.tierId, required this.earned});

  final ChallengeTierId tierId;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    if (earned) {
      return ChallengeBadgeCeremony(tierId: tierId);
    }
    return ChallengeBadgeImage(tierId: tierId, size: 96, dimmed: true);
  }
}

class _ResultActions extends StatelessWidget {
  const _ResultActions({
    required this.earned,
    required this.onClose,
    required this.onViewBadgeCollection,
  });

  final bool earned;
  final VoidCallback onClose;
  final VoidCallback? onViewBadgeCollection;

  @override
  Widget build(BuildContext context) {
    if (earned && onViewBadgeCollection != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: RuniacButtonStyles.primary(
                tone: RuniacButtonTone.orange,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onViewBadgeCollection,
              child: const Text(ChallengeCopy.resultViewBadgeCollection),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: RuniacButtonStyles.secondary(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onClose,
              child: const Text(ChallengeCopy.resultDone),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: RuniacButtonStyles.primary(
          minimumSize: const Size.fromHeight(52),
        ),
        onPressed: onClose,
        child: const Text(ChallengeCopy.resultDone),
      ),
    );
  }
}
