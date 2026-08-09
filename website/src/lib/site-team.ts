// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable "About us" team section (config/siteContent.team):
// the section heading, the team-member cards, and the supervisor block.
//
// Pure module (no Firebase / server imports) so it is shared by the marketing
// render layer (src/lib/site-content.ts, src/app/about/page.tsx), the admin
// console model/mapping (src/lib/admin/*), and the save action's validator
// (src/lib/actions/admin.ts) — mirrors the shape of src/lib/site-testimonials.ts.
//
// DEFAULT_SITE_TEAM reuses the literals that used to live directly in
// src/lib/team.ts, so an unseeded (or partial, or malformed) document renders
// the same About page as before. mergeSiteTeam() falls back per field.

import { PROJECT_SUPERVISOR, TEAM_MEMBERS } from "@/lib/team";

export type SiteTeamMember = {
  name: string;
  role: string;
  bio: string;
  // Photo is a /public path (e.g. /images/team/name.jpg) or an https:// URL.
  photo: string;
  // Optional social links; empty string means "not shown".
  github: string;
  linkedin: string;
  email: string;
};

export type SiteTeamSupervisor = {
  name: string;
  role: string;
  email: string;
  bio: string;
};

export type SiteTeam = {
  eyebrow: string;
  heading: string;
  body: string;
  members: SiteTeamMember[];
  supervisorLabel: string;
  supervisor: SiteTeamSupervisor;
};

export const DEFAULT_SITE_TEAM: SiteTeam = {
  eyebrow: "Our team",
  heading: "Meet the Team Behind Runiac",
  body: "Runiac is built by a five-member student team combining product planning, mobile development, backend engineering, data modeling, and beginner-focused UX design.",
  members: TEAM_MEMBERS.map((member) => ({
    name: member.name,
    role: member.role,
    bio: member.bio,
    photo: member.photo,
    github: member.github ?? "",
    linkedin: member.linkedin ?? "",
    email: member.email ?? "",
  })),
  supervisorLabel: "Supervisor",
  supervisor: { ...PROJECT_SUPERVISOR },
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

// A stored member list is used only when it is an array with at least one entry
// that has both a name and a photo (the two fields the card cannot render
// without); otherwise it falls back to the default roster. Malformed or
// incomplete entries are dropped rather than rendered broken.
function mergeMembers(
  raw: unknown,
  fallback: SiteTeamMember[],
): SiteTeamMember[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }

  const cleaned = raw
    .filter(isRecord)
    .map((entry) => ({
      name: readString(entry.name),
      role: readString(entry.role),
      bio: readString(entry.bio),
      photo: readString(entry.photo),
      github: readString(entry.github),
      linkedin: readString(entry.linkedin),
      email: readString(entry.email),
    }))
    .filter(
      (member) => member.name.trim().length > 0 && member.photo.trim().length > 0,
    );

  return cleaned.length > 0 ? cleaned : fallback;
}

// Per-field deep-merge of an arbitrary stored value over DEFAULT_SITE_TEAM.
// Always returns a fully-populated, render-safe SiteTeam.
export function mergeSiteTeam(raw: unknown): SiteTeam {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_TEAM;
  const supervisor = isRecord(source.supervisor) ? source.supervisor : {};

  return {
    eyebrow: mergeString(source.eyebrow, defaults.eyebrow),
    heading: mergeString(source.heading, defaults.heading),
    body: mergeString(source.body, defaults.body),
    members: mergeMembers(source.members, defaults.members),
    supervisorLabel: mergeString(
      source.supervisorLabel,
      defaults.supervisorLabel,
    ),
    supervisor: {
      name: mergeString(supervisor.name, defaults.supervisor.name),
      role: mergeString(supervisor.role, defaults.supervisor.role),
      email: mergeString(supervisor.email, defaults.supervisor.email),
      bio: mergeString(supervisor.bio, defaults.supervisor.bio),
    },
  };
}

// --- validation (used by the admin save action) -------------------------------

export type SiteTeamValidationResult = {
  valid: boolean;
  errors: string[];
};

// Photo must be a /public path or an https:// URL, matching how next/Image is
// used by the team card (a bare relative string would throw at render time).
function isValidPhoto(value: unknown): boolean {
  if (typeof value !== "string" || value.trim().length === 0) {
    return false;
  }
  const trimmed = value.trim();
  return trimmed.startsWith("/") || /^https?:\/\//.test(trimmed);
}

export function validateSiteTeam(raw: unknown): SiteTeamValidationResult {
  const errors: string[] = [];

  if (!isRecord(raw)) {
    return { valid: false, errors: ["Team content is missing."] };
  }

  if (typeof raw.heading !== "string" || raw.heading.trim().length === 0) {
    errors.push("Team heading must not be empty.");
  }

  if (!Array.isArray(raw.members)) {
    errors.push("Team members must be a list.");
  } else {
    if (raw.members.length === 0) {
      errors.push("Add at least one team member.");
    }
    raw.members.forEach((member, index) => {
      const position = index + 1;
      if (!isRecord(member)) {
        errors.push(`Team member ${position} is invalid.`);
        return;
      }
      if (typeof member.name !== "string" || member.name.trim().length === 0) {
        errors.push(`Team member ${position} name must not be empty.`);
      }
      if (typeof member.role !== "string" || member.role.trim().length === 0) {
        errors.push(`Team member ${position} role must not be empty.`);
      }
      if (!isValidPhoto(member.photo)) {
        errors.push(
          `Team member ${position} photo must be a /public path or https:// URL.`,
        );
      }
    });
  }

  const supervisor = isRecord(raw.supervisor) ? raw.supervisor : null;
  if (!supervisor) {
    errors.push("Supervisor content is missing.");
  } else {
    if (
      typeof supervisor.name !== "string" ||
      supervisor.name.trim().length === 0
    ) {
      errors.push("Supervisor name must not be empty.");
    }
  }

  return { valid: errors.length === 0, errors };
}
