// Canonical schema, defaults, deep-merge, and validation for the marketing
// pricing page's admin-editable content (config/siteContent.pricing).
//
// This is a pure module (no Firebase / server imports) so it can be shared by
// the marketing render layer (src/lib/site-content.ts, PricingSection.tsx), the
// admin console model/mapping (src/lib/admin/*), and the save action's
// validator (src/lib/actions/admin.ts) without pulling in the Admin SDK.
//
// DEFAULT_SITE_PRICING equals the literals that used to be hard-coded in
// PricingSection.tsx, so an unseeded (or partially seeded, or malformed)
// config/siteContent renders exactly the same page it did before — the
// per-field deep-merge in mergeSitePricing() falls back to these defaults for
// every field the admin has not (validly) set.

export type SitePricingTier = {
  price: string;
  period: string;
  note: string;
};

export type SitePricing = {
  free: {
    badge: string;
    title: string;
    subtitle: string;
    price: string;
    priceNote: string;
    features: string[];
  };
  premium: {
    badge: string;
    title: string;
    subtitle: string;
    premiumPrice: {
      monthly: SitePricingTier;
      annual: SitePricingTier;
    };
    ctaLabel: string;
    features: string[];
  };
};

export const DEFAULT_SITE_PRICING: SitePricing = {
  free: {
    badge: "Core",
    title: "Free",
    subtitle: "Core running + habit formation experience",
    price: "S$0",
    priceNote: "start building consistency",
    features: [
      "GPS run tracking",
      "Basic running analysis",
      "Weekly running plan",
      "Running and rest reminders",
      "Streak tracking",
      "XP progression",
      "Fair leaderboard participation",
    ],
  },
  premium: {
    badge: "More guidance",
    title: "Premium",
    subtitle: "Deeper guidance, richer feedback, and milestone preparation",
    premiumPrice: {
      monthly: {
        price: "S$5.99",
        period: "/ month",
        note: "Annual option: S$49.99/year",
      },
      annual: {
        price: "S$49.99",
        period: "/ year",
        note: "About S$4.17/month · save about 30%",
      },
    },
    ctaLabel: "Get Premium Plan",
    features: [
      "Advanced progress insights",
      "Goal preparation mode",
      "Enhanced post-run summaries",
      "Advanced route filters",
      "Premium sharing cards",
      "Visual profile and status features",
    ],
  },
};

// --- deep-merge over defaults ------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// A string field is used only when it is actually a string; anything else
// (missing, null, number, object) falls back to the default so a malformed
// document can never blank out a label.
function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

// A feature list is used only when it is an array whose every entry is a
// string; otherwise it falls back to the default list. An intentionally empty
// (but valid) array is respected so an admin can clear a tier's features.
function mergeStringList(raw: unknown, fallback: string[]): string[] {
  if (Array.isArray(raw) && raw.every((item) => typeof item === "string")) {
    return raw as string[];
  }
  return fallback;
}

function mergeTier(raw: unknown, fallback: SitePricingTier): SitePricingTier {
  const source = isRecord(raw) ? raw : {};
  return {
    price: mergeString(source.price, fallback.price),
    period: mergeString(source.period, fallback.period),
    note: mergeString(source.note, fallback.note),
  };
}

