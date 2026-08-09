// Server-authored participant identity snapshots.
//
// Participant docs expose ONLY a minimal display name and avatar initials —
// never routes, coordinates, run timestamps, or activity history. This module
// derives those two fields from the trusted `userProfiles/{uid}` document with
// deterministic fallbacks, so the roster is always renderable even when a
// profile is sparse.

export type ParticipantIdentitySnapshot = {
  readonly displayNameSnapshot: string;
  readonly avatarInitialsSnapshot: string;
};

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringField(profile: Readonly<Record<string, unknown>> | undefined, key: string): string {
  if (profile === undefined) return "";
  const value = profile[key];
  return typeof value === "string" ? value.trim() : "";
}

// Derive two-letter initials from a display name; falls back to "R" (Runiac).
function deriveInitials(displayName: string): string {
  const words = displayName.split(/\s+/u).filter((word) => word.length > 0);
  if (words.length === 0) return "R";
  if (words.length === 1) return words[0]!.slice(0, 2).toUpperCase();
  return `${words[0]![0]!}${words[1]![0]!}`.toUpperCase();
}

// Build the immutable identity snapshot recorded onto a participant doc. Reads
// `displayName`/`avatarInitials` (the feed profile convention) with a
// `nickname` fallback and a final "Runner" default.
export function buildParticipantIdentity(profileData: unknown): ParticipantIdentitySnapshot {
  const profile = isRecord(profileData) ? profileData : undefined;
  const displayName =
    stringField(profile, "displayName") ||
    stringField(profile, "nickname") ||
    "Runner";
  const avatarInitials = stringField(profile, "avatarInitials") || deriveInitials(displayName);
  return {
    displayNameSnapshot: displayName,
    avatarInitialsSnapshot: avatarInitials.slice(0, 3).toUpperCase(),
  };
}
