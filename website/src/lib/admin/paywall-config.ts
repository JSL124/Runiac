// Canonical schema, defaults, deep-merge, and validation for the mobile app's
// premium paywall sheet copy (config/paywall).
//
// This is a pure module (no Firebase / server imports) modeled on
// src/lib/site-pricing.ts. It is deliberately NOT part of
// src/lib/admin/config-validation.ts: that file is drift-checked block-for-block
// against functions/src/config/configLoader.ts, and Cloud Functions do not
// consume config/paywall — only the Flutter app (read-only, signed-in) and this
// console (Admin SDK writes) do.
//
// The mobile mirror of this schema is
// mobile/lib/features/paywall/domain/models/paywall_config_read_model.dart
// in the app repo; the shared source of truth for the default document is the
// fixture tests/cross-system/fixtures/paywall-config-defaults.json there.
//
// DEFAULT_PAYWALL_CONFIG intentionally mirrors the marketing site's premium
// prices (DEFAULT_SITE_PRICING in src/lib/site-pricing.ts) so the app and the
// website never quote different amounts by default.

export type PaywallFeature = {
  title: string;
  /** Optional secondary line; empty string means no subtitle row. */
  subtitle: string;
};

export type PaywallPrice = {
  /** Display string with currency embedded, e.g. "S$5.99". */
  price: string;
  /** Display period label, e.g. "per month". */
  period: string;
  /** Optional savings/context note (shown under the yearly card). */
  note: string;
};

export type PaywallFooter = {
  showTerms: boolean;
  termsLabel: string;
  showPrivacy: boolean;
  privacyLabel: string;
};

export type PaywallConfig = {
  /** Kill switch: when false the app's premium gates stop intercepting taps. */
  enabled: boolean;
  title: string;
  /** Small pill under the title; empty string hides it. */
  badge: string;
  /** Ordered feature rows, highlighted sequentially on the sheet (1–12). */
  features: PaywallFeature[];
  monthly: PaywallPrice;
  yearly: PaywallPrice;
  ctaLabel: string;
  footer: PaywallFooter;
  /** Interval between sequential feature highlights, ms (800–6000). */
  highlightIntervalMs: number;
  /** Server-assigned save counter (bumped by saveAdminConfig). */
  version?: number;
};

export const PAYWALL_HIGHLIGHT_INTERVAL_MIN_MS = 800;
export const PAYWALL_HIGHLIGHT_INTERVAL_MAX_MS = 6000;
export const PAYWALL_MAX_FEATURES = 12;

export const DEFAULT_PAYWALL_CONFIG: PaywallConfig = {
  enabled: true,
  title: "Runiac Premium",
  badge: "More guidance",
  features: [
    {
      title: "Advanced run analysis",
      subtitle: "Cadence, heart-rate and split insights",
    },
    { title: "Personal coaching summary", subtitle: "" },
    { title: "AI activity feedback", subtitle: "" },
    { title: "Enhanced post-run summaries", subtitle: "" },
    { title: "Premium sharing cards", subtitle: "" },
  ],
  monthly: { price: "S$5.99", period: "per month", note: "" },
  yearly: {
    price: "S$49.99",
    period: "per year",
    note: "About S$4.17/month · save about 30%",
  },
  ctaLabel: "Subscribe",
  footer: {
    showTerms: true,
    termsLabel: "Terms of service",
    showPrivacy: true,
    privacyLabel: "Privacy policy",
  },
  highlightIntervalMs: 1800,
};

// --- deep-merge over defaults ------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeBoolean(raw: unknown, fallback: boolean): boolean {
  return typeof raw === "boolean" ? raw : fallback;
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

function mergePrice(raw: unknown, fallback: PaywallPrice): PaywallPrice {
  const source = isRecord(raw) ? raw : {};
  return {
    price: mergeString(source.price, fallback.price),
    period: mergeString(source.period, fallback.period),
    note: mergeString(source.note, fallback.note),
  };
}

function mergeFooter(raw: unknown, fallback: PaywallFooter): PaywallFooter {
  const source = isRecord(raw) ? raw : {};
  return {
    showTerms: mergeBoolean(source.showTerms, fallback.showTerms),
    termsLabel: mergeString(source.termsLabel, fallback.termsLabel),
    showPrivacy: mergeBoolean(source.showPrivacy, fallback.showPrivacy),
    privacyLabel: mergeString(source.privacyLabel, fallback.privacyLabel),
  };
}

// A feature list is used only when it is an array with at least one entry
// carrying a non-empty title, mirroring the mobile reader's coercion; invalid
// entries are dropped rather than failing the whole list.
function mergeFeatures(raw: unknown, fallback: PaywallFeature[]): PaywallFeature[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }
  const items: PaywallFeature[] = [];
  for (const entry of raw) {
    if (!isRecord(entry) || typeof entry.title !== "string") {
      continue;
    }
    const title = entry.title.trim();
    if (title.length === 0) {
      continue;
    }
    items.push({
      title,
      subtitle: typeof entry.subtitle === "string" ? entry.subtitle.trim() : "",
    });
  }
  return items.length > 0 ? items : fallback;
}

