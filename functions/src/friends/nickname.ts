import { createHash } from "node:crypto";

export type FriendIdentity = {
  readonly uid: string;
  readonly nickname: string;
  readonly displayName: string;
  readonly avatarInitials: string;
};

export type NicknameMigrationProfile = {
  readonly uid: string;
  readonly nickname: string;
  readonly legacyNicknameKey?: string;
  readonly nicknameIndexKey?: string;
  readonly nicknameCanonical?: string;
  readonly socialDiscoveryStatus?: string;
};

export type NicknameMigrationClaim = {
  readonly id: string;
  readonly ownerUid: string;
  readonly nicknameCanonical?: string;
};

export type NicknameMigrationRow = {
  readonly uid: string;
  readonly nickname: string;
  readonly canonical: string;
  readonly indexKey: string;
  readonly sourceClaimId: string;
  readonly socialDiscoveryStatus: "active" | "inactive";
};

export type NicknameMigrationPlan =
  | { readonly kind: "ready"; readonly rows: readonly NicknameMigrationRow[] }
  | { readonly kind: "invalid"; readonly reason: "INVALID_NICKNAME" | "CANONICAL_COLLISION" | "CORRUPT_CLAIM" };

export class NicknameInputError extends Error {
  readonly name = "NicknameInputError";

  constructor() {
    super("Nickname must be 1-30 Unicode code points without control characters.");
  }
}

export function canonicalizeNickname(value: string): string {
  if (/[\u0000-\u001F\u007F-\u009F]/u.test(value)) throw new NicknameInputError();
  const normalized = value.trim().normalize("NFC").toLocaleLowerCase("und");
  if (
    normalized.length === 0 ||
    Array.from(normalized).length > 30
  ) {
    throw new NicknameInputError();
  }
  return normalized;
}

export function nicknameIndexKey(canonicalNickname: string): string {
  const digest = createHash("sha256").update(canonicalNickname, "utf8").digest("hex");
  return `n1_${digest}`;
}

export function buildFriendIdentity(
  uid: string,
  nickname: string,
): FriendIdentity {
  const displayName = nickname;
  const avatarInitials = initials(displayName);
  return {
    uid,
    nickname,
    displayName,
    avatarInitials: Array.from(avatarInitials).slice(0, 3).join("").toUpperCase(),
  };
}

export function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function profileString(profile: Readonly<Record<string, unknown>>, field: string): string {
  const value = profile[field];
  return typeof value === "string" ? value.trim() : "";
}

export function preflightNicknameClaimMigration(
  profiles: readonly NicknameMigrationProfile[],
  claims: readonly NicknameMigrationClaim[],
): NicknameMigrationPlan {
  const claimsById = new Map(claims.map((claim) => [claim.id, claim]));
  const canonicalOwners = new Map<string, string>();
  const usedClaimIds = new Set<string>();
  const canonicalProfiles: Array<{ readonly profile: NicknameMigrationProfile; readonly canonical: string }> = [];
  const rows: NicknameMigrationRow[] = [];

  for (const profile of profiles) {
    let canonical: string;
    try {
      canonical = canonicalizeNickname(profile.nickname);
    } catch (error: unknown) {
      if (error instanceof NicknameInputError) return { kind: "invalid", reason: "INVALID_NICKNAME" };
      throw error;
    }
    const priorOwner = canonicalOwners.get(canonical);
    if (priorOwner !== undefined && priorOwner !== profile.uid) {
      return { kind: "invalid", reason: "CANONICAL_COLLISION" };
    }
    canonicalOwners.set(canonical, profile.uid);
    canonicalProfiles.push({ profile, canonical });
  }

  if (!validateNicknameIndexCanonicalPairs(canonicalProfiles.map(({ canonical }) => ({
    indexKey: nicknameIndexKey(canonical),
    canonical,
  })))) {
    return { kind: "invalid", reason: "CORRUPT_CLAIM" };
  }

  for (const { profile, canonical } of canonicalProfiles) {
    const indexKey = nicknameIndexKey(canonical);
    const sourceClaimId = profile.nicknameIndexKey === indexKey
      ? indexKey
      : profile.legacyNicknameKey;
    if (sourceClaimId === undefined) return { kind: "invalid", reason: "CORRUPT_CLAIM" };
    const claim = claimsById.get(sourceClaimId);
    if (claim === undefined || claim.ownerUid !== profile.uid) {
      return { kind: "invalid", reason: "CORRUPT_CLAIM" };
    }
    if (
      sourceClaimId === indexKey &&
      (claim.nicknameCanonical !== canonical || profile.nicknameCanonical !== canonical)
    ) {
      return { kind: "invalid", reason: "CORRUPT_CLAIM" };
    }
    usedClaimIds.add(sourceClaimId);
    rows.push({
      uid: profile.uid,
      nickname: profile.nickname.trim().normalize("NFC"),
      canonical,
      indexKey,
      sourceClaimId,
      socialDiscoveryStatus: profile.socialDiscoveryStatus === "inactive" ? "inactive" : "active",
    });
  }

  if (usedClaimIds.size !== claims.length) return { kind: "invalid", reason: "CORRUPT_CLAIM" };
  return { kind: "ready", rows };
}

export function validateNicknameIndexCanonicalPairs(
  pairs: readonly { readonly indexKey: string; readonly canonical: string }[],
): boolean {
  const canonicalByIndexKey = new Map<string, string>();
  for (const pair of pairs) {
    const existingCanonical = canonicalByIndexKey.get(pair.indexKey);
    if (existingCanonical !== undefined && existingCanonical !== pair.canonical) return false;
    canonicalByIndexKey.set(pair.indexKey, pair.canonical);
  }
  return true;
}

function initials(displayName: string): string {
  const parts = displayName.split(/\s+/u).filter((part) => part.length > 0);
  if (parts.length === 0) return "R";
  if (parts.length === 1) return Array.from(parts[0] ?? "R").slice(0, 2).join("").toUpperCase();
  const first = Array.from(parts[0] ?? "R")[0] ?? "R";
  const second = Array.from(parts[1] ?? "R")[0] ?? "R";
  return `${first}${second}`.toUpperCase();
}
