// Admin-editable labels for the Website Content accordion sections. These are
// console-only organizational labels (they never render on the marketing site),
// stored in config/siteContent.sectionTitles so a renamed section survives
// reloads. Any missing or blank entry falls back to the default label, so a
// header is never empty.
//
// Pure module (no Firebase / server imports).

export type SectionTitleKey =
  | "announcement"
  | "hero"
  | "problem"
  | "solution"
  | "personalizedPlan"
  | "journeyMap"
  | "xpProgression"
  | "territorial"
  | "postRunSummary"
  | "pricing"
  | "testimonials"
  | "team"
  | "faq";

export type SiteSectionTitles = Record<SectionTitleKey, string>;

export const DEFAULT_SECTION_TITLES: SiteSectionTitles = {
  announcement: "Announcement banner",
  hero: "Hero",
  problem: "Problem section",
  solution: "Solution section",
  personalizedPlan: "Personalized plan section",
  journeyMap: "Adventure map section",
  xpProgression: "Progression system section",
  territorial: "Territorial leaderboard section",
  postRunSummary: "Post-run summary section",
  pricing: "Pricing page",
  testimonials: "Testimonials",
  team: "Team (About page)",
  faq: "FAQ",
};

// Default top-to-bottom order of the sections. The home landing page
// (src/app/page.tsx) walks config/siteContent.sectionOrder to decide the render
// order of its stacked sections, so this default is kept in sync with the live
// home layout: dragging in the admin console reorders the home page for the
// movable keys (problem, testimonials, solution, journeyMap, personalizedPlan,
// xpProgression, territorial, postRunSummary, pricing). Keys that are pinned
// (hero, announcement) or live on their own routes (team -> /about,
// faq -> /faq) appear here for the admin accordion but are skipped by the home
// render registry, so reordering them has no visual effect on the live site.
export const DEFAULT_SECTION_ORDER: SectionTitleKey[] = [
  "announcement",
  "hero",
  "problem",
  "testimonials",
  "solution",
  "journeyMap",
  "personalizedPlan",
  "xpProgression",
  "territorial",
  "postRunSummary",
  "pricing",
  "team",
  "faq",
];

// Normalizes a stored order into a complete, valid permutation of the known
// keys: honor the stored sequence (dropping unknowns/duplicates), then splice
// in any missing keys at their default-order position — right after the nearest
// preceding default key that is already present. This matters when a new
// section is added to the codebase after a doc was already saved: the new key
// appears in its natural spot (e.g. journeyMap right after solution) for
// already-seeded docs instead of being dumped at the very end, until an
// admin drags it elsewhere. Guarantees every section appears exactly once.
export function mergeSectionOrder(raw: unknown): SectionTitleKey[] {
  const known = new Set<SectionTitleKey>(DEFAULT_SECTION_ORDER);
  const result: SectionTitleKey[] = [];

  if (Array.isArray(raw)) {
    for (const value of raw) {
      if (
        typeof value === "string" &&
        known.has(value as SectionTitleKey) &&
        !result.includes(value as SectionTitleKey)
      ) {
        result.push(value as SectionTitleKey);
      }
    }
  }

  DEFAULT_SECTION_ORDER.forEach((key, defaultIndex) => {
    if (result.includes(key)) {
      return;
    }
    // Insert right after the nearest earlier default key that is present in the
    // result; if none is present, insert at the front.
    let insertAt = 0;
    for (let j = defaultIndex - 1; j >= 0; j--) {
      const idx = result.indexOf(DEFAULT_SECTION_ORDER[j]);
      if (idx !== -1) {
        insertAt = idx + 1;
        break;
      }
    }
    result.splice(insertAt, 0, key);
  });

  return result;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Per-key merge over the defaults: a stored label is used only when it is a
// non-empty string; anything else falls back to the default so headers never
// render blank.
export function mergeSectionTitles(raw: unknown): SiteSectionTitles {
  const source = isRecord(raw) ? raw : {};
  const out = { ...DEFAULT_SECTION_TITLES };
  for (const key of Object.keys(DEFAULT_SECTION_TITLES) as SectionTitleKey[]) {
    const value = source[key];
    if (typeof value === "string" && value.trim().length > 0) {
      out[key] = value;
    }
  }
  return out;
}
