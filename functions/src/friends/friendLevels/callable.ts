import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { getFriendLevels as getFriendLevelsCore, type FriendLevelsPorts } from "./core.js";
import { blockRef, friendRef, profileRef, requestRef } from "../friendsPaths.js";
import { withCallableErrorReporting } from "../../errors/withErrorReporting.js";
import { avatarUrlContextFromEnvironment } from "../../profile/avatar/context.js";

if (getApps().length === 0) initializeApp();

type GetFriendLevelsRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

export const getFriendLevels = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("getFriendLevels", async (request: GetFriendLevelsRequest) => {
    const callableRequest = request.auth === undefined ? { data: request.data } : { auth: { uid: request.auth.uid }, data: request.data };
    return getFriendLevelsCore(callableRequest, createFriendLevelsPorts(getFirestore()), avatarUrlContextFromEnvironment());
  }),
);

export function createFriendLevelsPorts(firestore: Firestore): FriendLevelsPorts {
  return {
    async hasSocialEdge(callerUid, uid) {
      const [friend, requestDoc, block] = await Promise.all([
        friendRef(firestore, callerUid, uid).get(),
        requestRef(firestore, callerUid, uid).get(),
        blockRef(firestore, callerUid, uid).get(),
      ]);
      return friend.exists || requestDoc.exists || block.exists;
    },
    async readProfiles(uids) {
      if (uids.length === 0) return [];
      const snaps = await firestore.getAll(...uids.map((uid) => profileRef(firestore, uid)));
      return snaps.map((snap) => snap.data());
    },
  };
}
