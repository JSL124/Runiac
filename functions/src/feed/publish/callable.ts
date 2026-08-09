import { createHash } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onCall } from "firebase-functions/v2/https";
import { publishFeedActivity, type FeedPublishPorts, type FeedStoredObject } from "./core.js";
import { assertShareRouteToFeedEntitlement } from "./entitlement.js";
import { loadFeatureAccessConfig } from "../../config/configLoader.js";
import { withCallableErrorReporting } from "../../errors/withErrorReporting.js";
import { assertAccountNotSuspended } from "../../security/accountStatus.js";

if (getApps().length === 0) initializeApp();

type PublishActivityToFeedRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

export const publishActivityToFeed = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("publishActivityToFeed", async (request: PublishActivityToFeedRequest) => {
    // Defence-in-depth (see accountStatus.ts) plus the Feed premium
    // entitlement gate. Both are checked here in the onCall wrapper rather than
    // inside publishFeedActivity's port-based core, which stays unit-testable
    // with fake ports and no real Firestore. Skips silently when uid is absent
    // so the core's own unauthenticated path is unaffected. The single
    // users/{uid} read serves both the suspension check and the premium check;
    // the feature-access config decides whether sharing to Feed requires
    // Premium (config-driven, admin-console-administered). Enforcing it here —
    // not only by hiding client UI — is required because the client gate is UX
    // only and a Basic user can call the callable directly.
    const firestore = getFirestore();
    const uid = request.auth?.uid;
    if (uid !== undefined && uid.length > 0) {
      const snapshot = await firestore.collection("users").doc(uid).get();
      assertAccountNotSuspended(snapshot.data());
      const featureAccess = await loadFeatureAccessConfig(firestore);
      assertShareRouteToFeedEntitlement(snapshot.data(), featureAccess, Date.now());
    }
    const callableRequest = request.auth === undefined ? { data: request.data } : { auth: { uid: request.auth.uid }, data: request.data };
    return publishFeedActivity(callableRequest, createPublishPorts(firestore));
  }),
);

export function createPublishPorts(firestore: Firestore): FeedPublishPorts {
  const bucket = getStorage().bucket();
  return {
    async readActivity(activityId) { return (await firestore.doc(`activities/${activityId}`).get()).data(); },
    async readProfile(uid) { return (await firestore.doc(`userProfiles/${uid}`).get()).data(); },
    async readPost(postId) { return (await firestore.doc(`feedPosts/${postId}`).get()).data(); },
    async readObject(path, generation) { return readStoredObject(bucket, path, generation); },
    async copyCreateOnly(sourcePath, destinationPath, sha256) {
      try {
        await bucket.file(sourcePath).copy(bucket.file(destinationPath), { contentType: "image/png", metadata: { sha256 }, preconditionOpts: { ifGenerationMatch: 0 } });
      } catch (error: unknown) {
        if (!isPreconditionFailure(error)) throw error;
      }
    },
    async createPostIfAbsent(postId, post) {
      return firestore.runTransaction(async (transaction) => {
        const reference = firestore.doc(`feedPosts/${postId}`);
        const snapshot = await transaction.get(reference);
        if (snapshot.exists) return snapshot.data();
        transaction.create(reference, post);
        return post;
      });
    },
    async deleteObject(path) { await bucket.file(path).delete({ ignoreNotFound: true }); },
    now() { return new Date().toISOString(); },
    sha256(bytes) { return createHash("sha256").update(bytes).digest("hex"); },
  };
}

async function readStoredObject(bucket: ReturnType<ReturnType<typeof getStorage>["bucket"]>, path: string, generation?: string): Promise<FeedStoredObject | undefined> {
  const file = generation === undefined ? bucket.file(path) : bucket.file(path, { generation });
  const [exists] = await file.exists();
  if (!exists) return undefined;
  const [metadata] = await file.getMetadata();
  const [bytes] = await file.download();
  const objectGeneration = metadata.generation;
  if (objectGeneration === undefined) return undefined;
  return { path, generation: String(objectGeneration), bytes, contentType: metadata.contentType ?? "", metadata: stringMap(metadata.metadata) };
}
function stringMap(value: unknown): Readonly<Record<string, string>> {
  if (!isRecord(value)) return {};
  return Object.fromEntries(Object.entries(value).filter((entry): entry is [string, string] => typeof entry[1] === "string"));
}
function isPreconditionFailure(error: unknown): boolean { return isRecord(error) && (error["code"] === 409 || error["code"] === 412); }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
