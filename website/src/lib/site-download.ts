// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable Download page (config/siteContent.download): the
// Android/iOS cards, the "install in 3 steps" list, and the system
// requirements list.
//
// Pure module (no Firebase / server imports) so it is shared by the marketing
// render layer (src/lib/site-content.ts, src/app/download/page.tsx), the
// admin console model/mapping (src/lib/admin/*), and the save action's
// validator (src/lib/actions/admin.ts) — mirrors the shape of
// src/lib/site-team.ts.
//
// DEFAULT_SITE_DOWNLOAD reuses the literals that used to live directly in
// src/app/download/page.tsx, so an unseeded (or partial, or malformed)
// document renders the same Download page as before. mergeSiteDownload()
// falls back per field.

export type SiteDownloadStep = {
  title: string;
  body: string;
};

export type SiteDownload = {
  android: {
    apkUrl: string;
    note: string;
  };
  ios: {
    comingSoon: boolean;
    badgeLabel: string;
    reason: string;
  };
  steps: SiteDownloadStep[];
  requirements: string[];
};

export const DEFAULT_SITE_DOWNLOAD: SiteDownload = {
  android: {
    // Same-origin endpoint rather than the GitHub Releases URL: the visitor
    // downloads from the Runiac domain and never leaves the site. The route
    // (src/app/api/download/android/route.ts) streams the Releases "latest"
    // alias, so publishing a new android-vX.Y.Z release still re-points the
    // button without a code change.
    apkUrl: "/api/download/android",
    note: "Direct APK · Android 8.0+ · You may need to allow installs from your browser.",
  },
  ios: {
    comingSoon: true,
    badgeLabel: "Coming soon",
    reason: "TestFlight distribution is in preparation.",
  },
  steps: [
    {
      title: "Download the APK",
      body: "Grab the Android installer directly from the button above — no app store account needed.",
    },
    {
      title: "Create your account",
      body: "Sign up in a minute and tell us a little about your running experience.",
    },
    {
      title: "Start your first run",
      body: "Follow your first plan session and start earning XP toward your level.",
    },
  ],
  requirements: [
    "Android 8.0 (API 26) or newer",
    "~150 MB download",
    "GPS required for run tracking",
    "Internet needed for sync",
    "iOS — Coming soon",
  ],
};

// --- deep-merge over defaults -------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

function mergeNonEmptyString(raw: unknown, fallback: string): string {
  return typeof raw === "string" && raw.trim().length > 0 ? raw : fallback;
}

// Same as mergeNonEmptyString, but the surrounding whitespace is dropped. Used
// for apkUrl: a URL pasted into the admin console with a leading space was
// rendered verbatim into href=" https://…", which browsers treat as a relative
// path and the download button silently broke.
//
// The value also becomes the public download page's href, so the scheme is
// restricted to the two shapes a download link can legitimately take: an
// https: URL, or a site-relative path such as the default
// "/api/download/android". Anything else — most obviously a "javascript:" URL
// typed into the admin console's APK field — falls back to the default rather
// than being rendered as a link every visitor is invited to click.
function mergeUrl(raw: unknown, fallback: string): string {
  if (typeof raw !== "string") {
    return fallback;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0 || !isSafeDownloadUrl(trimmed)) {
    return fallback;
  }
  return trimmed;
}

const RELATIVE_URL_BASE = "https://runiac.invalid";

function isSafeDownloadUrl(value: string): boolean {
  // Control characters are stripped by URL parsing, so "/\t/evil.test/a.apk"
  // normalises to the protocol-relative "//evil.test/a.apk" that the prefix
  // checks below are meant to reject. Refuse them outright rather than trying
  // to predict the normalisation.
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001F\u007F]/.test(value)) {
    return false;
  }
  // A site-relative path: one leading slash, never "//host" (protocol-relative)
  // and never a "/\host" variant browsers also treat as protocol-relative.
  // Resolving against a throwaway origin is the check that actually holds:
  // anything that escapes to another host lands on a different origin.
  if (value.startsWith("/")) {
    try {
      return new URL(value, RELATIVE_URL_BASE).origin === RELATIVE_URL_BASE;
    } catch {
      return false;
    }
  }
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

function mergeBoolean(raw: unknown, fallback: boolean): boolean {
  return typeof raw === "boolean" ? raw : fallback;
}

function readString(raw: unknown): string {
  return typeof raw === "string" ? raw : "";
}

