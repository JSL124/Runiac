// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable Documents page (config/siteContent.documents): the
// hero heading/intro and the document card list.
//
// Pure module (no Firebase / server imports) so it is shared by the marketing
// render layer (src/lib/site-content.ts, src/app/documents/page.tsx), the
// admin console model/mapping (src/lib/admin/*), and the save action's
// validator (src/lib/actions/admin.ts) — mirrors the shape of
// src/lib/site-team.ts.
//
// DEFAULT_SITE_DOCUMENTS reuses the literals that used to live directly in
// src/app/documents/page.tsx, so an unseeded (or partial, or malformed)
// document renders the same Documents page as before. mergeSiteDocuments()
// falls back per field.

export type SiteDocumentCard = {
  title: string;
  status: string;
  body: string;
};

export type SiteDocuments = {
  heading: string;
  intro: string;
  cards: SiteDocumentCard[];
};

export const DEFAULT_SITE_DOCUMENTS: SiteDocuments = {
  heading: "Runiac project documents.",
  intro:
    "A focused place for the project materials behind Runiac, including planning, system design, user guidance, and team records.",
  cards: [
    {
      title: "Project Proposal",
      status: "Core document",
      body: "Problem statement, project objectives, scope, and the beginner-focused direction behind Runiac.",
    },
    {
      title: "System Overview",
      status: "Architecture",
      body: "Mobile client, Firebase backend, Firestore data flow, notifications, and leaderboard processing.",
    },
    {
      title: "User Manual",
      status: "Product guide",
      body: "Beginner onboarding, run tracking, reminders, streaks, XP progression, and fair competition flows.",
    },
    {
      title: "Meeting Minutes",
      status: "Project records",
      body: "Team planning notes, decisions, weekly progress, and follow-up actions throughout the FYP.",
    },
  ],
};

// --- deep-merge over defaults -------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

function readString(raw: unknown): string {
  return typeof raw === "string" ? raw : "";
}

// A stored card list is used only when it is an array with at least one
// well-formed entry (non-empty title/status/body); otherwise it falls back to
// the default cards. Malformed or incomplete entries are dropped rather than
// rendered broken. Any extra, no-longer-supported field a stored entry still
// carries from before the Documents page cards stopped linking out is simply
// ignored: only title/status/body are read here.
function mergeCards(
  raw: unknown,
  fallback: SiteDocumentCard[],
): SiteDocumentCard[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }

  const cleaned = raw
    .filter(isRecord)
    .map((entry): SiteDocumentCard => ({
      title: readString(entry.title),
      status: readString(entry.status),
      body: readString(entry.body),
    }))
    .filter(
      (card) =>
        card.title.trim().length > 0 &&
        card.status.trim().length > 0 &&
        card.body.trim().length > 0,
    );

  return cleaned.length > 0 ? cleaned : fallback;
}

// Per-field deep-merge of an arbitrary stored value over DEFAULT_SITE_DOCUMENTS.
// Always returns a fully-populated, render-safe SiteDocuments.
export function mergeSiteDocuments(raw: unknown): SiteDocuments {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_DOCUMENTS;

  return {
    heading: mergeString(source.heading, defaults.heading),
    intro: mergeString(source.intro, defaults.intro),
    cards: mergeCards(source.cards, defaults.cards),
  };
}

// --- validation (used by the admin save action) -------------------------------

export type SiteDocumentsValidationResult = {
  errors: string[];
};

export function validateSiteDocuments(
  raw: unknown,
): SiteDocumentsValidationResult {
  const errors: string[] = [];

  if (raw === undefined) {
    return { errors };
  }

  if (!isRecord(raw)) {
    errors.push("Documents content is invalid.");
    return { errors };
  }

  if (raw.heading !== undefined && typeof raw.heading !== "string") {
    errors.push("Documents heading must be a string.");
  }

  if (raw.intro !== undefined && typeof raw.intro !== "string") {
    errors.push("Documents intro must be a string.");
  }

  if (raw.cards !== undefined) {
    if (!Array.isArray(raw.cards)) {
      errors.push("Documents cards must be a list.");
    } else {
      raw.cards.forEach((card, index) => {
        const position = index + 1;
        if (!isRecord(card)) {
          errors.push(`Document card ${position} is invalid.`);
          return;
        }
        if (typeof card.title !== "string" || card.title.trim().length === 0) {
          errors.push(`Document card ${position} title must not be empty.`);
        }
        if (
          typeof card.status !== "string" ||
          card.status.trim().length === 0
        ) {
          errors.push(`Document card ${position} status must not be empty.`);
        }
        if (typeof card.body !== "string" || card.body.trim().length === 0) {
          errors.push(`Document card ${position} body must not be empty.`);
        }
      });
    }
  }

  return { errors };
}
