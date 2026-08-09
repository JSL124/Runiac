import { HttpsError } from "firebase-functions/v2/https";
import {
  buildFeedPost,
  parsePublishFeedPayload,
  parseValidatedOwnedActivity,
  type FeedPost,
  type PrivateProfileSnapshot,
} from "../contracts.js";
import { validateFeedThumbnailPng } from "../png.js";

export type FeedStoredObject = {
  readonly path: string;
  readonly generation: string;
  readonly bytes: Uint8Array;
  readonly contentType: string;
  readonly metadata: Readonly<Record<string, string>>;
};
export type FeedPublishRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };
export type FeedPublishResult = { readonly postId: string; readonly thumbnailObjectGeneration: string; readonly thumbnailSha256: string };
export interface FeedPublishPorts {
  readActivity(activityId: string): Promise<unknown>;
  readProfile(uid: string): Promise<unknown>;
  readPost(postId: string): Promise<unknown>;
  readObject(path: string, generation?: string): Promise<FeedStoredObject | undefined>;
  copyCreateOnly(sourcePath: string, destinationPath: string, sha256: string): Promise<void>;
  createPostIfAbsent(postId: string, post: FeedPost): Promise<unknown>;
  deleteObject(path: string): Promise<void>;
  now(): string;
  sha256(bytes: Uint8Array): string;
}

export async function publishFeedActivity(request: FeedPublishRequest, ports: FeedPublishPorts): Promise<FeedPublishResult> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) throw new HttpsError("unauthenticated", "Authentication is required.");
  const parsed = parsePublishFeedPayload(request.data, uid);
  if (!parsed.ok) throw new HttpsError("invalid-argument", "Invalid publish request.");
  const { activityId, stagingPath } = parsed.value;
  const activityResult = parseValidatedOwnedActivity(await ports.readActivity(activityId), uid, activityId);
  if (!activityResult.ok) throw new HttpsError("failed-precondition", "Activity is not publishable.");
  const existing = await ports.readPost(activityId);
  if (existing !== undefined) return resolveExistingPost(existing, activityId, uid, stagingPath, ports);
  const profile = parseProfile(await ports.readProfile(uid), uid);
  if (profile === undefined) throw new HttpsError("failed-precondition", "Profile snapshot is unavailable.");
  const staging = await ports.readObject(stagingPath);
  if (staging === undefined || !isSafeStagingObject(staging, stagingPath, uid, activityId)) throw new HttpsError("failed-precondition", "Staging thumbnail is invalid.");
  const sha256 = ports.sha256(staging.bytes);
  const finalPath = finalThumbnailPath(uid, activityId);
  await ports.copyCreateOnly(stagingPath, finalPath, sha256);
  const final = await ports.readObject(finalPath);
  if (final === undefined || !matchesFinalObject(final, finalPath, sha256, ports.sha256)) throw new HttpsError("failed-precondition", "Final thumbnail is invalid.");
  const built = buildFeedPost({ activity: activityResult.value, profile, thumbnail: { storagePath: finalPath, objectGeneration: final.generation, sha256 }, now: ports.now() });
  if (!built.ok) throw new HttpsError("failed-precondition", "Publish state is invalid.");
  const persisted = await ports.createPostIfAbsent(activityId, built.value);
  if (!samePublishedPost(persisted, built.value)) throw new HttpsError("failed-precondition", "Existing post conflicts with activity.");
  await ports.deleteObject(stagingPath);
  return resultFor(built.value);
}

async function resolveExistingPost(raw: unknown, activityId: string, uid: string, stagingPath: string, ports: FeedPublishPorts): Promise<FeedPublishResult> {
  if (!isFeedPost(raw) || raw.activityId !== activityId || raw.authorUid !== uid || raw.status !== "published") throw new HttpsError("failed-precondition", "Existing post conflicts with activity.");
  const object = await ports.readObject(raw.thumbnailStoragePath, raw.thumbnailObjectGeneration);
  if (object === undefined || !matchesFinalObject(object, finalThumbnailPath(uid, activityId), raw.thumbnailSha256, ports.sha256)) throw new HttpsError("failed-precondition", "Existing thumbnail is invalid.");
  const staging = await ports.readObject(stagingPath);
  if (staging !== undefined) {
    if (!isSafeStagingObject(staging, stagingPath, uid, activityId)) throw new HttpsError("failed-precondition", "Retry staging thumbnail is invalid.");
    await ports.deleteObject(stagingPath);
  }
  return resultFor(raw);
}

function parseProfile(raw: unknown, uid: string): PrivateProfileSnapshot | undefined {
  if (!isRecord(raw) || typeof raw["displayName"] !== "string" || typeof raw["avatarInitials"] !== "string") return undefined;
  return { uid, displayName: raw["displayName"], avatarInitials: raw["avatarInitials"], levelLabel: typeof raw["levelLabel"] === "string" ? raw["levelLabel"] : "" };
}
function isSafeStagingObject(object: FeedStoredObject, expectedPath: string, ownerUid: string, activityId: string): boolean {
  const uploadId = expectedPath.split("/")[3];
  return object.path === expectedPath && object.contentType === "image/png" && uploadId !== undefined && hasSafeStagingMetadata(object.metadata, ownerUid, activityId, uploadId) && validateFeedThumbnailPng(object.bytes).ok;
}
function hasSafeStagingMetadata(metadata: Readonly<Record<string, string>>, ownerUid: string, activityId: string, uploadId: string): boolean {
  const keys = Object.keys(metadata);
  const hasManagedDownloadToken = typeof metadata["firebaseStorageDownloadTokens"] === "string" && metadata["firebaseStorageDownloadTokens"].length > 0;
  const hasExactKeys = keys.length === 3 || (keys.length === 4 && hasManagedDownloadToken);
  return hasExactKeys && metadata["ownerUid"] === ownerUid && metadata["activityId"] === activityId && metadata["uploadId"] === uploadId;
}
function matchesFinalObject(object: FeedStoredObject, path: string, sha256: string, hash: (bytes: Uint8Array) => string): boolean {
  return object.path === path && object.contentType === "image/png" && object.metadata["sha256"] === sha256 && object.generation.length > 0 && validateFeedThumbnailPng(object.bytes).ok && sha256 === hash(object.bytes);
}
function finalThumbnailPath(uid: string, activityId: string): string { return `feed-thumbnails/${uid}/${activityId}/route-preview.png`; }
function resultFor(post: FeedPost): FeedPublishResult { return { postId: post.activityId, thumbnailObjectGeneration: post.thumbnailObjectGeneration, thumbnailSha256: post.thumbnailSha256 }; }
function samePublishedPost(raw: unknown, expected: FeedPost): raw is FeedPost { return isFeedPost(raw) && raw.authorUid === expected.authorUid && raw.activityId === expected.activityId && raw.status === "published" && raw.thumbnailStoragePath === expected.thumbnailStoragePath && raw.thumbnailObjectGeneration === expected.thumbnailObjectGeneration && raw.thumbnailSha256 === expected.thumbnailSha256; }
function isFeedPost(value: unknown): value is FeedPost { return isRecord(value) && typeof value["authorUid"] === "string" && typeof value["activityId"] === "string" && typeof value["thumbnailStoragePath"] === "string" && typeof value["thumbnailObjectGeneration"] === "string" && typeof value["thumbnailSha256"] === "string" && value["status"] === "published"; }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
