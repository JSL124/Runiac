import { Timestamp } from "firebase-admin/firestore";

import { blockDocument, isOutgoingRequest } from "./friendsDocuments.js";
import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { dataOf, readUid, requireAuthUid } from "./friendsParsing.js";
import { blockRef, friendRef, profileRef, rateRef, requestRef } from "./friendsPaths.js";
import { fallbackIdentity, socialProfile } from "./friendsProfiles.js";
import { writeOutstandingDelta } from "./friendsRateLimits.js";
import type { FriendsCallableRequest, FriendsDependencies, SocialProfile } from "./friendsTypes.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../security/accountStatus.js";

export async function blockUser(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const targetUid = readUid(request.data, "targetUid");
  if (targetUid === uid) throw friendError(FRIEND_REASON.CANNOT_TARGET_SELF);
  const at = Timestamp.fromMillis(dependencies.nowMs());
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const blockReference = blockRef(dependencies.firestore, uid, targetUid);
    const localRequestReference = requestRef(dependencies.firestore, uid, targetUid);
    const remoteRequestReference = requestRef(dependencies.firestore, targetUid, uid);
    const localRateReference = rateRef(dependencies.firestore, uid);
    const remoteRateReference = rateRef(dependencies.firestore, targetUid);
    const [blockSnapshot, profileSnapshot, localRequestSnapshot, remoteRequestSnapshot,
      localRateSnapshot, remoteRateSnapshot] = await Promise.all([
      transaction.get(blockReference),
      transaction.get(profileRef(dependencies.firestore, targetUid)),
      transaction.get(localRequestReference),
      transaction.get(remoteRequestReference),
      transaction.get(localRateReference),
      transaction.get(remoteRateReference),
    ]);
    if (!blockSnapshot.exists) {
      const profile = socialProfile(targetUid, dataOf(profileSnapshot)) ?? fallbackProfile(targetUid);
      transaction.set(blockReference, blockDocument(targetUid, profile, at));
    }
    transaction.delete(friendRef(dependencies.firestore, uid, targetUid));
    transaction.delete(friendRef(dependencies.firestore, targetUid, uid));
    transaction.delete(localRequestReference);
    transaction.delete(remoteRequestReference);
    if (isOutgoingRequest(dataOf(localRequestSnapshot), uid, targetUid)) {
      writeOutstandingDelta(transaction, localRateReference, dataOf(localRateSnapshot), -1);
    }
    if (isOutgoingRequest(dataOf(remoteRequestSnapshot), targetUid, uid)) {
      writeOutstandingDelta(transaction, remoteRateReference, dataOf(remoteRateSnapshot), -1);
    }
    return { blocked: !blockSnapshot.exists };
  });
}

export async function unblockUser(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const targetUid = readUid(request.data, "targetUid");
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const reference = blockRef(dependencies.firestore, uid, targetUid);
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return { unblocked: false };
    transaction.delete(reference);
    return { unblocked: true };
  });
}

function fallbackProfile(uid: string): SocialProfile {
  return { identity: fallbackIdentity(uid), canonicalNickname: "runner" };
}
