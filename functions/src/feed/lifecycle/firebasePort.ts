import { FieldValue, getFirestore, type Firestore, type Transaction } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import type {
  FeedLifecyclePort,
  FeedLifecycleTransaction,
  FeedReport,
  LifecyclePost,
  LifecycleStepResult,
} from "./types.js";

const batchLimit = 200;

export function firebaseLifecyclePort(firestore: Firestore = getFirestore()): FeedLifecyclePort {
  return {
    runTransaction: async (operation) => firestore.runTransaction(async (transaction) => operation(firebaseTransaction(firestore, transaction))),
    now: () => FieldValue.serverTimestamp(),
    deleteLikes: async (postId) => deleteCollection(firestore, `feedPosts/${postId}/likes`),
    deleteComments: async (postId) => deleteCollection(firestore, `feedPosts/${postId}/comments`),
    deleteReportsAndHiddenMarkers: async (postId) => deleteReportsAndMarkers(firestore, postId),
    deleteExactThumbnail: async (post) => deleteThumbnail(post),
    deletePost: async (postId) => deleteDocument(firestore, `feedPosts/${postId}`),
  };
}

function firebaseTransaction(firestore: Firestore, transaction: Transaction): FeedLifecycleTransaction {
  return {
    getPost: async (postId) => {
      const snapshot = await transaction.get(firestore.doc(`feedPosts/${postId}`));
      return snapshot.exists ? parsePost(postId, snapshot.data()) : null;
    },
    canReadPost: async (viewerUid, post) => canReadPost(firestore, transaction, viewerUid, post),
    getReport: async (reportId) => {
      const snapshot = await transaction.get(firestore.doc(`reports/${reportId}`));
      return snapshot.exists ? parseReport(snapshot.data()) : null;
    },
    setReport: (reportId, report) => transaction.set(firestore.doc(`reports/${reportId}`), report),
    setHiddenMarker: (uid, postId, createdAt) => transaction.set(firestore.doc(`users/${uid}/hiddenFeedPosts/${postId}`), { postId, createdAt }),
    setDeleting: (postId) => transaction.update(firestore.doc(`feedPosts/${postId}`), { status: "deleting", updatedAt: FieldValue.serverTimestamp() }),
  };
}

async function canReadPost(firestore: Firestore, transaction: Transaction, viewerUid: string, post: LifecyclePost): Promise<boolean> {
  if (viewerUid === post.authorUid) return true;
  const [viewerFriend, authorFriend, viewerBlock, authorBlock] = await Promise.all([
    transaction.get(firestore.doc(`users/${viewerUid}/friends/${post.authorUid}`)),
    transaction.get(firestore.doc(`users/${post.authorUid}/friends/${viewerUid}`)),
    transaction.get(firestore.doc(`users/${viewerUid}/blockedUsers/${post.authorUid}`)),
    transaction.get(firestore.doc(`users/${post.authorUid}/blockedUsers/${viewerUid}`)),
  ]);
  return viewerFriend.exists && authorFriend.exists && !viewerBlock.exists && !authorBlock.exists;
}

async function deleteCollection(firestore: Firestore, path: string): Promise<LifecycleStepResult> {
  return operation(async () => {
    let deleted = false;
    for (;;) {
      const snapshot = await firestore.collection(path).limit(batchLimit).get();
      if (snapshot.empty) return deleted ? { kind: "completed" } : { kind: "already_missing" };
      const batch = firestore.batch();
      for (const document of snapshot.docs) batch.delete(document.ref);
      await batch.commit();
      deleted = true;
    }
  });
}

async function deleteReportsAndMarkers(firestore: Firestore, postId: string): Promise<LifecycleStepResult> {
  return operation(async () => {
    let deleted = false;
    for (;;) {
      const snapshot = await firestore.collection("reports").where("targetType", "==", "feedPost").where("targetId", "==", postId).limit(batchLimit).get();
      if (snapshot.empty) return deleted ? { kind: "completed" } : { kind: "already_missing" };
      const batch = firestore.batch();
      for (const document of snapshot.docs) {
        const reporterUid = readString(document.data(), "reporterUid");
        if (reporterUid === null) return { kind: "retry_required" };
        batch.delete(document.ref);
        batch.delete(firestore.doc(`users/${reporterUid}/hiddenFeedPosts/${postId}`));
      }
      await batch.commit();
      deleted = true;
    }
  });
}

async function deleteThumbnail(post: LifecyclePost): Promise<LifecycleStepResult> {
  try {
    await getStorage().bucket().file(post.thumbnailStoragePath).delete({ ifGenerationMatch: post.thumbnailObjectGeneration, ignoreNotFound: true });
    return { kind: "completed" };
  } catch (error) {
    return storageFailure(error);
  }
}

async function deleteDocument(firestore: Firestore, path: string): Promise<LifecycleStepResult> {
  return operation(async () => {
    await firestore.doc(path).delete();
    return { kind: "completed" };
  });
}

async function operation(run: () => Promise<LifecycleStepResult>): Promise<LifecycleStepResult> {
  try {
    return await run();
  } catch (error) {
    return firestoreFailure(error);
  }
}

function storageFailure(error: unknown): LifecycleStepResult {
  const code = errorCode(error);
  if (code === 404) return { kind: "already_missing" };
  return { kind: "retry_required" };
}

function firestoreFailure(_error: unknown): LifecycleStepResult { return { kind: "retry_required" }; }

function parsePost(postId: string, raw: unknown): LifecyclePost | null {
  const authorUid = readString(raw, "authorUid");
  const status = readString(raw, "status");
  const thumbnailStoragePath = readString(raw, "thumbnailStoragePath");
  const thumbnailObjectGeneration = readString(raw, "thumbnailObjectGeneration");
  if (authorUid === null || thumbnailStoragePath === null || thumbnailObjectGeneration === null) return null;
  if (status !== "published" && status !== "deleting") return null;
  if (thumbnailStoragePath !== `feed-thumbnails/${authorUid}/${postId}/route-preview.png`) return null;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(thumbnailObjectGeneration)) return null;
  return { postId, authorUid, status, thumbnailStoragePath, thumbnailObjectGeneration };
}

function parseReport(raw: unknown): FeedReport | null {
  const reporterUid = readString(raw, "reporterUid");
  const targetType = readString(raw, "targetType");
  const targetId = readString(raw, "targetId");
  const reason = readString(raw, "reason");
  const description = readString(raw, "description");
  if (reporterUid === null || targetType !== "feedPost" || targetId === null || reason !== "feed_inappropriate" || description !== "") return null;
  return { reporterUid, targetType, targetId, reason, description, createdAt: readValue(raw, "createdAt") };
}

function readString(raw: unknown, key: string): string | null {
  const value = readValue(raw, key);
  return typeof value === "string" ? value : null;
}

function readValue(raw: unknown, key: string): unknown {
  return isRecord(raw) ? raw[key] : undefined;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function errorCode(error: unknown): number | null {
  if (!isRecord(error)) return null;
  const code = error["code"];
  return typeof code === "number" ? code : null;
}
