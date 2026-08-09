import { NicknameInputError, buildFriendIdentity, canonicalizeNickname, nicknameIndexKey, profileString } from "./nickname.js";
import type { SocialProfile } from "./friendsTypes.js";

export function socialProfile(uid: string, profile: Readonly<Record<string, unknown>>): SocialProfile | undefined {
  if (profile["socialDiscoveryStatus"] !== "active") return undefined;
  const nickname = profileString(profile, "nickname");
  const canonical = profileString(profile, "nicknameCanonical");
  if (nickname.length === 0 || canonical.length === 0) return undefined;
  try {
    if (canonicalizeNickname(nickname) !== canonical || nicknameIndexKey(canonical) !== profile["nicknameIndexKey"]) {
      return undefined;
    }
  } catch (error: unknown) {
    if (error instanceof NicknameInputError) return undefined;
    throw error;
  }
  return { identity: buildFriendIdentity(uid, nickname), canonicalNickname: canonical };
}

export function fallbackIdentity(uid: string) {
  return { uid, nickname: "Runner", displayName: "Runner", avatarInitials: "R" };
}
