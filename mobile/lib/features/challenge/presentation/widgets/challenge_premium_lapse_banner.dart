import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/challenge_copy.dart';
import '../../domain/models/challenge_premium_hold.dart';

/// Warns a runner whose Premium subscription lapsed while they are taking part
/// in a premium-only challenge tier, and offers the paywall before the server's
/// grace window closes and removes them.
///
/// Renders nothing at all when [hold] is null, which is the case for every
/// runner whose subscription is in good standing — the overwhelmingly common
/// path — so the active-challenge surfaces are unchanged for them.
///
/// The eviction itself is entirely server-owned: this widget neither computes
/// entitlement nor decides removal, it only renders the deadline the
/// `getActiveChallenge` callable relayed and routes the CTA to the existing
/// paywall.
class ChallengePremiumLapseBanner extends StatelessWidget {
  const ChallengePremiumLapseBanner({
    required this.hold,
    this.now,
    this.onUpgrade,
    super.key,
  });

  final ChallengePremiumHold? hold;

  /// Injectable clock seam so a widget test can assert an exact remaining
  /// window. Production passes nothing and reads the wall clock.
  final DateTime? now;

  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final hold = this.hold;
    if (hold == null) {
      return const SizedBox.shrink();
    }
    final remainingLabel = hold.remainingLabel(now ?? DateTime.now());
    final body = remainingLabel == null
        ? ChallengeCopy.premiumLapseImminentBody
        : ChallengeCopy.premiumLapseBody(remainingLabel);

    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: RuniacColors.sectionSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: RuniacColors.accentOrange),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: RuniacColors.accentOrange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ChallengeCopy.premiumLapseTitle,
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onUpgrade,
                style: ElevatedButton.styleFrom(
                  backgroundColor: RuniacColors.accentOrange,
                  foregroundColor: RuniacColors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  ChallengeCopy.premiumLapseCta,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
