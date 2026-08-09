import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import {
  createFeedEngagementHandlers,
  createFeedEngagementTriggers,
  recomputeFeedEngagementCount,
  type EngagementAggregationPort,
  type EngagementKind,
  type EngagementRecomputeResult,
  type EngagementUpdate,
} from "../src/feed/engagement/engagement.js";
import type {
  FeedEngagementNotification,
  FeedEngagementNotificationWriteStatus,
  FeedEngagementNotificationWriter,
} from "../src/feed/engagement/engagementNotifications.js";

type ParentState = "published" | "deleting" | "deleted" | "missing";

describe("Feed engagement aggregation", () => {
  it("defines exactly the five trusted Firestore engagement triggers", () => {
    // Given: a production Firestore trigger factory.
    const triggers = createFeedEngagementTriggers({
      firestore: getFirestore(),
      updatedAt: () => FieldValue.serverTimestamp(),
    });

    // Then: only the required create, update, and delete trigger definitions exist.
    assert.deepEqual(Object.keys(triggers).sort(), [
      "feedCommentCreated",
      "feedCommentDeleted",
      "feedCommentUpdated",
      "feedLikeCreated",
      "feedLikeDeleted",
    ]);
    assert.deepEqual(
      Object.values(triggers).map(
        (trigger) => trigger.__endpoint.eventTrigger?.eventFilterPathPatterns?.["document"],
      ),
      [
        "feedPosts/{postId}/likes/{uid}",
        "feedPosts/{postId}/likes/{uid}",
        "feedPosts/{postId}/comments/{commentId}",
        "feedPosts/{postId}/comments/{commentId}",
        "feedPosts/{postId}/comments/{commentId}",
      ],
    );
    assert.deepEqual(
      Object.values(triggers).map((trigger) => trigger.__endpoint.region?.[0]),
      Array<string>(5).fill("asia-southeast1"),
    );
  });

  it("recomputes a published like count from the authoritative one-like-per-uid shape", async () => {
    // Given: repeated user writes to the one-like-per-UID document shape.
    const port = new FakeEngagementPort();
    port.createLike("runner-a");
    port.createLike("runner-a");

    // When: the create trigger recomputes from the subcollection aggregate.
    const result = await recomputeFeedEngagementCount(port, {
      postId: "post-a",
      kind: "like",
      updatedAt: "server-time",
    });

    // Then: only one like is counted and only the intended parent fields update.
    assert.deepEqual(result, { kind: "updated", count: 1 });
    assert.deepEqual(port.updates, [{ likeCount: 1, updatedAt: "server-time" }]);
  });

  it("converges likes after duplicate delivery, an unlike, and concurrent create-delete delivery", async () => {
    // Given: an injectable aggregate port and duplicate/out-of-order delivery.
    const port = new FakeEngagementPort();
    const handlers = createFeedEngagementHandlers({ port, updatedAt: () => "server-time" });

    port.createLike("runner-a");
    await handlers.onLikeCreated("post-a");
    await handlers.onLikeCreated("post-a");
    port.deleteLike("runner-a");
    await handlers.onLikeDeleted("post-a");

    port.createLike("runner-b");
    const create = handlers.onLikeCreated("post-a");
    port.deleteLike("runner-b");
    const remove = handlers.onLikeDeleted("post-a");
    // When: the final unlike and concurrent create-delete handlers finish.
    await Promise.all([create, remove]);

    // Then: the authoritative count converges at zero and never becomes negative.
    assert.deepEqual(port.likeCounts, [1, 1, 0, 0, 0]);
    assert.equal(port.likeCounts.every((count) => count >= 0), true);
    assert.deepEqual(port.updates.at(-1), { likeCount: 0, updatedAt: "server-time" });
  });

  it("recomputes comments for create, edit, and delete without changing the edit aggregate", async () => {
    // Given: a flat comments subcollection with one editable comment.
    const port = new FakeEngagementPort();
    const handlers = createFeedEngagementHandlers({ port, updatedAt: () => "server-time" });

    // When: create, edit, another create, and delete events are delivered.
    port.createComment("comment-a", "first");
    await handlers.onCommentCreated("post-a");
    port.editComment("comment-a", "edited");
    await handlers.onCommentUpdated("post-a");
    port.createComment("comment-b", "second");
    await handlers.onCommentCreated("post-a");
    port.deleteComment("comment-a");
    await handlers.onCommentDeleted("post-a");

    // Then: edit preserves the count and every update has only commentCount plus updatedAt.
    assert.deepEqual(port.commentCounts, [1, 1, 2, 1]);
    assert.equal(port.commentCounts[0], port.commentCounts[1]);
    assert.equal(port.commentCounts.every((count) => count >= 0), true);
    assert.deepEqual(port.updates, [
      { commentCount: 1, updatedAt: "server-time" },
      { commentCount: 1, updatedAt: "server-time" },
      { commentCount: 2, updatedAt: "server-time" },
      { commentCount: 1, updatedAt: "server-time" },
    ]);
  });

  it("does not write or recreate a missing, deleting, or deleted parent", async () => {
    // Given: a parent that is absent or outside the published state.
    for (const state of ["missing", "deleting", "deleted"] as const) {
      const port = new FakeEngagementPort(state);
      port.createLike("runner-a");

      // When: a late like event is recomputed.
      const result = await recomputeFeedEngagementCount(port, {
        postId: "post-a",
        kind: "like",
        updatedAt: "server-time",
      });

      // Then: the parent remains untouched and cannot be recreated by update().
      assert.deepEqual(result, { kind: "parent_not_published" });
      assert.deepEqual(port.updates, []);
    }
  });
});