// Per-field deep-merge of an arbitrary stored value over DEFAULT_SITE_PRICING.
// Every missing or wrong-typed field degrades to its default, so the result is
// always a fully-populated, render-safe SitePricing.
export function mergeSitePricing(raw: unknown): SitePricing {
  const source = isRecord(raw) ? raw : {};
  const free = isRecord(source.free) ? source.free : {};
  const premium = isRecord(source.premium) ? source.premium : {};
  const premiumPrice = isRecord(premium.premiumPrice)
    ? premium.premiumPrice
    : {};

  const defaults = DEFAULT_SITE_PRICING;

  return {
    free: {
      badge: mergeString(free.badge, defaults.free.badge),
      title: mergeString(free.title, defaults.free.title),
      subtitle: mergeString(free.subtitle, defaults.free.subtitle),
      price: mergeString(free.price, defaults.free.price),
      priceNote: mergeString(free.priceNote, defaults.free.priceNote),
      features: mergeStringList(free.features, defaults.free.features),
    },
    premium: {
      badge: mergeString(premium.badge, defaults.premium.badge),
      title: mergeString(premium.title, defaults.premium.title),
      subtitle: mergeString(premium.subtitle, defaults.premium.subtitle),
      premiumPrice: {
        monthly: mergeTier(
          premiumPrice.monthly,
          defaults.premium.premiumPrice.monthly,
        ),
        annual: mergeTier(
          premiumPrice.annual,
          defaults.premium.premiumPrice.annual,
        ),
      },
      ctaLabel: mergeString(premium.ctaLabel, defaults.premium.ctaLabel),
      features: mergeStringList(
        premium.features,
        defaults.premium.features,
      ),
    },
  };
}

// --- validation (used by the admin save action) ------------------------------
//
// The marketing site always self-heals via mergeSitePricing(), but the save
// path validates the admin-submitted shape up front so a bad write is rejected
// with a clear message instead of being silently normalized away. Kept
// deliberately light: this is marketing copy, not backend-owned state, so it
// only enforces that required labels are non-empty strings and feature entries
// are non-empty strings.

export type SitePricingValidationResult = {
  valid: boolean;
  errors: string[];
};

function requireNonEmptyString(
  errors: string[],
  raw: unknown,
  label: string,
): void {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    errors.push(`${label} must not be empty.`);
  }
}

function validateFeatures(
  errors: string[],
  raw: unknown,
  label: string,
): void {
  if (!Array.isArray(raw)) {
    errors.push(`${label} must be a list.`);
    return;
  }
  raw.forEach((item, index) => {
    if (typeof item !== "string" || item.trim().length === 0) {
      errors.push(`${label} item ${index + 1} must not be empty.`);
    }
  });
}

function validateTier(errors: string[], raw: unknown, label: string): void {
  if (!isRecord(raw)) {
    errors.push(`${label} is missing.`);
    return;
  }
  requireNonEmptyString(errors, raw.price, `${label} price`);
  requireNonEmptyString(errors, raw.period, `${label} period`);
  requireNonEmptyString(errors, raw.note, `${label} note`);
}

export function validateSitePricing(raw: unknown): SitePricingValidationResult {
  const errors: string[] = [];

  if (!isRecord(raw)) {
    return { valid: false, errors: ["Pricing content is missing."] };
  }

  const free = isRecord(raw.free) ? raw.free : null;
  const premium = isRecord(raw.premium) ? raw.premium : null;

  if (!free) {
    errors.push("Free tier content is missing.");
  } else {
    requireNonEmptyString(errors, free.badge, "Free tier badge");
    requireNonEmptyString(errors, free.title, "Free tier title");
    requireNonEmptyString(errors, free.subtitle, "Free tier subtitle");
    requireNonEmptyString(errors, free.price, "Free tier price");
    requireNonEmptyString(errors, free.priceNote, "Free tier price note");
    validateFeatures(errors, free.features, "Free tier features");
  }

  if (!premium) {
    errors.push("Premium tier content is missing.");
  } else {
    requireNonEmptyString(errors, premium.badge, "Premium tier badge");
    requireNonEmptyString(errors, premium.title, "Premium tier title");
    requireNonEmptyString(errors, premium.subtitle, "Premium tier subtitle");
    requireNonEmptyString(errors, premium.ctaLabel, "Premium tier CTA label");
    validateFeatures(errors, premium.features, "Premium tier features");
    const premiumPrice = isRecord(premium.premiumPrice)
      ? premium.premiumPrice
      : null;
    if (!premiumPrice) {
      errors.push("Premium pricing is missing.");
    } else {
      validateTier(errors, premiumPrice.monthly, "Monthly price");
      validateTier(errors, premiumPrice.annual, "Annual price");
    }
  }

  return { valid: errors.length === 0, errors };
}
