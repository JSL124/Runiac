import { Timestamp } from "firebase-admin/firestore";

import { DECLINE_COOLDOWN_MS, clearRecordedDecline, directionalCooldown, isRecordedDecline, REMOVE_COOLDOWN_MS } from "./friendsCooldowns.js";
import { friendDocument, isIncomingRequest } from "./friendsDocuments.js";
import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { dataOf, readAction, readUid, requireAuthUid } from "./friendsParsing.js";
import { blockRef, cooldownRef, friendRef, profileRef, rateRef, requestRef } from "./friendsPaths.js";
import { socialProfile } from "./friendsProfiles.js";
import { writeOutstandingDelta } from "./friendsRateLimits.js";
import type { FriendsCallableRequest, FriendsDependencies } from "./friendsTypes.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../security/accountStatus.js";

export async function respondToFriendRequest(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const senderUid = readUid(request.data, "senderUid");
  const action = readAction(request.data);
  const atMs = dependencies.nowMs();
  const at = Timestamp.fromMillis(atMs);
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const incomingReference = requestRef(dependencies.firestore, uid, senderUid);
    const outgoingReference = requestRef(dependencies.firestore, senderUid, uid);
    const senderRateReference = rateRef(dependencies.firestore, senderUid);
    const cooldownReference = cooldownRef(dependencies.firestore, uid, senderUid);
    const [incomingSnapshot, localFriendSnapshot, remoteFriendSnapshot, senderRateSnapshot,
      cooldownSnapshot, localBlockSnapshot, remoteBlockSnapshot] = await Promise.all([
      transaction.get(incomingReference),
      transaction.get(friendRef(dependencies.firestore, uid, senderUid)),
      transaction.get(friendRef(dependencies.firestore, senderUid, uid)),
      transaction.get(senderRateReference),
      transaction.get(cooldownReference),
      transaction.get(blockRef(dependencies.firestore, uid, senderUid)),
      transaction.get(blockRef(dependencies.firestore, senderUid, uid)),
    ]);
    if (action === "accept" && localFriendSnapshot.exists && remoteFriendSnapshot.exists) {
      return { status: "ACCEPTED" };
    }
    if (action === "decline" && localFriendSnapshot.exists && remoteFriendSnapshot.exists) {
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    if (!incomingSnapshot.exists) {
      if (action === "decline" && isRecordedDecline(dataOf(cooldownSnapshot), senderUid)) {
        return { status: "DECLINED" };
      }
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    if (!isIncomingRequest(dataOf(incomingSnapshot), senderUid, uid)) {
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    if (action === "decline") {
      transaction.delete(incomingReference);
      transaction.delete(outgoingReference);
      transaction.set(cooldownReference, directionalCooldown(
        dataOf(cooldownSnapshot), senderUid, atMs + DECLINE_COOLDOWN_MS, at,
      ), { merge: true });
      writeOutstandingDelta(transaction, senderRateReference, dataOf(senderRateSnapshot), -1);
      return { status: "DECLINED" };
    }
    if (localBlockSnapshot.exists || remoteBlockSnapshot.exists) {
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    const [localProfileSnapshot, remoteProfileSnapshot] = await Promise.all([
      transaction.get(profileRef(dependencies.firestore, uid)),
      transaction.get(profileRef(dependencies.firestore, senderUid)),
    ]);
    const localProfile = socialProfile(uid, dataOf(localProfileSnapshot));
    const remoteProfile = socialProfile(senderUid, dataOf(remoteProfileSnapshot));
    if (localProfile === undefined || remoteProfile === undefined) throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    transaction.set(friendRef(dependencies.firestore, uid, senderUid), friendDocument(remoteProfile, at));
    transaction.set(friendRef(dependencies.firestore, senderUid, uid), friendDocument(localProfile, at));
    transaction.delete(incomingReference);
    transaction.delete(outgoingReference);
    transaction.set(cooldownReference, clearRecordedDecline(at), { merge: true });
    writeOutstandingDelta(transaction, senderRateReference, dataOf(senderRateSnapshot), -1);
    return { status: "ACCEPTED" };
  });
}

export async function removeFriend(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const friendUid = readUid(request.data, "friendUid");
  const atMs = dependencies.nowMs();
  const at = Timestamp.fromMillis(atMs);
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const localReference = friendRef(dependencies.firestore, uid, friendUid);
    const remoteReference = friendRef(dependencies.firestore, friendUid, uid);
    const cooldownReference = cooldownRef(dependencies.firestore, uid, friendUid);
    const [localSnapshot, remoteSnapshot] = await Promise.all([
      transaction.get(localReference),
      transaction.get(remoteReference),
    ]);
    if (!localSnapshot.exists && !remoteSnapshot.exists) return { removed: false };
    transaction.delete(localReference);
    transaction.delete(remoteReference);
    transaction.set(cooldownReference, {
      pairCooldownUntilMs: atMs + REMOVE_COOLDOWN_MS,
      ...clearRecordedDecline(at),
    }, { merge: true });
    return { removed: true };
  });
}