function mergeInterval(raw: unknown, fallback: number): number {
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    return fallback;
  }
  return Math.min(
    PAYWALL_HIGHLIGHT_INTERVAL_MAX_MS,
    Math.max(PAYWALL_HIGHLIGHT_INTERVAL_MIN_MS, Math.trunc(raw)),
  );
}

// Per-field deep-merge of an arbitrary stored value over
// DEFAULT_PAYWALL_CONFIG, so a partially seeded or malformed document can
// never blank out the paywall sheet.
export function mergePaywallConfig(raw: unknown): PaywallConfig {
  const source = isRecord(raw) ? raw : {};
  const merged: PaywallConfig = {
    enabled: mergeBoolean(source.enabled, DEFAULT_PAYWALL_CONFIG.enabled),
    title: mergeString(source.title, DEFAULT_PAYWALL_CONFIG.title),
    badge: mergeString(source.badge, DEFAULT_PAYWALL_CONFIG.badge),
    features: mergeFeatures(source.features, DEFAULT_PAYWALL_CONFIG.features),
    monthly: mergePrice(source.monthly, DEFAULT_PAYWALL_CONFIG.monthly),
    yearly: mergePrice(source.yearly, DEFAULT_PAYWALL_CONFIG.yearly),
    ctaLabel: mergeString(source.ctaLabel, DEFAULT_PAYWALL_CONFIG.ctaLabel),
    footer: mergeFooter(source.footer, DEFAULT_PAYWALL_CONFIG.footer),
    highlightIntervalMs: mergeInterval(
      source.highlightIntervalMs,
      DEFAULT_PAYWALL_CONFIG.highlightIntervalMs,
    ),
  };
  if (typeof source.version === "number" && Number.isFinite(source.version)) {
    merged.version = source.version;
  }
  return merged;
}

// --- validation --------------------------------------------------------------

export function validatePaywallConfig(
  candidate: PaywallConfig,
): { valid: boolean; errors: readonly string[] } {
  const errors: string[] = [];

  if (typeof candidate.enabled !== "boolean") {
    errors.push("Enabled must be on or off.");
  }
  if (typeof candidate.title !== "string" || candidate.title.trim().length === 0) {
    errors.push("Title must not be empty.");
  }
  if (typeof candidate.badge !== "string") {
    errors.push("Badge must be text (it may be empty to hide the pill).");
  }
  if (!Array.isArray(candidate.features) || candidate.features.length === 0) {
    errors.push("At least one feature row is required.");
  } else {
    if (candidate.features.length > PAYWALL_MAX_FEATURES) {
      errors.push(`At most ${PAYWALL_MAX_FEATURES} feature rows are allowed.`);
    }
    candidate.features.forEach((feature, index) => {
      if (typeof feature.title !== "string" || feature.title.trim().length === 0) {
        errors.push(`Feature ${index + 1} needs a title.`);
      }
      if (typeof feature.subtitle !== "string") {
        errors.push(`Feature ${index + 1} subtitle must be text (may be empty).`);
      }
    });
  }
  for (const [label, price] of [
    ["Monthly", candidate.monthly],
    ["Yearly", candidate.yearly],
  ] as const) {
    if (typeof price.price !== "string" || price.price.trim().length === 0) {
      errors.push(`${label} price must not be empty.`);
    }
    if (typeof price.period !== "string" || price.period.trim().length === 0) {
      errors.push(`${label} period label must not be empty.`);
    }
    if (typeof price.note !== "string") {
      errors.push(`${label} note must be text (it may be empty).`);
    }
  }
  if (
    typeof candidate.ctaLabel !== "string" ||
    candidate.ctaLabel.trim().length === 0
  ) {
    errors.push("The subscribe button label must not be empty.");
  }
  const footer = candidate.footer;
  if (!footer || typeof footer.showTerms !== "boolean" || typeof footer.showPrivacy !== "boolean") {
    errors.push("Footer link toggles must be on or off.");
  } else {
    if (footer.showTerms && footer.termsLabel.trim().length === 0) {
      errors.push("The terms link label must not be empty while it is shown.");
    }
    if (footer.showPrivacy && footer.privacyLabel.trim().length === 0) {
      errors.push("The privacy link label must not be empty while it is shown.");
    }
  }
  if (
    !Number.isInteger(candidate.highlightIntervalMs) ||
    candidate.highlightIntervalMs < PAYWALL_HIGHLIGHT_INTERVAL_MIN_MS ||
    candidate.highlightIntervalMs > PAYWALL_HIGHLIGHT_INTERVAL_MAX_MS
  ) {
    errors.push(
      `Highlight interval must be a whole number between ${PAYWALL_HIGHLIGHT_INTERVAL_MIN_MS} and ${PAYWALL_HIGHLIGHT_INTERVAL_MAX_MS} ms.`,
    );
  }

  return { valid: errors.length === 0, errors };
}
