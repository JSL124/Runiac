import { HttpsError } from "firebase-functions/v2/https";
import type { FeedRelationshipCheckInput } from "../relationship.js";
import { evaluateFeedRelationship } from "../relationship.js";
import { validateFeedThumbnailPng } from "../png.js";
import type { FeedStoredObject } from "../publish/core.js";

export type FeedThumbnailRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };
export type FeedThumbnailResult = { readonly base64Png: string; readonly contentType: "image/png"; readonly generation: string; readonly sha256: string };
export interface FeedThumbnailPorts {
  readPost(postId: string): Promise<unknown>;
  isHidden(uid: string, postId: string): Promise<boolean>;
  relationshipFor(viewerUid: string, authorUid: string): Promise<FeedRelationshipCheckInput>;
  readObject(path: string, generation: string): Promise<FeedStoredObject | undefined>;
  sha256(bytes: Uint8Array): string;
}

export async function readFeedThumbnail(request: FeedThumbnailRequest, ports: FeedThumbnailPorts): Promise<FeedThumbnailResult> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) throw new HttpsError("unauthenticated", "Authentication is required.");
  const postId = parsePostId(request.data);
  if (postId === undefined) throw new HttpsError("invalid-argument", "Invalid thumbnail request.");
  const post = await ports.readPost(postId);
  if (!isPublishedPost(post) || post.activityId !== postId || post.thumbnailStoragePath !== finalThumbnailPath(post.authorUid, postId)) throw new HttpsError("failed-precondition", "Post thumbnail is unavailable.");
  if (await ports.isHidden(uid, postId)) throw new HttpsError("permission-denied", "Post is hidden for this user.");
  if (uid !== post.authorUid) {
    const relationship = evaluateFeedRelationship(await ports.relationshipFor(uid, post.authorUid));
    if (relationship.kind === "denied") throw new HttpsError("permission-denied", "Post is unavailable.");
  }
  const object = await ports.readObject(post.thumbnailStoragePath, post.thumbnailObjectGeneration);
  if (object === undefined || !matchesPostObject(object, post, ports.sha256)) throw new HttpsError("failed-precondition", "Post thumbnail is invalid.");
  return { base64Png: Buffer.from(object.bytes).toString("base64"), contentType: "image/png", generation: object.generation, sha256: post.thumbnailSha256 };
}

type PublishedPost = { readonly authorUid: string; readonly activityId: string; readonly thumbnailStoragePath: string; readonly thumbnailObjectGeneration: string; readonly thumbnailSha256: string; readonly status: "published" };
function parsePostId(raw: unknown): string | undefined { return isRecord(raw) && Object.keys(raw).length === 1 && isIdentifier(raw["postId"]) ? raw["postId"] : undefined; }
function isPublishedPost(raw: unknown): raw is PublishedPost { return isRecord(raw) && isIdentifier(raw["authorUid"]) && isIdentifier(raw["activityId"]) && typeof raw["thumbnailStoragePath"] === "string" && isIdentifier(raw["thumbnailObjectGeneration"]) && /^[a-f0-9]{64}$/.test(stringOrEmpty(raw["thumbnailSha256"])) && raw["status"] === "published"; }
function matchesPostObject(object: FeedStoredObject, post: PublishedPost, hash: (bytes: Uint8Array) => string): boolean { return object.path === post.thumbnailStoragePath && object.generation === post.thumbnailObjectGeneration && object.contentType === "image/png" && object.metadata["sha256"] === post.thumbnailSha256 && validateFeedThumbnailPng(object.bytes).ok && hash(object.bytes) === post.thumbnailSha256; }
function finalThumbnailPath(authorUid: string, postId: string): string { return `feed-thumbnails/${authorUid}/${postId}/route-preview.png`; }
function isIdentifier(value: unknown): value is string { return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value); }
function stringOrEmpty(value: unknown): string { return typeof value === "string" ? value : ""; }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
