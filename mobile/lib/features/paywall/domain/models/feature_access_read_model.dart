// Client view of the backend-owned `config/featureAccess` document: which
// feature keys the Platform Administrator has checked as premium-tier.
//
// Two consumers:
//   - the You-tab upsell section lists [premiumFeatureKeys];
//   - the paywall gates in `premium_gate.dart` ask [isPremiumFeature] whether
//     a given surface is admin-gated before intercepting a tap.
//
// The gate this model drives is a UX layer, never the enforcement: features
// with a server surface (`shareRouteToFeed`, `activityFeedback`,
// `aiHomeCoach`, `workoutBriefing`) are re-checked against the same document
// inside Cloud Functions, which is what actually denies a Basic runner.

import 'package:flutter/foundation.dart';

/// Premium-checked feature keys from `config/featureAccess`, in the
/// document's iteration order.
@immutable
class FeatureAccessReadModel {
  const FeatureAccessReadModel({this.premiumFeatureKeys = _defaultKeys});

  static const defaults = FeatureAccessReadModel();

  /// The keys that are premium in every environment's shipped defaults,
  /// mirroring functions `DEFAULT_FEATURE_ACCESS_CONFIG` (and the admin
  /// console's copy of it) in document order. Used whenever the document has
  /// not been read yet or is unreachable, so an offline gate behaves like a
  /// freshly provisioned environment rather than guessing.
  static const _defaultKeys = <String>[
    'advancedAnalysis',
    'aiHomeCoach',
    'activityFeedback',
    'workoutBriefing',
  ];

  /// Feature keys whose stored entry is `minimumTier == 'premium'` and
  /// `enabled == true` (absent `enabled` counts as enabled, matching the
  /// backend loader's defaults-merge).
  final List<String> premiumFeatureKeys;

  /// Whether [featureKey] is admin-gated behind Premium.
  ///
  /// An unknown key reads as Basic: a build that predates a backend catalog
  /// addition must not invent a gate for a feature it cannot describe.
  bool isPremiumFeature(String featureKey) =>
      premiumFeatureKeys.contains(featureKey);

  /// Maps the trusted raw document. A missing document or a malformed
  /// `features` map resolves to [defaults] (the never-configured state).
  ///
  /// A well-formed map with zero premium entries is a legitimate "every
  /// feature is Basic" state and is honoured as such — collapsing it into
  /// [defaults] used to resurrect `advancedAnalysis` as premium, which both
  /// listed a paid feature the admin had opened and (now that the gates read
  /// this model) would have kept enforcing a lock the console had cleared.
  /// Mirrors `CharacterAccessReadModel.fromMap`, which already honours an
  /// empty premium list.
  ///
  /// A key the document does not mention at all is a different case from one
  /// it sets to Basic, and the two must not be conflated: the backend loads
  /// this document with `deepMerge(DEFAULT_FEATURE_ACCESS_CONFIG, stored)`, so
  /// an absent key keeps the shipped default and is still denied server-side.
  /// Reading it as Basic here let a Basic runner past the paywall into a
  /// callable that then refused them — the gate showed no paywall and the
  /// feature surfaced its premium-denial copy instead. Absent premium
  /// defaults are therefore merged back in, while an explicit Basic entry
  /// still wins, which is what keeps the cleared-lock fix above intact.
  factory FeatureAccessReadModel.fromMap(Map<String, Object?>? data) {
    final features = data?['features'];
    if (features is! Map) {
      return defaults;
    }
    final keys = <String>[];
    final mentioned = <String>{};
    for (final entry in features.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.trim().isEmpty || value is! Map) {
        continue;
      }
      mentioned.add(key.trim());
      if (value['minimumTier'] != 'premium') {
        continue;
      }
      final enabled = value['enabled'];
      if (enabled is bool && !enabled) {
        continue;
      }
      keys.add(key.trim());
    }
    for (final key in _defaultKeys) {
      if (!mentioned.contains(key)) {
        keys.add(key);
      }
    }
    return FeatureAccessReadModel(premiumFeatureKeys: List.unmodifiable(keys));
  }

  @override
  bool operator ==(Object other) {
    return other is FeatureAccessReadModel &&
        listEquals(other.premiumFeatureKeys, premiumFeatureKeys);
  }

  @override
  int get hashCode => Object.hashAll(premiumFeatureKeys);
}
