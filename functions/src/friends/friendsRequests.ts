import { Timestamp } from "firebase-admin/firestore";

import { cancellationCooldown, clearRecordedDecline, cooldownAllows, CANCEL_COOLDOWN_MS } from "./friendsCooldowns.js";
import { requestDocument, isOutgoingRequest } from "./friendsDocuments.js";
import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { dataOf, readUid, requireAuthUid } from "./friendsParsing.js";
import { blockRef, cooldownRef, friendRef, profileRef, rateRef, requestRef } from "./friendsPaths.js";
import { socialProfile } from "./friendsProfiles.js";
import {
  OUTSTANDING_REQUEST_LIMIT,
  nextRequestAttemptMs,
  outstandingOutgoing,
  writeOutstandingDelta,
  writeRequestRate,
} from "./friendsRateLimits.js";
import type { FriendsCallableRequest, FriendsDependencies } from "./friendsTypes.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../security/accountStatus.js";

export async function sendFriendRequest(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const targetUid = readUid(request.data, "targetUid");
  if (targetUid === uid) throw friendError(FRIEND_REASON.CANNOT_TARGET_SELF);
  const atMs = dependencies.nowMs();
  const at = Timestamp.fromMillis(atMs);
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const localRequestReference = requestRef(dependencies.firestore, uid, targetUid);
    const remoteRequestReference = requestRef(dependencies.firestore, targetUid, uid);
    const rateReference = rateRef(dependencies.firestore, uid);
    const cooldownReference = cooldownRef(dependencies.firestore, uid, targetUid);
    const snapshots = await Promise.all([
      transaction.get(profileRef(dependencies.firestore, uid)),
      transaction.get(profileRef(dependencies.firestore, targetUid)),
      transaction.get(blockRef(dependencies.firestore, uid, targetUid)),
      transaction.get(blockRef(dependencies.firestore, targetUid, uid)),
      transaction.get(friendRef(dependencies.firestore, uid, targetUid)),
      transaction.get(friendRef(dependencies.firestore, targetUid, uid)),
      transaction.get(localRequestReference),
      transaction.get(remoteRequestReference),
      transaction.get(rateReference),
      transaction.get(cooldownReference),
    ]);
    const [localProfileSnapshot, remoteProfileSnapshot, localBlockSnapshot, remoteBlockSnapshot,
      localFriendSnapshot, remoteFriendSnapshot, localRequestSnapshot, remoteRequestSnapshot,
      rateSnapshot, cooldownSnapshot] = snapshots;
    const localProfile = socialProfile(uid, dataOf(localProfileSnapshot));
    const remoteProfile = socialProfile(targetUid, dataOf(remoteProfileSnapshot));
    if (
      localProfile === undefined || remoteProfile === undefined ||
      localBlockSnapshot.exists || remoteBlockSnapshot.exists ||
      localFriendSnapshot.exists || remoteFriendSnapshot.exists
    ) {
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    if (localRequestSnapshot.exists && isOutgoingRequest(dataOf(localRequestSnapshot), uid, targetUid)) {
      return { status: "PENDING", created: false };
    }
    if (localRequestSnapshot.exists || remoteRequestSnapshot.exists) {
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    const rate = dataOf(rateSnapshot);
    if (!cooldownAllows(dataOf(cooldownSnapshot), uid, atMs) || outstandingOutgoing(rate) >= OUTSTANDING_REQUEST_LIMIT) {
      throw friendError(FRIEND_REASON.TRY_AGAIN_LATER);
    }
    const nextAttempts = nextRequestAttemptMs(rate, atMs);
    transaction.set(localRequestReference, requestDocument({
      senderUid: uid,
      recipientUid: targetUid,
      direction: "outgoing",
      profile: remoteProfile,
      at,
    }));
    transaction.set(remoteRequestReference, requestDocument({
      senderUid: uid,
      recipientUid: targetUid,
      direction: "incoming",
      profile: localProfile,
      at,
    }));
    transaction.set(cooldownReference, clearRecordedDecline(at), { merge: true });
    writeRequestRate(transaction, rateReference, rate, nextAttempts, 1);
    return { status: "PENDING", created: true };
  });
}

export async function cancelFriendRequest(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const targetUid = readUid(request.data, "targetUid");
  const atMs = dependencies.nowMs();
  const at = Timestamp.fromMillis(atMs);
  return dependencies.firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, dependencies.firestore, uid);
    const localRequestReference = requestRef(dependencies.firestore, uid, targetUid);
    const remoteRequestReference = requestRef(dependencies.firestore, targetUid, uid);
    const rateReference = rateRef(dependencies.firestore, uid);
    const cooldownReference = cooldownRef(dependencies.firestore, uid, targetUid);
    const [requestSnapshot, rateSnapshot, cooldownSnapshot] = await Promise.all([
      transaction.get(localRequestReference),
      transaction.get(rateReference),
      transaction.get(cooldownReference),
    ]);
    if (!requestSnapshot.exists) return { cancelled: false };
    if (!isOutgoingRequest(dataOf(requestSnapshot), uid, targetUid)) {
      throw friendError(FRIEND_REASON.STALE_SOCIAL_STATE);
    }
    transaction.delete(localRequestReference);
    transaction.delete(remoteRequestReference);
    transaction.set(cooldownReference, cancellationCooldown(
      dataOf(cooldownSnapshot), uid, atMs + CANCEL_COOLDOWN_MS, at,
    ), { merge: true });
    writeOutstandingDelta(transaction, rateReference, dataOf(rateSnapshot), -1);
    return { cancelled: true };
  });
}