// ---------------------------------------------------------------------------
// Notification wiring: feedLikeCreated/feedCommentCreated call the injected
// emitter only when the recompute reports `updated`; the other three
// triggers never notify. Uses the real Firestore emulator (already
// initialized by an earlier file in the `test:feed` run) because the
// gating check lives inside `firestoreEngagementAggregationPort`'s own
// transaction, which the pure `FakeEngagementPort` above does not exercise.
// ---------------------------------------------------------------------------

describe("createFeedEngagementTriggers notification wiring", () => {
  const firestore = getFirestore();

  it("feedLikeCreated notifies through the injected writer when the parent is published", async () => {
    const postId = uniqueId("wiring-like-post");
    await seedPublishedPost(firestore, postId, "wiring-author");
    await firestore.doc(`feedPosts/${postId}/likes/wiring-liker`).set({ userUid: "wiring-liker" });
    const writer = new RecordingWriter();
    const triggers = createFeedEngagementTriggers({
      firestore,
      updatedAt: () => FieldValue.serverTimestamp(),
      notifications: { writer },
    });

    await runFirestoreTrigger(triggers.feedLikeCreated, { postId, uid: "wiring-liker" });

    assert.equal(writer.persisted.length, 1);
    assert.equal(writer.persisted[0]!.payload.postId, postId);
    assert.equal(writer.persisted[0]!.payload.kind, "feed_post_liked");
  });

  it("feedCommentCreated notifies through the injected writer when the parent is published", async () => {
    const postId = uniqueId("wiring-comment-post");
    await seedPublishedPost(firestore, postId, "wiring-author");
    await firestore.doc(`feedPosts/${postId}/comments/wiring-comment`).set({
      authorUid: "wiring-commenter",
      authorDisplayName: "Wiring Commenter",
      body: "Nice run!",
    });
    const writer = new RecordingWriter();
    const triggers = createFeedEngagementTriggers({
      firestore,
      updatedAt: () => FieldValue.serverTimestamp(),
      notifications: { writer },
    });

    await runFirestoreTrigger(triggers.feedCommentCreated, { postId, commentId: "wiring-comment" });

    assert.equal(writer.persisted.length, 1);
    assert.equal(writer.persisted[0]!.payload.kind, "feed_post_commented");
  });

  it("feedCommentUpdated never notifies", async () => {
    const postId = uniqueId("wiring-update-post");
    await seedPublishedPost(firestore, postId, "wiring-author");
    await firestore.doc(`feedPosts/${postId}/comments/wiring-comment`).set({
      authorUid: "wiring-commenter",
      authorDisplayName: "Wiring Commenter",
      body: "edited",
    });
    const writer = new RecordingWriter();
    const triggers = createFeedEngagementTriggers({
      firestore,
      updatedAt: () => FieldValue.serverTimestamp(),
      notifications: { writer },
    });

    await runFirestoreTrigger(triggers.feedCommentUpdated, { postId, commentId: "wiring-comment" });

    assert.equal(writer.persisted.length, 0);
  });

  it("feedLikeDeleted and feedCommentDeleted never notify", async () => {
    const postId = uniqueId("wiring-delete-post");
    await seedPublishedPost(firestore, postId, "wiring-author");
    const writer = new RecordingWriter();
    const triggers = createFeedEngagementTriggers({
      firestore,
      updatedAt: () => FieldValue.serverTimestamp(),
      notifications: { writer },
    });

    await runFirestoreTrigger(triggers.feedLikeDeleted, { postId, uid: "wiring-liker" });
    await runFirestoreTrigger(triggers.feedCommentDeleted, { postId, commentId: "wiring-comment" });

    assert.equal(writer.persisted.length, 0);
  });

  it("a parent_not_published recompute short-circuits before the emitter ever runs", async () => {
    const postId = uniqueId("wiring-missing-post");
    // No feedPosts/{postId} doc at all -> recompute reports parent_not_published.
    await firestore.doc(`feedPosts/${postId}/likes/wiring-liker`).set({ userUid: "wiring-liker" });
    const writer = new RecordingWriter();
    const triggers = createFeedEngagementTriggers({
      firestore,
      updatedAt: () => FieldValue.serverTimestamp(),
      notifications: { writer },
    });

    await runFirestoreTrigger(triggers.feedLikeCreated, { postId, uid: "wiring-liker" });

    assert.equal(writer.persisted.length, 0);
    assert.equal((await firestore.collection("feedPosts").doc(postId).get()).exists, false);
  });

  it("the aggregate count still updates when the injected notifier throws", async () => {
    const postId = uniqueId("wiring-throw-post");
    await seedPublishedPost(firestore, postId, "wiring-author");
    await firestore.doc(`feedPosts/${postId}/likes/wiring-liker`).set({ userUid: "wiring-liker" });
    const throwingWriter: FeedEngagementNotificationWriter = {
      persist: async () => {
        throw new Error("simulated notify failure");
      },
    };
    const triggers = createFeedEngagementTriggers({
      firestore,
      updatedAt: () => FieldValue.serverTimestamp(),
      notifications: { writer: throwingWriter },
    });

    await assert.doesNotReject(() => runFirestoreTrigger(triggers.feedLikeCreated, { postId, uid: "wiring-liker" }));

    assert.equal((await firestore.collection("feedPosts").doc(postId).get()).get("likeCount"), 1);
  });
});

