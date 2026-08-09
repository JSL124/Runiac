/**
 * Shared reader for the backend-owned level display fields stored on a
 * `userProfiles/{uid}` document. Both `getFeedAuthorLevels` and
 * `getFriendLevels` (and the `searchFriends` result enrichment) resolve a
 * uid's displayed level through this single helper so the fallback and
 * clamping rules exist in exactly one place.
 *
 * This only ever reads `levelLabel` / `level` / `levelProgressPercent` —
 * fields a Cloud Function already computed and wrote. It must never derive a
 * level from XP or any other raw progression input.
 */

export type ProfileLevelDisplay = { readonly levelLabel: string; readonly levelProgressPercent: number };

export function resolveProfileLevelDisplay(data: Readonly<Record<string, unknown>> | undefined): ProfileLevelDisplay {
  return { levelLabel: profileLevelLabel(data), levelProgressPercent: profileLevelProgressPercent(data) };
}

function profileLevelLabel(data: Readonly<Record<string, unknown>> | undefined): string {
  if (data === undefined) return "";
  const label = data["levelLabel"];
  if (typeof label === "string" && label.trim().length > 0) return label.trim();
  const level = data["level"];
  if (typeof level === "number" && Number.isFinite(level)) return `Lv.${Math.trunc(level)}`;
  return "";
}

function profileLevelProgressPercent(data: Readonly<Record<string, unknown>> | undefined): number {
  const value = data?.["levelProgressPercent"];
  const percent = typeof value === "number" && Number.isFinite(value) ? value : 0;
  return Math.min(100, Math.max(0, percent));
}
