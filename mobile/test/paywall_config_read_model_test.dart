import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/paywall/domain/models/paywall_config_read_model.dart';

void main() {
  group('PaywallConfigReadModel.fromMap', () {
    test('missing document resolves to defaults', () {
      expect(
        PaywallConfigReadModel.fromMap(null),
        PaywallConfigReadModel.defaults,
      );
    });

    test('empty document resolves to defaults', () {
      expect(
        PaywallConfigReadModel.fromMap(const {}),
        PaywallConfigReadModel.defaults,
      );
    });

    test('valid document maps every field through', () {
      final config = PaywallConfigReadModel.fromMap(const {
        'enabled': false,
        'title': 'Premium TEST',
        'badge': 'Badge TEST',
        'features': [
          {'title': 'Feature A', 'subtitle': 'Sub A'},
          {'title': 'Feature B'},
        ],
        'monthly': {'price': r'S$1.99', 'period': 'per month'},
        'yearly': {
          'price': r'S$19.99',
          'period': 'per year',
          'note': 'Save lots',
        },
        'ctaLabel': 'Join now',
        'footer': {
          'showTerms': false,
          'termsLabel': 'Terms',
          'showPrivacy': true,
          'privacyLabel': 'Privacy',
        },
        'highlightIntervalMs': 2500,
      });

      expect(config.enabled, isFalse);
      expect(config.title, 'Premium TEST');
      expect(config.badge, 'Badge TEST');
      expect(config.features, const [
        PaywallFeatureItem(title: 'Feature A', subtitle: 'Sub A'),
        PaywallFeatureItem(title: 'Feature B'),
      ]);
      expect(config.monthly.price, r'S$1.99');
      expect(config.yearly.note, 'Save lots');
      expect(config.ctaLabel, 'Join now');
      expect(config.footer.showTerms, isFalse);
      expect(config.footer.privacyLabel, 'Privacy');
      expect(config.highlightIntervalMs, 2500);
    });

    test('wrong-typed fields each fall back to their default', () {
      final config = PaywallConfigReadModel.fromMap(const {
        'enabled': 'yes',
        'title': 42,
        'features': 'not-a-list',
        'monthly': 'not-a-map',
        'ctaLabel': '   ',
        'footer': 3,
        'highlightIntervalMs': 'soon',
      });

      expect(config, PaywallConfigReadModel.defaults);
    });

    test('malformed feature entries are skipped, empty list falls back', () {
      final skipped = PaywallConfigReadModel.fromMap(const {
        'features': [
          'nope',
          {'title': ''},
          {'subtitle': 'orphan'},
          {'title': '  Kept  ', 'subtitle': 7},
        ],
      });
      expect(skipped.features, const [PaywallFeatureItem(title: 'Kept')]);

      final emptied = PaywallConfigReadModel.fromMap(const {
        'features': [
          {'title': ''},
        ],
      });
      expect(emptied.features, PaywallConfigReadModel.defaults.features);
    });

    test('highlight interval clamps to the allowed range', () {
      expect(
        PaywallConfigReadModel.fromMap(const {
          'highlightIntervalMs': 10,
        }).highlightIntervalMs,
        PaywallConfigReadModel.minHighlightIntervalMs,
      );
      expect(
        PaywallConfigReadModel.fromMap(const {
          'highlightIntervalMs': 99999,
        }).highlightIntervalMs,
        PaywallConfigReadModel.maxHighlightIntervalMs,
      );
      expect(
        PaywallConfigReadModel.fromMap(const {
          'highlightIntervalMs': -5,
        }).highlightIntervalMs,
        PaywallConfigReadModel.minHighlightIntervalMs,
      );
    });

    test('explicitly cleared badge and note stay empty', () {
      final config = PaywallConfigReadModel.fromMap(const {
        'badge': '',
        'yearly': {'note': ''},
      });
      expect(config.badge, isEmpty);
      expect(config.yearly.note, isEmpty);
    });
  });
}
