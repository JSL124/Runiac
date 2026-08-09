import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import { cleanupFromActivityDeletion, deleteFeedPostCore, reportFeedPostCore } from "../src/feed/lifecycle/core.js";
import { reportFeedPostForCallable } from "../src/feed/lifecycle/functions.js";
import type { FeedLifecyclePort, FeedLifecycleTransaction, FeedReport, LifecyclePost, LifecycleStepResult } from "../src/feed/lifecycle/types.js";

describe("Feed lifecycle", () => {
  it("denies unauthenticated report access", async () => {
    const port = fixture();
    const result = await reportFeedPostCore({ port, reporterUid: "", postId: "activity-a" });
    assert.deepEqual(result, { kind: "denied" });
    assert.equal(port.reports.size, 0);
  });

  it("rejects unauthenticated callable report requests before reading a post", async () => {
    const port = fixture();
    await assert.rejects(
      reportFeedPostForCallable({ data: { postId: "activity-a" } }, port),
      (error: unknown) => error instanceof HttpsError && error.code === "unauthenticated",
    );
    assert.equal(port.reports.size, 0);
  });

  it("denies reports after current friend access is revoked", async () => {
    const port = fixture();
    port.readers.delete("friend-a");
    const result = await reportFeedPostCore({ port, reporterUid: "friend-a", postId: "activity-a" });
    assert.deepEqual(result, { kind: "denied" });
    assert.equal(port.reports.size, 0);
  });

  it("creates one exact report and reporter-private marker without changing the post", async () => {
    const port = fixture();
    const before = port.post("activity-a");
    const result = await reportFeedPostCore({ port, reporterUid: "friend-a", postId: "activity-a" });
    assert.deepEqual(result, { kind: "reported", reportId: "report_8_ZnJpZW5kLWE_10_YWN0aXZpdHktYQ", duplicate: false });
    assert.deepEqual(port.reports.get(result.reportId), report("friend-a"));
    assert.equal(port.hidden("friend-a", "activity-a"), true);
    assert.equal(port.hidden("friend-b", "activity-a"), false);
    assert.equal(port.hidden("author", "activity-a"), false);
    assert.deepEqual(port.post("activity-a"), before);
  });

  it("converges duplicate reports and recreates only the reporter marker", async () => {
    const port = fixture();
    const first = await reportFeedPostCore({ port, reporterUid: "friend-a", postId: "activity-a" });
    port.hiddenMarkers.delete("friend-a/activity-a");
    const second = await reportFeedPostCore({ port, reporterUid: "friend-a", postId: "activity-a" });
    assert.equal(first.kind, "reported");
    assert.deepEqual(second, { kind: "reported", reportId: first.reportId, duplicate: true });
    assert.equal(port.reports.size, 1);
    assert.equal(port.hidden("friend-a", "activity-a"), true);
  });

  it("denies a non-owner delete without changing the post", async () => {
    const port = fixture();
    const result = await deleteFeedPostCore({ port, ownerUid: "friend-b", postId: "activity-a" });
    assert.deepEqual(result, { kind: "denied" });
    assert.equal(port.post("activity-a")?.status, "published");
  });

  it("cuts off published access then removes dependents and exact thumbnail while preserving activity", async () => {
    const port = fixture();
    await reportFeedPostCore({ port, reporterUid: "friend-a", postId: "activity-a" });
    const result = await deleteFeedPostCore({ port, ownerUid: "author", postId: "activity-a" });
    assert.equal(result.kind, "cleanup");
    if (result.kind !== "cleanup") return;
    assert.equal(result.cleanup.kind, "completed");
    assert.equal(port.statuses.includes("deleting"), true);
    assert.equal(port.sawDeletingAtCleanup, true);
    assert.equal(port.posts.has("activity-a"), false);
    assert.equal(port.likes.size, 0);
    assert.equal(port.comments.size, 0);
    assert.equal(port.reports.size, 0);
    assert.equal(port.hiddenMarkers.size, 0);
    assert.equal(port.thumbnailGenerations.size, 0);
    assert.equal(port.activities.has("activity-a"), true);
  });

  it("uses the same idempotent cleanup after source activity deletion", async () => {
    const port = fixture();
    const result = await cleanupFromActivityDeletion({ port, postId: "activity-a" });
    assert.equal(result.kind, "cleanup");
    if (result.kind !== "cleanup") return;
    assert.equal(result.cleanup.kind, "completed");
    assert.equal(port.activities.has("activity-a"), true);
    const repeated = await cleanupFromActivityDeletion({ port, postId: "activity-a" });
    assert.deepEqual(repeated, { kind: "already_missing" });
  });

  it("reports retry required after a partial cleanup and converges on retry", async () => {
    const port = fixture();
    port.failStep = "comments";
    const first = await deleteFeedPostCore({ port, ownerUid: "author", postId: "activity-a" });
    assert.deepEqual(first, { kind: "cleanup", cleanup: { kind: "retry_required", postId: "activity-a", failedStep: "comments" } });
    assert.equal(port.post("activity-a")?.status, "deleting");
    const second = await deleteFeedPostCore({ port, ownerUid: "author", postId: "activity-a" });
    assert.equal(second.kind, "cleanup");
    if (second.kind !== "cleanup") return;
    assert.equal(second.cleanup.kind, "completed");
    assert.equal(port.posts.has("activity-a"), false);
  });

  it("never deletes a replacement thumbnail generation", async () => {
    const port = fixture();
    port.thumbnailGenerationMismatch = true;
    const result = await deleteFeedPostCore({ port, ownerUid: "author", postId: "activity-a" });
    assert.deepEqual(result, { kind: "cleanup", cleanup: { kind: "retry_required", postId: "activity-a", failedStep: "thumbnail" } });
    assert.equal(port.thumbnailGenerations.has("feed-thumbnails/author/activity-a/route-preview.png@7"), true);
    assert.equal(port.post("activity-a")?.status, "deleting");
  });
});

