import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/paywall/domain/models/paywall_config_read_model.dart';

/// The canonical `config/paywall` default document shared with the admin
/// console (`website/src/lib/admin/paywall-config.ts`, checked by
/// `tests/cross-system/paywall-config-drift.mjs`). This test pins the Dart
/// defaults to the same fixture so the app and the console can never render
/// different fallback paywalls.
const _fixturePath =
    '../tests/cross-system/fixtures/paywall-config-defaults.json';

Map<String, Object?> _serialize(PaywallConfigReadModel config) {
  return {
    'enabled': config.enabled,
    'title': config.title,
    'badge': config.badge,
    'features': [
      for (final feature in config.features)
        {'title': feature.title, 'subtitle': feature.subtitle},
    ],
    'monthly': {
      'price': config.monthly.price,
      'period': config.monthly.period,
      'note': config.monthly.note,
    },
    'yearly': {
      'price': config.yearly.price,
      'period': config.yearly.period,
      'note': config.yearly.note,
    },
    'ctaLabel': config.ctaLabel,
    'footer': {
      'showTerms': config.footer.showTerms,
      'termsLabel': config.footer.termsLabel,
      'showPrivacy': config.footer.showPrivacy,
      'privacyLabel': config.footer.privacyLabel,
    },
    'highlightIntervalMs': config.highlightIntervalMs,
  };
}

void main() {
  test('Dart paywall defaults equal the shared cross-system fixture', () {
    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync())
            as Map<String, dynamic>;

    expect(_serialize(PaywallConfigReadModel.defaults), fixture);
  });

  test('the fixture itself round-trips through the reader unchanged', () {
    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync())
            as Map<String, dynamic>;

    final parsed = PaywallConfigReadModel.fromMap(
      Map<String, Object?>.from(fixture),
    );

    expect(parsed, PaywallConfigReadModel.defaults);
  });
}
