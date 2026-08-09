import type { Timestamp } from "firebase-admin/firestore";

import type { FriendIdentity } from "./nickname.js";
import type { SocialProfile } from "./friendsTypes.js";

export function requestDocument(input: {
  readonly senderUid: string;
  readonly recipientUid: string;
  readonly direction: "incoming" | "outgoing";
  readonly profile: SocialProfile;
  readonly at: Timestamp;
}) {
  return {
    senderUid: input.senderUid,
    recipientUid: input.recipientUid,
    direction: input.direction,
    status: "PENDING",
    ...identityFields(input.profile.identity),
    listSortKey: input.profile.canonicalNickname,
    listSortTieBreaker: input.profile.identity.uid,
    createdAt: input.at,
    updatedAt: input.at,
  };
}

export function friendDocument(profile: SocialProfile, at: Timestamp) {
  return {
    friendUid: profile.identity.uid,
    ...identityFields(profile.identity),
    listSortKey: profile.canonicalNickname,
    listSortTieBreaker: profile.identity.uid,
    createdAt: at,
    updatedAt: at,
  };
}

export function blockDocument(targetUid: string, profile: SocialProfile, at: Timestamp) {
  return {
    blockedUid: targetUid,
    ...identityFields(profile.identity),
    listSortKey: profile.canonicalNickname,
    listSortTieBreaker: targetUid,
    createdAt: at,
  };
}

export function isOutgoingRequest(data: Readonly<Record<string, unknown>>, senderUid: string, recipientUid: string): boolean {
  return data["senderUid"] === senderUid && data["recipientUid"] === recipientUid && data["direction"] === "outgoing" && data["status"] === "PENDING";
}

export function isIncomingRequest(data: Readonly<Record<string, unknown>>, senderUid: string, recipientUid: string): boolean {
  return data["senderUid"] === senderUid && data["recipientUid"] === recipientUid && data["direction"] === "incoming" && data["status"] === "PENDING";
}

function identityFields(identity: FriendIdentity) {
  return {
    uid: identity.uid,
    nickname: identity.nickname,
    displayName: identity.displayName,
    avatarInitials: identity.avatarInitials,
  };
}
