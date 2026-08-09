import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/paywall/domain/models/feature_access_read_model.dart';
import 'package:runiac_app/features/paywall/domain/models/premium_feature_catalog.dart';

void main() {
  group('FeatureAccessReadModel.fromMap', () {
    test('missing document resolves to defaults', () {
      expect(
        FeatureAccessReadModel.fromMap(null),
        FeatureAccessReadModel.defaults,
      );
      // Mirrors functions DEFAULT_FEATURE_ACCESS_CONFIG, so an unreachable
      // document gates exactly like a freshly provisioned environment.
      expect(FeatureAccessReadModel.defaults.premiumFeatureKeys, const [
        'advancedAnalysis',
        'aiHomeCoach',
        'activityFeedback',
        'workoutBriefing',
      ]);
    });

    test('collects only enabled premium-tier features in document order', () {
      // Every default key is mentioned, so this exercises the parsing rules
      // alone with nothing left for the absent-key merge to fill in.
      final model = FeatureAccessReadModel.fromMap(const {
        'features': {
          'advancedAnalysis': {'minimumTier': 'premium', 'enabled': true},
          'goalPlan': {'minimumTier': 'basic', 'enabled': true},
          'shareCards': {'minimumTier': 'premium', 'enabled': false},
          'activityFeedback': {'minimumTier': 'premium'},
          'aiHomeCoach': {'minimumTier': 'basic', 'enabled': true},
          'workoutBriefing': {'minimumTier': 'basic', 'enabled': true},
          'shareRouteToFeed': {'minimumTier': 'basic', 'enabled': true},
        },
      });

      expect(model.premiumFeatureKeys, const [
        'advancedAnalysis',
        'activityFeedback',
      ]);
    });

    test('a key the document never mentions keeps its shipped default', () {
      // The backend loads the same document with
      // deepMerge(DEFAULT_FEATURE_ACCESS_CONFIG, stored), so an absent key is
      // still Premium server-side. Reading it as Basic here used to walk a
      // Basic runner past the paywall into a callable that then refused them.
      final model = FeatureAccessReadModel.fromMap(const {
        'features': {
          'advancedAnalysis': {'minimumTier': 'basic', 'enabled': true},
        },
      });

      expect(model.isPremiumFeature('advancedAnalysis'), isFalse);
      expect(model.isPremiumFeature('workoutBriefing'), isTrue);
      expect(model.isPremiumFeature('activityFeedback'), isTrue);
      expect(model.isPremiumFeature('aiHomeCoach'), isTrue);
      // Keys that ship as Basic are not resurrected by the merge.
      expect(model.isPremiumFeature('shareRouteToFeed'), isFalse);
      expect(model.isPremiumFeature('shareCards'), isFalse);
    });

    test('malformed features map falls back to defaults', () {
      expect(
        FeatureAccessReadModel.fromMap(const {'features': 'nope'}),
        FeatureAccessReadModel.defaults,
      );
    });

    test('an all-basic catalog is honoured, not read as never-configured', () {
      // Collapsing this into the defaults used to resurrect advancedAnalysis
      // as premium — which now would keep enforcing a lock the admin had
      // deliberately cleared. The catalog is spelled out in full, which is
      // what the console actually writes, so an explicit Basic entry is what
      // is being asserted rather than the absent-key merge.
      final model = FeatureAccessReadModel.fromMap(const {
        'features': {
          'advancedAnalysis': {'minimumTier': 'basic', 'enabled': true},
          'aiHomeCoach': {'minimumTier': 'basic', 'enabled': true},
          'activityFeedback': {'minimumTier': 'basic', 'enabled': true},
          'workoutBriefing': {'minimumTier': 'basic', 'enabled': true},
          'shareRouteToFeed': {'minimumTier': 'basic', 'enabled': true},
          'shareCards': {'minimumTier': 'basic', 'enabled': true},
        },
      });

      expect(model.premiumFeatureKeys, isEmpty);
      expect(model.isPremiumFeature('advancedAnalysis'), isFalse);
      expect(model.isPremiumFeature('shareRouteToFeed'), isFalse);
      expect(model.isPremiumFeature('workoutBriefing'), isFalse);
    });

    test('entries that cannot be parsed are skipped, not fatal', () {
      final model = FeatureAccessReadModel.fromMap(const {
        'features': {
          'broken': 'not-a-map',
          '': {'minimumTier': 'premium'},
          'shareCards': {'minimumTier': 'premium', 'enabled': true},
        },
      });

      expect(model.isPremiumFeature('shareCards'), isTrue);
      expect(model.isPremiumFeature('broken'), isFalse);
      expect(model.isPremiumFeature(''), isFalse);
      // An unparseable entry is skipped rather than counted as mentioned, so
      // the rest of the catalog still falls back to its shipped defaults.
      expect(model.premiumFeatureKeys, const [
        'shareCards',
        'advancedAnalysis',
        'aiHomeCoach',
        'activityFeedback',
        'workoutBriefing',
      ]);
    });
  });

  group('FeatureAccessReadModel.isPremiumFeature', () {
    test('reports the admin-published tier for a known key', () {
      final model = FeatureAccessReadModel.fromMap(const {
        'features': {
          'shareRouteToFeed': {'minimumTier': 'premium', 'enabled': true},
          'shareCards': {'minimumTier': 'basic', 'enabled': true},
        },
      });

      expect(model.isPremiumFeature('shareRouteToFeed'), isTrue);
      expect(model.isPremiumFeature('shareCards'), isFalse);
    });

    test('an unknown key reads as basic', () {
      expect(
        FeatureAccessReadModel.defaults.isPremiumFeature('featureFromTheFuture'),
        isFalse,
      );
    });

    test('a disabled premium entry reads as basic', () {
      // Matches the backend's isPremiumGatedFeature: `enabled` means "this
      // tier rule is active", so clearing it releases the gate on both sides.
      final model = FeatureAccessReadModel.fromMap(const {
        'features': {
          'shareCards': {'minimumTier': 'premium', 'enabled': false},
        },
      });

      expect(model.isPremiumFeature('shareCards'), isFalse);
    });
  });

  group('premiumFeatureDisplayFor', () {
    test('known keys use the admin catalog labels', () {
      // Both keys are ones whose catalog label differs from what the humanize
      // fallback would produce ('Advanced analysis', 'Ai home coach'), so this
      // proves the catalog lookup rather than passing either way. It used to
      // assert 'healthWorkoutImport', which 65b41c49 had already removed from
      // the catalog — the humanize fallback happened to return the same string,
      // so the test kept passing while covering nothing.
      expect(
        premiumFeatureDisplayFor('advancedAnalysis').label,
        'Advanced run analysis',
      );
      expect(
        premiumFeatureDisplayFor('aiHomeCoach').label,
        'AI home coach',
      );
    });

    test('unknown keys humanize instead of rendering blank', () {
      expect(
        premiumFeatureDisplayFor('someFutureFeature').label,
        'Some future feature',
      );
    });
  });
}
