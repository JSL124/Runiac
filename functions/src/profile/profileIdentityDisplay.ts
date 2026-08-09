/**
 * Shared reader for the backend-owned identity display fields stored on a
 * `userProfiles/{uid}` document.
 *
 * Feed posts and Feed comments freeze the author's name and initials at write
 * time, so a rename would otherwise leave every earlier post labelled with the
 * old name forever. Every surface that shows another runner's CURRENT identity
 * — the runner public profile projection, the Feed author overlay, and the
 * avatar disc each renders next to it — resolves it through this single
 * helper, so the nickname-wins rule, the trimming rules, and the avatarUrl
 * sanitisation rule exist in exactly one place.
 *
 * This only ever reads `nickname` / `displayName` / `avatarInitials` /
 * `avatarUrl`, all of which the nickname callable and the profile avatar
 * callables already own and wrote. It never derives an identity from
 * anything else.
 */

import { resolveProfileAvatarUrl, type AvatarUrlContext } from "./avatar/avatarPaths.js";

export type ProfileAvatarDisplay = { readonly avatarUrl: string };

export type ProfileIdentityDisplay = {
  readonly displayName: string;
  readonly avatarInitials: string;
} & ProfileAvatarDisplay;

export function resolveProfileIdentityDisplay(
  data: Readonly<Record<string, unknown>> | undefined,
  avatarContext: AvatarUrlContext,
): ProfileIdentityDisplay {
  return {
    displayName: profileDisplayName(data),
    avatarInitials: trimmedString(data?.["avatarInitials"]),
    ...resolveProfileAvatarDisplay(data, avatarContext),
  };
}

/**
 * Standalone avatar-only resolution for callers that want the avatar
 * without the name/initials half of the identity (`getFriendLevels`, whose
 * result deliberately excludes `displayName` — see friendLevels/core.ts).
 */
export function resolveProfileAvatarDisplay(
  data: Readonly<Record<string, unknown>> | undefined,
  avatarContext: AvatarUrlContext,
): ProfileAvatarDisplay {
  return { avatarUrl: resolveProfileAvatarUrl(data, avatarContext) };
}

/**
 * The nickname wins when the runner set one, matching how they see their own
 * account screen and how the leaderboard labels their row.
 */
function profileDisplayName(data: Readonly<Record<string, unknown>> | undefined): string {
  const nickname = trimmedString(data?.["nickname"]);
  return nickname.length > 0 ? nickname : trimmedString(data?.["displayName"]);
}

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
