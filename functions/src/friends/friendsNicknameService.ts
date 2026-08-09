import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import {
  NICKNAME_RENAME_MAX_FANOUT_ROWS,
  nicknameFanoutReferences,
  updateNicknameFanout,
} from "./friendsNicknameFanout.js";
import { dataOf, readNickname, requireAuthUid } from "./friendsParsing.js";
import { claimRef, profileRef, rateRef, safeDocumentId } from "./friendsPaths.js";
import { nextSearchAttemptMs, writeSearchRate } from "./friendsRateLimits.js";
import { buildFriendIdentity, nicknameIndexKey } from "./nickname.js";
import type { FriendsCallableRequest, FriendsDependencies } from "./friendsTypes.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../security/accountStatus.js";

export async function checkNicknameAvailability(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const nickname = readNickname(request.data);
  const indexKey = nicknameIndexKey(nickname.canonical);
  const atMs = dependencies.nowMs();
  return dependencies.firestore.runTransaction(async (transaction) => {
    const rateReference = rateRef(dependencies.firestore, uid);
    const [rateSnapshot, claimSnapshot] = await Promise.all([
      transaction.get(rateReference),
      transaction.get(claimRef(dependencies.firestore, indexKey)),
    ]);
    const attempts = nextSearchAttemptMs(dataOf(rateSnapshot), atMs);
    writeSearchRate(transaction, rateReference, attempts);
    const claim = dataOf(claimSnapshot);
    return {
      available: !claimSnapshot.exists || (
        claim["ownerUid"] === uid && claim["nicknameCanonical"] === nickname.canonical
      ),
    };
  });
}

export async function upsertNickname(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const nickname = readNickname(request.data);
  const indexKey = nicknameIndexKey(nickname.canonical);
  const at = Timestamp.fromMillis(dependencies.nowMs());
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const profileReference = profileRef(dependencies.firestore, uid);
    const [profileSnapshot, targetClaimSnapshot] = await Promise.all([
      transaction.get(profileReference),
      transaction.get(claimRef(dependencies.firestore, indexKey)),
    ]);
    if (!profileSnapshot.exists) throw friendError(FRIEND_REASON.PROFILE_REQUIRED);
    const profile = dataOf(profileSnapshot);
    if (profile["socialDiscoveryStatus"] === "inactive") throw friendError(FRIEND_REASON.USER_INACTIVE);
    const claim = dataOf(targetClaimSnapshot);
    if (
      targetClaimSnapshot.exists &&
      (claim["ownerUid"] !== uid || claim["nicknameCanonical"] !== nickname.canonical)
    ) {
      throw friendError(FRIEND_REASON.NICKNAME_UNAVAILABLE);
    }
    const oldClaimId = previousClaimId(profile, indexKey);
    const oldClaimSnapshot = oldClaimId === undefined
      ? undefined
      : await transaction.get(claimRef(dependencies.firestore, oldClaimId));
    if (oldClaimSnapshot !== undefined && oldClaimSnapshot.exists && dataOf(oldClaimSnapshot)["ownerUid"] !== uid) {
      throw friendError(FRIEND_REASON.NICKNAME_MIGRATION_INVALID);
    }
    const identity = buildFriendIdentity(uid, nickname.display);
    const fanoutReferences = await nicknameFanoutReferences(dependencies.firestore, transaction, uid);
    if (fanoutReferences.length > NICKNAME_RENAME_MAX_FANOUT_ROWS) {
      throw friendError(FRIEND_REASON.NICKNAME_RENAME_TOO_LARGE);
    }
    transaction.set(claimRef(dependencies.firestore, indexKey), {
      ownerUid: uid,
      nicknameCanonical: nickname.canonical,
      nicknameDisplay: nickname.display,
      nicknameIndexKey: indexKey,
      updatedAt: at,
    });
    transaction.update(profileReference, {
      nickname: nickname.display,
      nicknameCanonical: nickname.canonical,
      nicknameIndexKey: indexKey,
      nicknameKey: FieldValue.delete(),
      displayName: identity.displayName,
      avatarInitials: identity.avatarInitials,
      socialDiscoveryStatus: "active",
      socialListSortKey: nickname.canonical,
      updatedAt: at,
    });
    if (oldClaimId !== undefined) transaction.delete(claimRef(dependencies.firestore, oldClaimId));
    updateNicknameFanout(transaction, fanoutReferences, identity, nickname.canonical);
    return { identity };
  });
}

function previousClaimId(profile: Readonly<Record<string, unknown>>, nextIndexKey: string): string | undefined {
  const candidates = [profile["nicknameIndexKey"], profile["nicknameKey"]];
  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate !== nextIndexKey && safeDocumentId(candidate)) {
      return candidate;
    }
  }
  return undefined;
}
