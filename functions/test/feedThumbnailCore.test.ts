import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { readFeedThumbnail, type FeedThumbnailPorts } from "../src/feed/thumbnail/core.js";

const owner = "author-a";
const viewer = "friend-a";
const postId = "activity-a";
const path = `feed-thumbnails/${owner}/${postId}/route-preview.png`;

describe("Feed thumbnail core", () => {
  it("returns bounded bytes for the owner and reciprocal current friend, never a URL", async () => {
    const ports = fakePorts();
    const ownerResult = await readFeedThumbnail({ auth: { uid: owner }, data: { postId } }, ports);
    const friendResult = await readFeedThumbnail({ auth: { uid: viewer }, data: { postId } }, ports);
    assert.equal(ownerResult.contentType, "image/png");
    assert.equal(ownerResult.generation, "1");
    assert.equal(friendResult.sha256, "a".repeat(64));
    assert.equal("url" in friendResult, false);
    assert.equal(Buffer.from(friendResult.base64Png, "base64").byteLength <= 1_048_576, true);
    assert.equal(ports.relationshipReads, 1);
  });

  it("rejects unauthenticated, unknown-key, missing-friend, revoked, block, and hidden access", async () => {
    const ports = fakePorts();
    await rejects(() => readFeedThumbnail({ data: { postId } }, ports), "unauthenticated");
    await rejects(() => readFeedThumbnail({ auth: { uid: viewer }, data: { postId, extra: true } }, ports), "invalid-argument");
    for (const relationship of [
      { viewerHasAuthorFriend: false }, { authorHasViewerFriend: false }, { viewerBlockedAuthor: true }, { authorBlockedViewer: true },
    ]) {
      Object.assign(ports.relationship, relationship);
      await rejects(() => readFeedThumbnail({ auth: { uid: viewer }, data: { postId } }, ports), "permission-denied");
      Object.assign(ports.relationship, { viewerHasAuthorFriend: true, authorHasViewerFriend: true, viewerBlockedAuthor: false, authorBlockedViewer: false });
    }
    ports.hidden = true;
    await rejects(() => readFeedThumbnail({ auth: { uid: viewer }, data: { postId } }, ports), "permission-denied");
  });

  it("rejects inactive posts, staged/substituted paths, overwritten generations, hash mismatches, malformed PNGs, and oversized bytes", async () => {
    const ports = fakePorts();
    for (const post of [
      { ...publishedPost(), status: "deleting" }, { ...publishedPost(), status: "deleted" }, { ...publishedPost(), status: "draft" }, { ...publishedPost(), thumbnailStoragePath: `feed-thumbnail-staging/${owner}/${postId}/upload.png` }, { ...publishedPost(), thumbnailSha256: "b".repeat(64) },
    ]) {
      ports.post = post;
      await rejects(() => readFeedThumbnail({ auth: { uid: viewer }, data: { postId } }, ports), "failed-precondition");
    }
    ports.post = publishedPost();
    for (const object of [stored({ path: "feed-thumbnails/other/substituted.png" }), stored({ generation: "2" }), stored({ metadata: { sha256: "b".repeat(64) } }), stored({ bytes: png(88, 87) }), stored({ bytes: new Uint8Array(1_048_577) })]) {
      ports.object = object;
      await rejects(() => readFeedThumbnail({ auth: { uid: viewer }, data: { postId } }, ports), "failed-precondition");
    }
  });
});

type Stored = { readonly path: string; readonly generation: string; readonly bytes: Uint8Array; readonly contentType: string; readonly metadata: Readonly<Record<string, string>> };
class FakePorts implements FeedThumbnailPorts {
  post: unknown = publishedPost();
  object: Stored | undefined = stored();
  hidden = false;
  relationshipReads = 0;
  relationship = { viewerUid: viewer, authorUid: owner, viewerHasAuthorFriend: true, authorHasViewerFriend: true, viewerBlockedAuthor: false, authorBlockedViewer: false };
  async readPost(): Promise<unknown> { return this.post; }
  async isHidden(): Promise<boolean> { return this.hidden; }
  async relationshipFor(): Promise<typeof this.relationship> { this.relationshipReads += 1; return this.relationship; }
  async readObject(): Promise<Stored | undefined> { return this.object; }
  sha256(_bytes: Uint8Array): string { return "a".repeat(64); }
}
function fakePorts(): FakePorts { return new FakePorts(); }
function publishedPost(): Record<string, unknown> { return { authorUid: owner, activityId: postId, thumbnailStoragePath: path, thumbnailObjectGeneration: "1", thumbnailSha256: "a".repeat(64), status: "published" }; }
function stored(overrides: Partial<Stored> = {}): Stored { return { path: overrides.path ?? path, generation: overrides.generation ?? "1", bytes: overrides.bytes ?? png(88, 88), contentType: overrides.contentType ?? "image/png", metadata: overrides.metadata ?? { sha256: "a".repeat(64) } }; }
async function rejects(action: () => Promise<unknown>, code: string): Promise<void> { await assert.rejects(action, (error: unknown) => typeof error === "object" && error !== null && "code" in error && error["code"] === code); }
function png(width: number, height: number): Uint8Array { return Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, ...chunk("IHDR", [...u32(width), ...u32(height), 8, 6, 0, 0, 0]), ...chunk("IDAT", [0]), ...chunk("IEND", [])]); }
function u32(value: number): number[] { return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255]; }
function chunk(type: string, data: readonly number[]): number[] { const typeBytes = [...type].map((character) => character.charCodeAt(0)); return [...u32(data.length), ...typeBytes, ...data, ...u32(crc32([...typeBytes, ...data]))]; }
function crc32(bytes: readonly number[]): number { let crc = 0xffff_ffff; for (const value of bytes) { crc ^= value; for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1; } return (crc ^ 0xffff_ffff) >>> 0; }
