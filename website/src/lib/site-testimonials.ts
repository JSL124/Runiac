// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable testimonials section (config/siteContent.testimonials).
//
// Pure module (no Firebase / server imports) so it is shared by the marketing
// render layer (src/lib/site-content.ts, TestimonialsSection.tsx), the admin
// console model/mapping (src/lib/admin/*), and the save action's validator
// (src/lib/actions/admin.ts) — mirrors the shape of src/lib/site-pricing.ts.
//
// DEFAULT_SITE_TESTIMONIALS reuses the community quotes that used to be
// hard-coded in the lower "real problem" block of Problem.tsx, so an unseeded
// (or partial, or malformed) document renders meaningful content rather than an
// empty section. mergeSiteTestimonials() falls back to these defaults per field.

export type SiteTestimonial = {
  quote: string;
  authorName: string;
  authorTitle: string;
};

export type SiteTestimonials = {
  title: string;
  subtitle: string;
  items: SiteTestimonial[];
};

export const DEFAULT_SITE_TESTIMONIALS: SiteTestimonials = {
  title: "The problem is not starting. It is staying consistent.",
  subtitle:
    "See what runners in beginner communities said about the struggle to keep going.",
  items: [
    {
      quote: "I kept repeating runs, but it still felt like zero progress.",
      authorName: "j***",
      authorTitle: "C25K community",
    },
    {
      quote:
        "I wanted structure, but random intervals made it hard to know what to do next.",
      authorName: "a***",
      authorTitle: "Beginner running community",
    },
    {
      quote:
        "I could not tell whether slow running still counted as improvement.",
      authorName: "m***",
      authorTitle: "C25K community",
    },
    {
      quote:
        "I have tried before and always stopped once it started feeling hard.",
      authorName: "s***",
      authorTitle: "Beginner running community",
    },
    {
      quote: "I did not quit on purpose. I just lost the push to go again.",
      authorName: "d***",
      authorTitle: "C25K community",
    },
    {
      quote: "When every run felt too hard, giving up started to feel easier.",
      authorName: "r***",
      authorTitle: "C25K community",
    },
    {
      quote:
        "Everyone kept saying slow down, but I did not know what slow enough meant.",
      authorName: "k***",
      authorTitle: "C25K community",
    },
    {
      quote:
        "I was running way too fast because I thought that was what running meant.",
      authorName: "n***",
      authorTitle: "Beginner running community",
    },
    {
      quote:
        "Beginner plans felt less personal than what my body could handle that day.",
      authorName: "t***",
      authorTitle: "C25K community",
    },
  ],
};

// --- initials -----------------------------------------------------------------

// Derives the avatar initials shown in each card's circle from the author name
// (e.g. "Emily W." -> "EW", "m***" -> "M"). Falls back to "?" when the name has
// no alphanumeric characters.
export function initialsFor(authorName: string): string {
  const words = authorName
    .split(/\s+/)
    .map((word) => word.replace(/[^a-zA-Z0-9]/g, ""))
    .filter(Boolean);

  if (words.length === 0) {
    const firstAlnum = authorName.replace(/[^a-zA-Z0-9]/g, "").charAt(0);
    return firstAlnum ? firstAlnum.toUpperCase() : "?";
  }

  const letters = words.slice(0, 2).map((word) => word.charAt(0));
  return letters.join("").toUpperCase();
}

// --- row arrangement ----------------------------------------------------------

export type TestimonialRow = {
  id: string;
  speed: string;
  direction: "left" | "right";
  items: SiteTestimonial[];
};

// Arranges a flat testimonial list into up to three horizontally-scrolling rows
// with alternating direction and staggered speeds, matching the reference
// design. Distributes round-robin so every row stays roughly balanced.
export function arrangeIntoRows(items: SiteTestimonial[]): TestimonialRow[] {
  const configs: { id: string; speed: string; direction: "left" | "right" }[] =
    [
      { id: "row-1", speed: "42s", direction: "left" },
      { id: "row-2", speed: "52s", direction: "right" },
      { id: "row-3", speed: "46s", direction: "left" },
    ];

  const rowCount = Math.min(configs.length, Math.max(1, items.length));
  const buckets: SiteTestimonial[][] = Array.from(
    { length: rowCount },
    () => [],
  );

  items.forEach((item, index) => {
    buckets[index % rowCount].push(item);
  });

  return buckets
    .map((bucket, index) => ({ ...configs[index], items: bucket }))
    .filter((row) => row.items.length > 0);
}

// --- deep-merge over defaults -------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

// A stored testimonial list is used only when it is an array whose every entry
// is a well-formed { quote, authorName, authorTitle } record; otherwise it
// falls back to the default list. Malformed entries within an otherwise valid
// array are dropped rather than rendered blank.
function mergeItems(
  raw: unknown,
  fallback: SiteTestimonial[],
): SiteTestimonial[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }

  const cleaned = raw
    .filter(isRecord)
    .map((entry) => ({
      quote: typeof entry.quote === "string" ? entry.quote : "",
      authorName: typeof entry.authorName === "string" ? entry.authorName : "",
      authorTitle:
        typeof entry.authorTitle === "string" ? entry.authorTitle : "",
    }))
    .filter((entry) => entry.quote.trim().length > 0);

  return cleaned.length > 0 ? cleaned : fallback;
}

// Per-field deep-merge of an arbitrary stored value over
// DEFAULT_SITE_TESTIMONIALS. Always returns a fully-populated, render-safe
// SiteTestimonials.
export function mergeSiteTestimonials(raw: unknown): SiteTestimonials {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_TESTIMONIALS;

  return {
    title: mergeString(source.title, defaults.title),
    subtitle: mergeString(source.subtitle, defaults.subtitle),
    items: mergeItems(source.items, defaults.items),
  };
}

// --- validation (used by the admin save action) -------------------------------

export type SiteTestimonialsValidationResult = {
  valid: boolean;
  errors: string[];
};

export function validateSiteTestimonials(
  raw: unknown,
): SiteTestimonialsValidationResult {
  const errors: string[] = [];

  if (!isRecord(raw)) {
    return { valid: false, errors: ["Testimonials content is missing."] };
  }

  if (typeof raw.title !== "string" || raw.title.trim().length === 0) {
    errors.push("Testimonials title must not be empty.");
  }

  if (!Array.isArray(raw.items)) {
    errors.push("Testimonials must be a list.");
    return { valid: errors.length === 0, errors };
  }

  if (raw.items.length === 0) {
    errors.push("Add at least one testimonial.");
  }

  raw.items.forEach((item, index) => {
    const position = index + 1;
    if (!isRecord(item)) {
      errors.push(`Testimonial ${position} is invalid.`);
      return;
    }
    if (typeof item.quote !== "string" || item.quote.trim().length === 0) {
      errors.push(`Testimonial ${position} quote must not be empty.`);
    }
    if (
      typeof item.authorName !== "string" ||
      item.authorName.trim().length === 0
    ) {
      errors.push(`Testimonial ${position} author name must not be empty.`);
    }
  });

  return { valid: errors.length === 0, errors };
}
