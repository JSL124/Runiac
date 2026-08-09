import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { publishFeedActivity, type FeedPublishPorts } from "../src/feed/publish/core.js";

const owner = "author-a";
const activityId = "activity-a";
const stagingPath = `feed-thumbnail-staging/${owner}/${activityId}/upload-a.png`;
const finalPath = `feed-thumbnails/${owner}/${activityId}/route-preview.png`;

describe("Feed publish core", () => {
  it("rejects unauthenticated, non-exact, invalid-activity, and unsafe staging requests", async () => {
    const ports = fakePorts();
    await rejects(() => publishFeedActivity({ data: request() }, ports), "unauthenticated");
    for (const data of [
      { ...request(), extra: true },
      { activityId, stagingPath: `feed-thumbnail-staging/${owner}/${activityId}/../upload-a.png` },
      { activityId, stagingPath: `feed-thumbnail-staging/other/${activityId}/upload-a.png` },
    ]) await rejects(() => publishFeedActivity({ auth: { uid: owner }, data }, ports), "invalid-argument");
    ports.activity = undefined;
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "failed-precondition");
    ports.activity = { ...activity(), ownerUid: "other" };
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "failed-precondition");
    ports.activity = { ...activity(), validationStatus: "pending" };
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "failed-precondition");
  });

  it("rejects missing, foreign, non-PNG, oversized, unsupported dimensions, and invalid staging metadata", async () => {
    const ports = fakePorts();
    for (const object of [
      undefined, stored("other/path.png"), stored(stagingPath, { contentType: "image/jpeg" }), stored(stagingPath, { bytes: new Uint8Array(1_048_577) }), stored(stagingPath, { bytes: png(343, 184) }), stored(stagingPath, { bytes: png(88, 87) }),
      stored(stagingPath, { metadata: {} }), stored(stagingPath, { metadata: { ownerUid: owner, activityId } }), stored(stagingPath, { metadata: { ownerUid: "other", activityId, uploadId: "upload-a.png" } }),
      stored(stagingPath, { metadata: { ownerUid: owner, activityId: "other", uploadId: "upload-a.png" } }), stored(stagingPath, { metadata: { ownerUid: owner, activityId, uploadId: "upload-a" } }),
      stored(stagingPath, { metadata: { ownerUid: owner, activityId, uploadId: "other.png" } }), stored(stagingPath, { metadata: { ...stagingMetadata(), trace: "x" } }),
    ]) {
      ports.staging = object;
      await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "failed-precondition");
    }
  });

  it("accepts current wide card thumbnail dimensions", async () => {
    const ports = fakePorts();
    ports.staging = stored(stagingPath, { bytes: png(1032, 552) });
    const result = await publishFeedActivity({ auth: { uid: owner }, data: request() }, ports);
    assert.equal(result.postId, activityId);
    assert.equal(ports.posts.size, 1);
    assert.equal(ports.staging, undefined);
  });

  it("accepts Firebase-managed staging download-token metadata", async () => {
    const ports = fakePorts();
    ports.staging = stored(stagingPath, {
      metadata: { ...stagingMetadata(), firebaseStorageDownloadTokens: "managed-token" },
    });
    const result = await publishFeedActivity({ auth: { uid: owner }, data: request() }, ports);
    assert.equal(result.postId, activityId);
  });

  it("rejects staging bytes that bypass structure checks with corrupt PNG checksums", async () => {
    const ports = fakePorts();
    ports.staging = stored(stagingPath, { bytes: corruptPng(88, 88) });
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "failed-precondition");
    assert.equal(ports.copyCount, 0);
    assert.equal(ports.final, undefined);
    assert.equal(ports.posts.size, 0);
    assert.notEqual(ports.staging, undefined);
  });

  it("creates one immutable post and converges after copy and transaction checkpoints", async () => {
    const ports = fakePorts();
    ports.failAfterCopy = true;
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "internal");
    const afterCopy = await publishFeedActivity({ auth: { uid: owner }, data: request() }, ports);
    assert.equal(afterCopy.thumbnailObjectGeneration, "1");
    assert.equal(ports.copyCount, 2);
    assert.equal(ports.posts.size, 1);
    assert.equal(ports.staging, undefined);

    const transactionRetry = fakePorts();
    transactionRetry.failAfterPost = true;
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, transactionRetry), "internal");
    const afterTransaction = await publishFeedActivity({ auth: { uid: owner }, data: request() }, transactionRetry);
    assert.equal(afterTransaction.thumbnailObjectGeneration, "1");
    assert.equal(transactionRetry.posts.size, 1);
    assert.equal(transactionRetry.staging, undefined);
  });

  it("rejects a mismatched existing final object and leaves a duplicate request stable", async () => {
    const ports = fakePorts();
    ports.final = stored(finalPath, { generation: "1", metadata: { sha256: "b".repeat(64) } });
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, ports), "failed-precondition");
    const clean = fakePorts();
    const first = await publishFeedActivity({ auth: { uid: owner }, data: request() }, clean);
    const second = await publishFeedActivity({ auth: { uid: owner }, data: request() }, clean);
    assert.deepEqual(second, first);
    assert.equal(clean.posts.size, 1);
    assert.equal(clean.final?.generation, "1");

    clean.staging = stored(stagingPath, { metadata: { ...stagingMetadata(), ownerUid: "other" } });
    await rejects(() => publishFeedActivity({ auth: { uid: owner }, data: request() }, clean), "failed-precondition");
    assert.notEqual(clean.staging, undefined);
  });
});

