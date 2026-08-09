import 'package:flutter/material.dart';

/// Runner-facing display entry for one `config/featureAccess` feature key.
@immutable
class PremiumFeatureDisplay {
  const PremiumFeatureDisplay({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Display catalog for the feature keys the admin console can premium-check,
/// mirroring the console's `FEATURE_LABELS` in
/// `website/src/components/admin/PolicySettings.tsx` (labels only — the
/// console's descriptions are admin-facing and are not shown to runners).
///
/// Every key here is wired to a real gate, so an admin flipping its tier
/// changes what the app does, not just what the upsell says. `goalPlan` was
/// retired from the catalog rather than wired: the onboarding-generated plan
/// is the core beginner experience, and premium must never gate that — an
/// admin switch that could put it behind the paywall is itself the risk.
///
/// An unknown key (a backend catalog addition this build predates) falls
/// back to a humanized form of the key so it never renders blank.
const Map<String, PremiumFeatureDisplay> premiumFeatureCatalog = {
  'advancedAnalysis': PremiumFeatureDisplay(
    label: 'Advanced run analysis',
    icon: Icons.query_stats_rounded,
  ),
  'aiHomeCoach': PremiumFeatureDisplay(
    label: 'AI home coach',
    icon: Icons.tips_and_updates_rounded,
  ),
  'activityFeedback': PremiumFeatureDisplay(
    label: 'AI activity feedback',
    icon: Icons.auto_awesome_rounded,
  ),
  'workoutBriefing': PremiumFeatureDisplay(
    label: 'AI workout briefing',
    icon: Icons.auto_stories_rounded,
  ),
  'shareRouteToFeed': PremiumFeatureDisplay(
    label: 'Share route to feed',
    icon: Icons.route_rounded,
  ),
  'shareCards': PremiumFeatureDisplay(
    label: 'Share cards',
    icon: Icons.ios_share_rounded,
  ),
};

/// Static upsell teaser for the premium-only challenge tiers (100K and up).
///
/// Not a `config/featureAccess` key on purpose: challenge tier entitlement is
/// owned by `config/challengeAccess` and enforced server-side at lobby
/// creation (`PREMIUM_REQUIRED`), and the admin console deliberately keeps
/// `challenges` out of the feature-access catalog. The upsell list appends
/// this display entry statically instead of the client reading challenge
/// config — the gate ships enabled by default, so the teaser is always true.
const PremiumFeatureDisplay premiumChallengeTiersDisplay = PremiumFeatureDisplay(
  label: 'Premium challenge tiers',
  icon: Icons.emoji_events_rounded,
);

PremiumFeatureDisplay premiumFeatureDisplayFor(String key) {
  final known = premiumFeatureCatalog[key];
  if (known != null) {
    return known;
  }
  return PremiumFeatureDisplay(
    label: _humanizeFeatureKey(key),
    icon: Icons.star_rounded,
  );
}

/// `shareRouteToFeed` -> `Share route to feed`.
String _humanizeFeatureKey(String key) {
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (i == 0) {
      buffer.write(char.toUpperCase());
    } else if (isUpper) {
      buffer
        ..write(' ')
        ..write(char.toLowerCase());
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}
