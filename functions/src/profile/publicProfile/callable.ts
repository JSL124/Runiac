import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { getRunnerPublicProfile as getRunnerPublicProfileCore, type RunnerPublicProfilePorts } from "./core.js";
import { withCallableErrorReporting } from "../../errors/withErrorReporting.js";
import { friendRef, requestRef } from "../../friends/friendsPaths.js";
import { instanceRef, readRoster, slotRef } from "../../challenge/challengeLobbySupport.js";
import { avatarUrlContextFromEnvironment } from "../avatar/context.js";

if (getApps().length === 0) initializeApp();

type GetRunnerPublicProfileRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

/**
 * Serves the public running-achievement projection of one runner to a signed-in
 * viewer. It exists because `users/{uid}`, `userProfiles/{uid}`, and
 * `users/{uid}/challengeBadges` are all owner-read-only in `firestore.rules`:
 * a viewer can never read another runner's documents directly, so the server
 * decides what leaves them.
 */
export const getRunnerPublicProfile = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("getRunnerPublicProfile", async (request: GetRunnerPublicProfileRequest) => {
    const callableRequest = request.auth === undefined ? { data: request.data } : { auth: { uid: request.auth.uid }, data: request.data };
    return getRunnerPublicProfileCore(callableRequest, createRunnerPublicProfilePorts(getFirestore()), avatarUrlContextFromEnvironment());
  }),
);

/** Badge tiers are one document per earned tier; nine tiers exist today. */
const BADGE_READ_LIMIT = 50;

export function createRunnerPublicProfilePorts(firestore: Firestore): RunnerPublicProfilePorts {
  return {
    async readBlockEdges(callerUid, targetUid) {
      const [callerBlock, targetBlock] = await Promise.all([
        firestore.doc(`users/${callerUid}/blockedUsers/${targetUid}`).get(),
        firestore.doc(`users/${targetUid}/blockedUsers/${callerUid}`).get(),
      ]);
      return { callerBlockedTarget: callerBlock.exists, targetBlockedCaller: targetBlock.exists };
    },
    async readProfile(uid) {
      const snapshot = await firestore.doc(`userProfiles/${uid}`).get();
      return snapshot.data();
    },
    async readAccount(uid) {
      const snapshot = await firestore.doc(`users/${uid}`).get();
      return snapshot.data();
    },
    async readOwnedBadgeTierIds(uid) {
      const snapshot = await firestore.collection(`users/${uid}/challengeBadges`).limit(BADGE_READ_LIMIT).get();
      return snapshot.docs.map((document) => document.id);
    },
    async resolveLeaderboardEntryOwner(snapshotId, rankLabel, buildId) {
      // Equality filters only, no ordering — served by single-field indexes,
      // so this needs no composite index. `limit(2)` is what makes an
      // ambiguous match detectable: exactly one rank projection may claim a
      // rank within a snapshot build, and anything else fails closed.
      const snapshot = await firestore
        .collection("leaderboardUserRanks")
        .where("snapshotId", "==", snapshotId)
        .where("rankLabel", "==", rankLabel)
        .where("buildId", "==", buildId)
        .limit(2)
        .get();
      if (snapshot.size !== 1) return undefined;
      const ownerUid = snapshot.docs[0]?.data()["ownerUid"];
      return typeof ownerUid === "string" && ownerUid.length > 0 ? ownerUid : undefined;
    },
    async readSocialEdge(callerUid, targetUid) {
      const [friend, request] = await Promise.all([
        friendRef(firestore, callerUid, targetUid).get(),
        requestRef(firestore, callerUid, targetUid).get(),
      ]);
      return friend.exists || request.exists;
    },
    async isChallengeCoMember(callerUid, targetUid) {
      const slotSnapshot = await slotRef(firestore, callerUid).get();
      const challengeId = slotSnapshot.data()?.["challengeId"];
      if (typeof challengeId !== "string" || challengeId.length === 0) return false;
      const instanceSnapshot = await instanceRef(firestore, challengeId).get();
      return readRoster(instanceSnapshot.data()).includes(targetUid);
    },
  };
}