type Stored = { readonly path: string; readonly generation: string; readonly bytes: Uint8Array; readonly contentType: string; readonly metadata: Readonly<Record<string, string>> };
class FakePorts implements FeedPublishPorts {
  activity: unknown = activity();
  staging: Stored | undefined = stored(stagingPath);
  final: Stored | undefined;
  readonly posts = new Map<string, unknown>();
  copyCount = 0;
  failAfterCopy = false;
  failAfterPost = false;
  async readActivity(): Promise<unknown> { return this.activity; }
  async readProfile(): Promise<unknown> { return { displayName: "Ava", avatarInitials: "AV" }; }
  async readPost(postId: string): Promise<unknown> { return this.posts.get(postId); }
  async readObject(path: string): Promise<Stored | undefined> { return path === stagingPath ? this.staging : this.final; }
  async copyCreateOnly(): Promise<void> {
    this.copyCount += 1;
    const sourceBytes = this.staging?.bytes ?? png(88, 88);
    if (this.final === undefined) this.final = stored(finalPath, { generation: "1", bytes: sourceBytes, metadata: { sha256: hash(sourceBytes) } });
    if (this.failAfterCopy) { this.failAfterCopy = false; throw coded("internal"); }
  }
  async createPostIfAbsent(postId: string, post: unknown): Promise<unknown> {
    const existing = this.posts.get(postId);
    if (existing !== undefined) return existing;
    this.posts.set(postId, post);
    if (this.failAfterPost) { this.failAfterPost = false; throw coded("internal"); }
    return post;
  }
  async deleteObject(path: string): Promise<void> { if (path === stagingPath) this.staging = undefined; }
  now(): string { return "2026-07-11T00:00:00.000Z"; }
  sha256(bytes: Uint8Array): string { return hash(bytes); }
}
function fakePorts(): FakePorts { return new FakePorts(); }
function request(): { readonly activityId: string; readonly stagingPath: string } { return { activityId, stagingPath }; }
function activity(): Record<string, unknown> { return { ownerUid: owner, status: "validated", validationStatus: "validated", endedAt: "2026-07-11T00:00:00.000Z", distanceMeters: 1000, durationSeconds: 600, averagePaceSecondsPerKm: 600 }; }
function stored(path: string, overrides: Partial<Stored> = {}): Stored { return { path, generation: overrides.generation ?? "staging", bytes: overrides.bytes ?? png(88, 88), contentType: overrides.contentType ?? "image/png", metadata: overrides.metadata ?? stagingMetadata() }; }
function stagingMetadata(): Readonly<Record<string, string>> { return { ownerUid: owner, activityId, uploadId: "upload-a.png" }; }
function coded(code: string): Error & { readonly code: string } { return Object.assign(new Error(code), { code }); }
function hash(_bytes: Uint8Array): string { return "a".repeat(64); }
async function rejects(action: () => Promise<unknown>, code: string): Promise<void> { await assert.rejects(action, (error: unknown) => typeof error === "object" && error !== null && "code" in error && error["code"] === code); }
function png(width: number, height: number): Uint8Array { return Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, ...chunk("IHDR", [...u32(width), ...u32(height), 8, 6, 0, 0, 0]), ...chunk("IDAT", [0]), ...chunk("IEND", [])]); }
function corruptPng(width: number, height: number): Uint8Array { const bytes = png(width, height); bytes[bytes.length - 1] = (bytes[bytes.length - 1] ?? 0) ^ 1; return bytes; }
function u32(value: number): number[] { return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255]; }
function chunk(type: string, data: readonly number[]): number[] { const typeBytes = [...type].map((character) => character.charCodeAt(0)); return [...u32(data.length), ...typeBytes, ...data, ...u32(crc32([...typeBytes, ...data]))]; }
function crc32(bytes: readonly number[]): number { let crc = 0xffff_ffff; for (const value of bytes) { crc ^= value; for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1; } return (crc ^ 0xffff_ffff) >>> 0; }