// A stored steps list is used only when it is an array with at least one
// well-formed { title, body } entry; otherwise it falls back to the default
// steps. Malformed or blank entries within an otherwise valid array are
// dropped rather than rendered empty.
function mergeSteps(
  raw: unknown,
  fallback: SiteDownloadStep[],
): SiteDownloadStep[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }

  const cleaned = raw
    .filter(isRecord)
    .map((entry) => ({
      title: readString(entry.title),
      body: readString(entry.body),
    }))
    .filter(
      (step) => step.title.trim().length > 0 && step.body.trim().length > 0,
    );

  return cleaned.length > 0 ? cleaned : fallback;
}

// A stored requirements list is used only when it is an array with at least
// one non-empty string; otherwise it falls back to the default list.
function mergeRequirements(raw: unknown, fallback: string[]): string[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }

  const cleaned = raw.filter(
    (entry): entry is string =>
      typeof entry === "string" && entry.trim().length > 0,
  );

  return cleaned.length > 0 ? cleaned : fallback;
}

// Per-field deep-merge of an arbitrary stored value over DEFAULT_SITE_DOWNLOAD.
// Always returns a fully-populated, render-safe SiteDownload.
export function mergeSiteDownload(raw: unknown): SiteDownload {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_DOWNLOAD;
  const android = isRecord(source.android) ? source.android : {};
  const ios = isRecord(source.ios) ? source.ios : {};

  return {
    android: {
      apkUrl: mergeUrl(android.apkUrl, defaults.android.apkUrl),
      note: mergeString(android.note, defaults.android.note),
    },
    ios: {
      comingSoon: mergeBoolean(ios.comingSoon, defaults.ios.comingSoon),
      badgeLabel: mergeString(ios.badgeLabel, defaults.ios.badgeLabel),
      reason: mergeString(ios.reason, defaults.ios.reason),
    },
    steps: mergeSteps(source.steps, defaults.steps),
    requirements: mergeRequirements(source.requirements, defaults.requirements),
  };
}

// --- validation (used by the admin save action) -------------------------------

export type SiteDownloadValidationResult = {
  errors: string[];
};

export function validateSiteDownload(
  raw: unknown,
): SiteDownloadValidationResult {
  const errors: string[] = [];

  if (raw === undefined) {
    return { errors };
  }

  if (!isRecord(raw)) {
    errors.push("Download content is invalid.");
    return { errors };
  }

  if (raw.android !== undefined) {
    if (!isRecord(raw.android)) {
      errors.push("Download android section is invalid.");
    } else {
      if (
        typeof raw.android.apkUrl !== "string" ||
        raw.android.apkUrl.trim().length === 0
      ) {
        errors.push("Download Android APK URL must not be empty.");
      } else if (!isSafeDownloadUrl(raw.android.apkUrl.trim())) {
        // Rejected at save time as well as at render time, so the admin sees
        // why the value was refused instead of silently getting the default
        // back on the next page load.
        errors.push(
          "Download Android APK URL must be an https:// URL or a site-relative path.",
        );
      }
      if (raw.android.note !== undefined && typeof raw.android.note !== "string") {
        errors.push("Download Android note must be a string.");
      }
    }
  }

  if (raw.ios !== undefined) {
    if (!isRecord(raw.ios)) {
      errors.push("Download iOS section is invalid.");
    } else {
      if (
        raw.ios.comingSoon !== undefined &&
        typeof raw.ios.comingSoon !== "boolean"
      ) {
        errors.push("Download iOS comingSoon must be a boolean.");
      }
      if (
        raw.ios.badgeLabel !== undefined &&
        typeof raw.ios.badgeLabel !== "string"
      ) {
        errors.push("Download iOS badge label must be a string.");
      }
      if (raw.ios.reason !== undefined && typeof raw.ios.reason !== "string") {
        errors.push("Download iOS reason must be a string.");
      }
    }
  }

  if (raw.steps !== undefined) {
    if (!Array.isArray(raw.steps)) {
      errors.push("Download steps must be a list.");
    } else {
      raw.steps.forEach((step, index) => {
        const position = index + 1;
        if (!isRecord(step)) {
          errors.push(`Download step ${position} is invalid.`);
          return;
        }
        if (typeof step.title !== "string" || step.title.trim().length === 0) {
          errors.push(`Download step ${position} title must not be empty.`);
        }
        if (typeof step.body !== "string" || step.body.trim().length === 0) {
          errors.push(`Download step ${position} body must not be empty.`);
        }
      });
    }
  }

  if (raw.requirements !== undefined) {
    if (!Array.isArray(raw.requirements)) {
      errors.push("Download requirements must be a list.");
    } else {
      raw.requirements.forEach((entry, index) => {
        if (typeof entry !== "string" || entry.trim().length === 0) {
          errors.push(`Download requirement ${index + 1} must not be empty.`);
        }
      });
    }
  }

  return { errors };
}
