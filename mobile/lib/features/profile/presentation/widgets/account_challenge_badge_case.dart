import 'package:flutter/material.dart';

import '../../../../core/assets/runiac_assets.dart';
import '../../../challenge/domain/models/challenge_enums.dart';
import '../../../challenge/presentation/widgets/challenge_badge_image.dart';

class AccountChallengeBadgeCase extends StatelessWidget {
  const AccountChallengeBadgeCase({
    this.ownedTierIds,
    this.onBadgeTap,
    super.key,
  });

  /// The tiers the viewer owns a badge for. When `null` the case renders its
  /// static preview (every badge full-colour) so existing previews/tests are
  /// unchanged. When supplied, earned tiers render full-colour and every other
  /// slot renders the SAME PNG dimmed/desaturated — one badge per tier.
  final Set<ChallengeTierId>? ownedTierIds;

  /// Invoked when an EARNED badge slot is tapped, to replay that tier's
  /// ceremony. `null` (or an unearned slot) leaves the badge non-interactive.
  final void Function(ChallengeTierId tierId)? onBadgeTap;

  static const _caseAspectRatio = 1448 / 1086;
  static const _badgeSlots = [
    _BadgeSlot(0.23, 0.235, 0.245, ChallengeTierId.k10),
    _BadgeSlot(0.5, 0.235, 0.245, ChallengeTierId.k20),
    _BadgeSlot(0.78, 0.235, 0.24, ChallengeTierId.k42),
    _BadgeSlot(0.23, 0.51, 0.245, ChallengeTierId.k100),
    _BadgeSlot(0.5, 0.51, 0.245, ChallengeTierId.k200),
    _BadgeSlot(0.78, 0.50, 0.245, ChallengeTierId.k250),
    _BadgeSlot(0.226, 0.795, 0.265, ChallengeTierId.k300),
    _BadgeSlot(0.5, 0.794, 0.27, ChallengeTierId.k500),
    _BadgeSlot(0.785, 0.8, 0.28, ChallengeTierId.k1000),
  ];

  /// The badge PNG for a slot, wrapped in a tap target only when the tier is
  /// earned AND [onBadgeTap] is wired — so replaying a ceremony is reachable
  /// from every earned badge while unearned slots stay inert. Geometry is
  /// unchanged (the wrapper fills the same slot box).
  Widget _badgeSlotChild(_BadgeSlot slot, double size) {
    final earned = _isEarned(slot.tierId);
    final badge = ChallengeBadgeImage(
      tierId: slot.tierId,
      size: size,
      dimmed: !earned,
    );
    final onTap = onBadgeTap;
    if (!earned || onTap == null) {
      return badge;
    }
    return Semantics(
      button: true,
      label: 'Replay ${challengeTierTitle(slot.tierId)} challenge celebration',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(slot.tierId),
        child: badge,
      ),
    );
  }

  bool _isEarned(ChallengeTierId tierId) {
    final owned = ownedTierIds;
    // Preview mode (null) keeps the committed all-earned look unchanged.
    return owned == null || owned.contains(tierId);
  }

  String _semanticsLabel() {
    final owned = ownedTierIds;
    if (owned == null) {
      return 'Challenge badge case preview with nine collection badges';
    }
    final earnedCount = _badgeSlots
        .where((slot) => owned.contains(slot.tierId))
        .length;
    return 'Challenge badge case, $earnedCount of ${_badgeSlots.length} '
        'badges earned';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticsLabel(),
      image: true,
      child: AspectRatio(
        aspectRatio: _caseAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      constraints.maxWidth * 0.035,
                    ),
                    child: Image.asset(
                      RuniacAssets.challengeBadgeCase,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
                for (final slot in _badgeSlots)
                  Positioned(
                    left:
                        constraints.maxWidth * slot.centerX -
                        constraints.maxWidth * slot.sizeFraction / 2,
                    top:
                        constraints.maxHeight * slot.centerY -
                        constraints.maxWidth * slot.sizeFraction / 2,
                    width: constraints.maxWidth * slot.sizeFraction,
                    height: constraints.maxWidth * slot.sizeFraction,
                    child: _badgeSlotChild(
                      slot,
                      constraints.maxWidth * slot.sizeFraction,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BadgeSlot {
  const _BadgeSlot(this.centerX, this.centerY, this.sizeFraction, this.tierId);

  final double centerX;
  final double centerY;
  final double sizeFraction;
  final ChallengeTierId tierId;
}
