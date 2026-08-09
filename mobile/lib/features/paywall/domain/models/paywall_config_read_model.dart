// Display-only paywall copy and pricing, read from the backend-owned
// `config/paywall` document.
//
// The document is written exclusively by the admin console via the Admin SDK;
// `firestore.rules` grants signed-in clients read-only access to this one
// config doc. The client only relays these values for display — tapping the
// paywall CTA never writes subscription state, and real premium enforcement
// stays server-side (Firestore Rules `isPremiumUser()` and Cloud Functions).
//
// The default values below are the canonical schema shared with the admin
// console (`website/src/lib/admin/paywall-config.ts`). The source of truth for
// keeping both sides in sync is the fixture at
// `tests/cross-system/fixtures/paywall-config-defaults.json` (repo root).

import 'package:flutter/foundation.dart';

/// One row in the paywall feature list.
@immutable
class PaywallFeatureItem {
  const PaywallFeatureItem({required this.title, this.subtitle = ''});

  final String title;

  /// Optional secondary line; empty means no subtitle row.
  final String subtitle;

  @override
  bool operator ==(Object other) {
    return other is PaywallFeatureItem &&
        other.title == title &&
        other.subtitle == subtitle;
  }

  @override
  int get hashCode => Object.hash(title, subtitle);
}

/// One selectable price card (monthly or yearly).
@immutable
class PaywallPriceOption {
  const PaywallPriceOption({
    required this.price,
    required this.period,
    this.note = '',
  });

  /// Display string with currency embedded, e.g. `S$5.99`.
  final String price;

  /// Display period label, e.g. `per month`.
  final String period;

  /// Optional savings/context note shown under the yearly card.
  final String note;

  @override
  bool operator ==(Object other) {
    return other is PaywallPriceOption &&
        other.price == price &&
        other.period == period &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(price, period, note);
}

/// Footer link visibility and labels.
@immutable
class PaywallFooterConfig {
  const PaywallFooterConfig({
    this.showTerms = true,
    this.termsLabel = 'Terms of service',
    this.showPrivacy = true,
    this.privacyLabel = 'Privacy policy',
  });

  final bool showTerms;
  final String termsLabel;
  final bool showPrivacy;
  final String privacyLabel;

  @override
  bool operator ==(Object other) {
    return other is PaywallFooterConfig &&
        other.showTerms == showTerms &&
        other.termsLabel == termsLabel &&
        other.showPrivacy == showPrivacy &&
        other.privacyLabel == privacyLabel;
  }

  @override
  int get hashCode =>
      Object.hash(showTerms, termsLabel, showPrivacy, privacyLabel);
}

/// Admin-configurable copy for the premium upsell sheet.
///
/// Every field falls back to [PaywallConfigReadModel.defaults] when the
/// document is missing or a field is malformed, so the sheet always renders
/// instantly and never blocks on the network.
@immutable
class PaywallConfigReadModel {
  const PaywallConfigReadModel({
    this.enabled = true,
    this.title = 'Runiac Premium',
    this.badge = 'More guidance',
    this.features = _defaultFeatures,
    this.monthly = _defaultMonthly,
    this.yearly = _defaultYearly,
    this.ctaLabel = 'Subscribe',
    this.footer = _defaultFooter,
    this.highlightIntervalMs = _defaultHighlightIntervalMs,
  });

  static const defaults = PaywallConfigReadModel();

  static const _defaultFeatures = <PaywallFeatureItem>[
    PaywallFeatureItem(
      title: 'Advanced run analysis',
      subtitle: 'Cadence, heart-rate and split insights',
    ),
    PaywallFeatureItem(title: 'Personal coaching summary'),
    PaywallFeatureItem(title: 'AI activity feedback'),
    PaywallFeatureItem(title: 'Enhanced post-run summaries'),
    PaywallFeatureItem(title: 'Premium sharing cards'),
  ];

  static const _defaultMonthly = PaywallPriceOption(
    price: 'S\$5.99',
    period: 'per month',
  );

  static const _defaultYearly = PaywallPriceOption(
    price: 'S\$49.99',
    period: 'per year',
    note: 'About S\$4.17/month · save about 30%',
  );

  static const _defaultFooter = PaywallFooterConfig();

  static const _defaultHighlightIntervalMs = 1800;
  static const minHighlightIntervalMs = 800;
  static const maxHighlightIntervalMs = 6000;

