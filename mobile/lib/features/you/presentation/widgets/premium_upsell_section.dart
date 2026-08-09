import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../paywall/domain/models/feature_access_read_model.dart';
import '../../../paywall/domain/models/premium_feature_catalog.dart';
import '../../../paywall/presentation/current_session_feature_access.dart';
import '../../../paywall/presentation/premium_gate.dart';
import '../../../paywall/presentation/premium_paywall_sheet.dart';
import 'you_surface_primitives.dart';

/// Strava-style premium upsell for the You > Plans surface, shown only to
/// Basic runners: lock chip, headline, and a card listing the features the
/// Platform Administrator has premium-checked in `config/featureAccess`,
/// over a warm radial glow. Tapping anywhere opens the paywall sheet.
///
/// Rendering is gated by [watchShouldShowPaywall]: a Premium runner (or an
/// unresolved account, or the admin kill switch) collapses this to nothing,
/// and the InheritedNotifier dependency makes it appear/disappear live when
/// the tier changes. The feature rows play a one-shot staggered entrance
/// (finite controller — `pumpAndSettle` always settles); reduced motion
/// renders them statically.
class PremiumUpsellSection extends StatelessWidget {
  const PremiumUpsellSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!watchShouldShowPaywall(context)) {
      return const SizedBox.shrink();
    }
    // Idempotent one-shot kick; the scope notifies and this rebuilds when
    // the admin-published checklist arrives.
    final featureAccessStore = FeatureAccessScope.maybeOf(context);
    featureAccessStore?.ensureLoaded();
    final premiumFeatureKeys =
        (featureAccessStore?.featureAccess ?? FeatureAccessReadModel.defaults)
            .premiumFeatureKeys;

    return Semantics(
      button: true,
      label: 'Unlock Runiac Premium',
      child: GestureDetector(
        key: const Key('premium-upsell-section'),
        behavior: HitTestBehavior.opaque,
        onTap: () => PremiumPaywallSheet.show(context),
        child: Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: _UpsellGlow())),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: RuniacColors.accentOrange.withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 26,
                      color: RuniacColors.accentOrange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Unlock your full potential',
                    textAlign: TextAlign.center,
                    style: YouTextStyles.section,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Go deeper on every run with Runiac Premium.',
                    textAlign: TextAlign.center,
                    style: YouTextStyles.body,
                  ),
                  const SizedBox(height: 16),
                  _PremiumFeatureListCard(featureKeys: premiumFeatureKeys),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Warm orange radial wash behind the section — the challenge-ceremony glow
/// (`challenge_result_ceremony.dart`) with its alphas cut down for the white
/// Plans background.
class _UpsellGlow extends StatelessWidget {
  const _UpsellGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.55),
          radius: 0.85,
          colors: [Color(0x2EFC6818), Color(0x1AFFC24B), Color(0x00FFFFFF)],
          stops: [0.0, 0.4, 1.0],
        ),
      ),
    );
  }
}

/// White card listing the admin's premium-checked features with a staggered
/// fade-and-rise entrance. The stagger replays when the checklist itself
/// changes (e.g. the `config/featureAccess` document arriving over the
/// built-in default), so the list always settles into place gracefully.
class _PremiumFeatureListCard extends StatefulWidget {
  const _PremiumFeatureListCard({required this.featureKeys});

  final List<String> featureKeys;

  @override
  State<_PremiumFeatureListCard> createState() =>
      _PremiumFeatureListCardState();
}

class _PremiumFeatureListCardState extends State<_PremiumFeatureListCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  var _reduceMotion = false;

  static const _perRowMs = 90;
  static const _rowFadeMs = 380;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      // +1 row: the static premium-challenge-tiers teaser appended in build.
      duration: _entranceDurationFor(widget.featureKeys.length + 1),
    );
  }

  Duration _entranceDurationFor(int rowCount) {
    return Duration(
      milliseconds: _rowFadeMs + _perRowMs * (rowCount - 1).clamp(0, 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
    }
    // One-shot entrance; under reduced motion the rows render settled.
    if (_reduceMotion) {
      _entrance.value = 1;
    } else if (!_entrance.isAnimating && _entrance.value == 0) {
      _entrance.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _PremiumFeatureListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.featureKeys, widget.featureKeys)) {
      _entrance.duration = _entranceDurationFor(widget.featureKeys.length + 1);
      if (_reduceMotion) {
        _entrance.value = 1;
      } else {
        _entrance.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Per-row animation: rows fade in and rise one after another.
  Animation<double> _rowAnimation(int index) {
    final totalMs = _entrance.duration!.inMilliseconds;
    final startMs = _perRowMs * index;
    final start = (startMs / totalMs).clamp(0.0, 1.0);
    final end = ((startMs + _rowFadeMs) / totalMs).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.featureKeys;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(youCardRadius),
        border: Border.all(color: RuniacColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: RuniacColors.softCardShadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  "What's included with Premium",
                  style: YouTextStyles.cardTitle,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: RuniacColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < keys.length; i++)
            _StaggeredFeatureRow(
              key: Key('premium-upsell-feature-${keys[i]}'),
              animation: _rowAnimation(i),
              display: premiumFeatureDisplayFor(keys[i]),
            ),
          // Static teaser appended after the admin-driven rows: challenge tier
          // entitlement lives in config/challengeAccess (server-enforced,
          // enabled by default), not the feature-access catalog — see
          // premiumChallengeTiersDisplay.
          _StaggeredFeatureRow(
            key: const Key('premium-upsell-feature-challengeTiers'),
            animation: _rowAnimation(keys.length),
            display: premiumChallengeTiersDisplay,
          ),
        ],
      ),
    );
  }
}

class _StaggeredFeatureRow extends StatelessWidget {
  const _StaggeredFeatureRow({
    required this.animation,
    required this.display,
    super.key,
  });

  final Animation<double> animation;
  final PremiumFeatureDisplay display;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RuniacColors.accentOrange.withValues(alpha: 0.12),
              ),
              child: Icon(
                display.icon,
                size: 18,
                color: RuniacColors.accentOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                display.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: RuniacColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: RuniacColors.textSecondary.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
