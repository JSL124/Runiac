import { createHash } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onCall } from "firebase-functions/v2/https";
import type { FeedStoredObject } from "../publish/core.js";
import { readFeedThumbnail as readFeedThumbnailCore, type FeedThumbnailPorts } from "./core.js";
import { withCallableErrorReporting } from "../../errors/withErrorReporting.js";

if (getApps().length === 0) initializeApp();

type ReadFeedThumbnailRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

export const readFeedThumbnail = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("readFeedThumbnail", async (request: ReadFeedThumbnailRequest) => {
    const callableRequest = request.auth === undefined ? { data: request.data } : { auth: { uid: request.auth.uid }, data: request.data };
    return readFeedThumbnailCore(callableRequest, createThumbnailPorts(getFirestore()));
  }),
);

export function createThumbnailPorts(firestore: Firestore): FeedThumbnailPorts {
  const bucket = getStorage().bucket();
  return {
    async readPost(postId) { return (await firestore.doc(`feedPosts/${postId}`).get()).data(); },
    async isHidden(uid, postId) { return (await firestore.doc(`users/${uid}/hiddenFeedPosts/${postId}`).get()).exists; },
    async relationshipFor(viewerUid, authorUid) {
      const [viewerFriend, authorFriend, viewerBlock, authorBlock] = await Promise.all([
        firestore.doc(`users/${viewerUid}/friends/${authorUid}`).get(), firestore.doc(`users/${authorUid}/friends/${viewerUid}`).get(),
        firestore.doc(`users/${viewerUid}/blockedUsers/${authorUid}`).get(), firestore.doc(`users/${authorUid}/blockedUsers/${viewerUid}`).get(),
      ]);
      return { viewerUid, authorUid, viewerHasAuthorFriend: viewerFriend.exists, authorHasViewerFriend: authorFriend.exists, viewerBlockedAuthor: viewerBlock.exists, authorBlockedViewer: authorBlock.exists };
    },
    async readObject(path, generation) { return readStoredObject(bucket, path, generation); },
    sha256(bytes) { return createHash("sha256").update(bytes).digest("hex"); },
  };
}

async function readStoredObject(bucket: ReturnType<ReturnType<typeof getStorage>["bucket"]>, path: string, generation: string): Promise<FeedStoredObject | undefined> {
  const file = bucket.file(path, { generation });
  const [exists] = await file.exists();
  if (!exists) return undefined;
  const [metadata] = await file.getMetadata();
  if (metadata.generation === undefined) return undefined;
  const [bytes] = await file.download();
  return { path, generation: String(metadata.generation), bytes, contentType: metadata.contentType ?? "", metadata: stringMap(metadata.metadata) };
}
function stringMap(value: unknown): Readonly<Record<string, string>> { return isRecord(value) ? Object.fromEntries(Object.entries(value).filter((entry): entry is [string, string] => typeof entry[1] === "string")) : {}; }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
