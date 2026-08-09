import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { getFeedAuthorLevels as getFeedAuthorLevelsCore, type FeedAuthorLevelsPorts } from "./core.js";
import { withCallableErrorReporting } from "../../errors/withErrorReporting.js";
import { avatarUrlContextFromEnvironment } from "../../profile/avatar/context.js";

if (getApps().length === 0) initializeApp();

type GetFeedAuthorLevelsRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

export const getFeedAuthorLevels = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("getFeedAuthorLevels", async (request: GetFeedAuthorLevelsRequest) => {
    const callableRequest = request.auth === undefined ? { data: request.data } : { auth: { uid: request.auth.uid }, data: request.data };
    return getFeedAuthorLevelsCore(callableRequest, createAuthorLevelsPorts(getFirestore()), avatarUrlContextFromEnvironment());
  }),
);

export function createAuthorLevelsPorts(firestore: Firestore): FeedAuthorLevelsPorts {
  return {
    async relationshipFor(viewerUid, authorUid) {
      const [viewerFriend, authorFriend, viewerBlock, authorBlock] = await Promise.all([
        firestore.doc(`users/${viewerUid}/friends/${authorUid}`).get(), firestore.doc(`users/${authorUid}/friends/${viewerUid}`).get(),
        firestore.doc(`users/${viewerUid}/blockedUsers/${authorUid}`).get(), firestore.doc(`users/${authorUid}/blockedUsers/${viewerUid}`).get(),
      ]);
      return { viewerUid, authorUid, viewerHasAuthorFriend: viewerFriend.exists, authorHasViewerFriend: authorFriend.exists, viewerBlockedAuthor: viewerBlock.exists, authorBlockedViewer: authorBlock.exists };
    },
    async readProfiles(uids) {
      if (uids.length === 0) return [];
      const snaps = await firestore.getAll(...uids.map((uid) => firestore.doc(`userProfiles/${uid}`)));
      return snaps.map((snap) => snap.data());
    },
    async readPost(postId) {
      const snapshot = await firestore.doc(`feedPosts/${postId}`).get();
      const data = snapshot.data();
      if (data === undefined) return undefined;
      const status = data["status"];
      const authorUid = data["authorUid"];
      if (typeof status !== "string" || typeof authorUid !== "string" || authorUid.length === 0) return undefined;
      return { status, authorUid };
    },
    async commentAuthorsAmong(postId, uids) {
      if (uids.length === 0) return [];
      // Firestore caps an `in` filter at 30 values and the callable caps the
      // request at 50 uids, so this is at most two equality queries against
      // the automatically indexed `authorUid` field — no composite index.
      const chunks: string[][] = [];
      for (let index = 0; index < uids.length; index += IN_FILTER_LIMIT) chunks.push(uids.slice(index, index + IN_FILTER_LIMIT));
      const results = await Promise.all(
        chunks.map((chunk) => firestore.collection(`feedPosts/${postId}/comments`).where("authorUid", "in", chunk).select("authorUid").get()),
      );
      const found = new Set<string>();
      for (const result of results) {
        for (const doc of result.docs) {
          const authorUid = doc.get("authorUid");
          if (typeof authorUid === "string" && authorUid.length > 0) found.add(authorUid);
        }
      }
      return [...found];
    },
  };
}

const IN_FILTER_LIMIT = 30;