class FakeLifecyclePort implements FeedLifecyclePort {
  readonly posts = new Map<string, LifecyclePost>();
  readonly reports = new Map<string, FeedReport>();
  readonly hiddenMarkers = new Set<string>();
  readonly likes = new Set(["friend-a", "friend-b"]);
  readonly comments = new Set(["comment-a", "comment-b"]);
  readonly thumbnailGenerations = new Set(["feed-thumbnails/author/activity-a/route-preview.png@7"]);
  readonly activities = new Set(["activity-a"]);
  readonly statuses: string[] = [];
  readonly readers = new Set(["author", "friend-a", "friend-b"]);
  failStep: "comments" | undefined;
  thumbnailGenerationMismatch = false;
  sawDeletingAtCleanup = false;

  constructor() {
    this.posts.set("activity-a", post());
  }

  async runTransaction<T>(operation: (transaction: FeedLifecycleTransaction) => Promise<T>): Promise<T> {
    return operation({
      getPost: async (postId) => this.post(postId),
      canReadPost: async (uid) => this.readers.has(uid),
      getReport: async (reportId) => this.reports.get(reportId) ?? null,
      setReport: (reportId, value) => { this.reports.set(reportId, value); },
      setHiddenMarker: (uid, postId) => { this.hiddenMarkers.add(`${uid}/${postId}`); },
      setDeleting: (postId) => {
        const existing = this.posts.get(postId);
        if (existing !== undefined) this.posts.set(postId, { ...existing, status: "deleting" });
        this.statuses.push("deleting");
      },
    });
  }

  now(): unknown { return "2026-07-11T01:00:00.000Z"; }
  async deleteLikes(postId: string): Promise<LifecycleStepResult> {
    this.sawDeletingAtCleanup = this.post(postId)?.status === "deleting";
    return this.deleteSet(this.likes, "likes");
  }
  async deleteComments(): Promise<LifecycleStepResult> { return this.deleteSet(this.comments, "comments"); }
  async deleteReportsAndHiddenMarkers(): Promise<LifecycleStepResult> {
    const hadReports = this.reports.size > 0 || this.hiddenMarkers.size > 0;
    this.reports.clear(); this.hiddenMarkers.clear();
    return { kind: hadReports ? "completed" : "already_missing" };
  }
  async deleteExactThumbnail(postValue: LifecyclePost): Promise<LifecycleStepResult> {
    if (this.thumbnailGenerationMismatch) return { kind: "retry_required" };
    const key = `${postValue.thumbnailStoragePath}@${postValue.thumbnailObjectGeneration}`;
    return this.thumbnailGenerations.delete(key) ? { kind: "completed" } : { kind: "already_missing" };
  }
  async deletePost(postId: string): Promise<LifecycleStepResult> {
    return this.posts.delete(postId) ? { kind: "completed" } : { kind: "already_missing" };
  }

  post(postId: string): LifecyclePost | null { return this.posts.get(postId) ?? null; }
  hidden(uid: string, postId: string): boolean { return this.hiddenMarkers.has(`${uid}/${postId}`); }

  private deleteSet(values: Set<string>, step: "likes" | "comments"): LifecycleStepResult {
    if (this.failStep === step) { this.failStep = undefined; return { kind: "retry_required" }; }
    const hadValues = values.size > 0; values.clear();
    return { kind: hadValues ? "completed" : "already_missing" };
  }
}

function fixture(): FakeLifecyclePort { return new FakeLifecyclePort(); }
function post(): LifecyclePost {
  return { postId: "activity-a", authorUid: "author", status: "published", thumbnailStoragePath: "feed-thumbnails/author/activity-a/route-preview.png", thumbnailObjectGeneration: "7" };
}
function report(reporterUid: string): FeedReport {
  return { reporterUid, targetType: "feedPost", targetId: "activity-a", reason: "feed_inappropriate", description: "", createdAt: "2026-07-11T01:00:00.000Z" };
}