class RecordingWriter implements FeedEngagementNotificationWriter {
  readonly persisted: FeedEngagementNotification[] = [];

  async persist(
    notification: FeedEngagementNotification,
    _nowMs: number,
  ): Promise<FeedEngagementNotificationWriteStatus> {
    this.persisted.push(notification);
    return "written";
  }
}

let wiringCounter = 0;
function uniqueId(prefix: string): string {
  wiringCounter += 1;
  return `${prefix}-${Date.now()}-${wiringCounter}`;
}

async function seedPublishedPost(
  firestore: ReturnType<typeof getFirestore>,
  postId: string,
  authorUid: string,
): Promise<void> {
  await firestore.collection("feedPosts").doc(postId).set({
    authorUid,
    status: "published",
    likeCount: 0,
    commentCount: 0,
  });
}

// Every v2 Cloud Function exposes `.run()` as a direct pass-through to its
// wrapped handler, bypassing raw-CloudEvent unmarshalling — the same
// unit-testing entry point already used for callables elsewhere in this
// suite (see `getRunnerPublicProfileCallable.run(...)` in
// runnerPublicProfileEmulatorIntegration.test.ts). The handlers under test
// here only ever read `event.params`, so a minimal params-only fake event is
// sufficient.
async function runFirestoreTrigger(
  trigger: unknown,
  params: Record<string, string>,
): Promise<void> {
  await (trigger as { run: (event: { params: Record<string, string> }) => Promise<void> }).run({
    params,
  });
}

class FakeEngagementPort implements EngagementAggregationPort<string> {
  readonly updates: EngagementUpdate<string>[] = [];
  readonly likes = new Set<string>();
  readonly comments = new Map<string, string>();
  readonly likeCounts: number[] = [];
  readonly commentCounts: number[] = [];

  constructor(private readonly parentState: ParentState = "published") {}

  createLike(uid: string): void {
    this.likes.add(uid);
  }

  deleteLike(uid: string): void {
    this.likes.delete(uid);
  }

  createComment(commentId: string, body: string): void {
    this.comments.set(commentId, body);
  }

  editComment(commentId: string, body: string): void {
    this.comments.set(commentId, body);
  }

  deleteComment(commentId: string): void {
    this.comments.delete(commentId);
  }

  async recomputePublishedCount(input: {
    readonly postId: string;
    readonly kind: EngagementKind;
    readonly updatedAt: string;
  }): Promise<EngagementRecomputeResult> {
    await Promise.resolve();
    if (this.parentState !== "published") {
      return { kind: "parent_not_published" };
    }
    switch (input.kind) {
      case "like": {
        const update = { likeCount: this.likes.size, updatedAt: input.updatedAt };
        this.updates.push(update);
        this.likeCounts.push(update.likeCount);
        return { kind: "updated", count: update.likeCount };
      }
      case "comment": {
        const update = { commentCount: this.comments.size, updatedAt: input.updatedAt };
        this.updates.push(update);
        this.commentCounts.push(update.commentCount);
        return { kind: "updated", count: update.commentCount };
      }
    }
  }
}