  /// Kill switch: when false, premium gates stop intercepting taps.
  final bool enabled;

  final String title;

  /// Small pill under the title, e.g. `More guidance`.
  final String badge;

  /// Ordered feature rows highlighted sequentially on the sheet.
  final List<PaywallFeatureItem> features;

  final PaywallPriceOption monthly;
  final PaywallPriceOption yearly;

  final String ctaLabel;
  final PaywallFooterConfig footer;

  /// Interval between sequential feature highlights, clamped to
  /// [minHighlightIntervalMs]..[maxHighlightIntervalMs] on read.
  final int highlightIntervalMs;

  /// Maps the trusted raw document, falling back per field to [defaults].
  ///
  /// A `null` map (missing document) or any malformed field resolves to the
  /// default for that field, mirroring the defaults-merge philosophy of the
  /// backend `configLoader.ts`.
  factory PaywallConfigReadModel.fromMap(Map<String, Object?>? data) {
    if (data == null) {
      return defaults;
    }
    return PaywallConfigReadModel(
      enabled: _bool(data['enabled'], defaults.enabled),
      title: _text(data['title'], defaults.title),
      badge: _textAllowEmpty(data['badge'], defaults.badge),
      features: _features(data['features']),
      monthly: _price(data['monthly'], defaults.monthly),
      yearly: _price(data['yearly'], defaults.yearly),
      ctaLabel: _text(data['ctaLabel'], defaults.ctaLabel),
      footer: _footer(data['footer']),
      highlightIntervalMs: _interval(data['highlightIntervalMs']),
    );
  }

  static bool _bool(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  /// Non-empty trimmed string, else [fallback].
  static String _text(Object? value, String fallback) {
    if (value is! String) {
      return fallback;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  /// Trimmed string where an explicit empty string is respected (used for
  /// fields the admin may intentionally clear, like the badge or notes).
  static String _textAllowEmpty(Object? value, String fallback) {
    return value is String ? value.trim() : fallback;
  }

  static List<PaywallFeatureItem> _features(Object? value) {
    if (value is! List) {
      return defaults.features;
    }
    final items = <PaywallFeatureItem>[];
    for (final entry in value) {
      if (entry is! Map) {
        continue;
      }
      final title = entry['title'];
      if (title is! String || title.trim().isEmpty) {
        continue;
      }
      final subtitle = entry['subtitle'];
      items.add(
        PaywallFeatureItem(
          title: title.trim(),
          subtitle: subtitle is String ? subtitle.trim() : '',
        ),
      );
    }
    return items.isEmpty ? defaults.features : List.unmodifiable(items);
  }

  static PaywallPriceOption _price(Object? value, PaywallPriceOption fallback) {
    if (value is! Map) {
      return fallback;
    }
    return PaywallPriceOption(
      price: _text(value['price'], fallback.price),
      period: _text(value['period'], fallback.period),
      note: _textAllowEmpty(value['note'], fallback.note),
    );
  }

  static PaywallFooterConfig _footer(Object? value) {
    const fallback = _defaultFooter;
    if (value is! Map) {
      return fallback;
    }
    return PaywallFooterConfig(
      showTerms: _bool(value['showTerms'], fallback.showTerms),
      termsLabel: _text(value['termsLabel'], fallback.termsLabel),
      showPrivacy: _bool(value['showPrivacy'], fallback.showPrivacy),
      privacyLabel: _text(value['privacyLabel'], fallback.privacyLabel),
    );
  }

  static int _interval(Object? value) {
    if (value is! num) {
      return defaults.highlightIntervalMs;
    }
    return value.toInt().clamp(minHighlightIntervalMs, maxHighlightIntervalMs);
  }

  @override
  bool operator ==(Object other) {
    return other is PaywallConfigReadModel &&
        other.enabled == enabled &&
        other.title == title &&
        other.badge == badge &&
        listEquals(other.features, features) &&
        other.monthly == monthly &&
        other.yearly == yearly &&
        other.ctaLabel == ctaLabel &&
        other.footer == footer &&
        other.highlightIntervalMs == highlightIntervalMs;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    title,
    badge,
    Object.hashAll(features),
    monthly,
    yearly,
    ctaLabel,
    footer,
    highlightIntervalMs,
  );
}
