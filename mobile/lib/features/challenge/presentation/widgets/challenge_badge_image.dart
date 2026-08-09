import 'package:flutter/material.dart';

import '../../../../core/assets/runiac_assets.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../domain/models/challenge_enums.dart';

/// Maps a tier to its user-created badge PNG asset. Every Challenge badge
/// rendering MUST route through here — never an icon, emoji, or generated art.
String challengeBadgeAsset(ChallengeTierId tierId) {
  return switch (tierId) {
    ChallengeTierId.k10 => RuniacAssets.challengeBadge10k,
    ChallengeTierId.k20 => RuniacAssets.challengeBadge20k,
    ChallengeTierId.k42 => RuniacAssets.challengeBadge42kMarathon,
    ChallengeTierId.k100 => RuniacAssets.challengeBadge100k,
    ChallengeTierId.k200 => RuniacAssets.challengeBadge200k,
    ChallengeTierId.k250 => RuniacAssets.challengeBadge250k,
    ChallengeTierId.k300 => RuniacAssets.challengeBadge300k,
    ChallengeTierId.k500 => RuniacAssets.challengeBadge500k,
    ChallengeTierId.k1000 => RuniacAssets.challengeBadge1000k,
  };
}

/// The tier's short display title (e.g. `10K`), taken verbatim from the backend
/// tier id wire value — never re-derived from a target metre figure.
String challengeTierTitle(ChallengeTierId tierId) => tierId.wireValue;

/// Renders a tier badge PNG at [size]. When [dimmed] (unearned/locked state)
/// the same asset is desaturated and faded — never swapped for other art.
class ChallengeBadgeImage extends StatelessWidget {
  const ChallengeBadgeImage({
    required this.tierId,
    required this.size,
    this.dimmed = false,
    super.key,
  });

  final ChallengeTierId tierId;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      challengeBadgeAsset(tierId),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
    if (!dimmed) {
      return ExcludeSemantics(child: image);
    }
    return ExcludeSemantics(
      child: Opacity(
        opacity: 0.45,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
          child: image,
        ),
      ),
    );
  }
}

/// A tier badge with the premium-lock treatment: when [locked] the badge PNG
/// renders through the [ChallengeBadgeImage] dimmed (desaturate + fade) mode
/// with a lock roundel overlaid at its centre. The badge asset itself is
/// always shown — never swapped for other art. Display-only: the backend
/// `PREMIUM_REQUIRED` gate on lobby creation is the enforcement.
class ChallengeLockableBadge extends StatelessWidget {
  const ChallengeLockableBadge({
    required this.tierId,
    required this.size,
    required this.locked,
    super.key,
  });

  final ChallengeTierId tierId;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final badge = ChallengeBadgeImage(tierId: tierId, size: size, dimmed: locked);
    if (!locked) {
      return badge;
    }
    final lockSize = (size * 0.22).clamp(14.0, 24.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          badge,
          Container(
            key: ValueKey<String>('challenge-tier-lock-${tierId.wireValue}'),
            padding: EdgeInsets.all(lockSize * 0.35),
            decoration: BoxDecoration(
              color: RuniacColors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(color: RuniacColors.cardBorder),
            ),
            child: Icon(
              Icons.lock_rounded,
              size: lockSize,
              color: RuniacColors.accentOrange,
            ),
          ),
        ],
      ),
    );
  }
}
