import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { createModerationCommandHandlers } from "../src/moderation/moderationCommand.js";

describe(
  "moderation command handler",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;
    let handlers: ReturnType<typeof createModerationCommandHandlers>;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: "demo-runiac-moderation" });
      }
      firestore = getFirestore();
      handlers = createModerationCommandHandlers({ firestore });
    });

    beforeEach(async () => {
      await clearCollections(firestore, [
        "feedPosts",
        "reports",
        "moderationCommands",
      ]);
    });

    it("rejects an unknown command kind without touching the post", async () => {
      await seedPost(firestore, "post-unknown-kind", "author-a");

      const ref = firestore.collection("moderationCommands").doc();
      const data = { kind: "wipeEverything", postId: "post-unknown-kind" };
      await ref.set(data);

      await handlers.onCommandCreated(ref.id, data);

      const after = await ref.get();
      assert.equal(after.get("status"), "failed");
      assert.equal(typeof after.get("error"), "string");
      assert.equal(after.get("removedAuthorUid"), undefined);
      assert.equal(typeof after.get("completedAt"), "string");

      const post = await firestore.doc("feedPosts/post-unknown-kind").get();
      assert.equal(post.exists, true);
    });

    it("rejects an invalid postId without touching the post", async () => {
      await seedPost(firestore, "post-invalid-id", "author-a");

      const ref = firestore.collection("moderationCommands").doc();
      const data = { kind: "removeFeedPost", postId: "not a valid id!" };
      await ref.set(data);

      await handlers.onCommandCreated(ref.id, data);

      const after = await ref.get();
      assert.equal(after.get("status"), "failed");
      assert.equal(typeof after.get("error"), "string");
      assert.equal(after.get("removedAuthorUid"), undefined);

      const post = await firestore.doc("feedPosts/post-invalid-id").get();
      assert.equal(post.exists, true);
    });

    it("removes a reported feed post regardless of who reported it, and captures the removed author uid", async () => {
      await seedPost(firestore, "post-remove-me", "reported-author");

      const ref = firestore.collection("moderationCommands").doc();
      const data = { kind: "removeFeedPost", postId: "post-remove-me", requestedBy: "admin@runiac.test" };
      await ref.set(data);

      await handlers.onCommandCreated(ref.id, data);

      const after = await ref.get();
      assert.equal(after.get("status"), "completed");
      assert.equal(after.get("removedAuthorUid"), "reported-author");
      assert.equal(typeof after.get("completedAt"), "string");
      assert.equal(after.get("error"), undefined);

      const post = await firestore.doc("feedPosts/post-remove-me").get();
      assert.equal(post.exists, false);
    });

    it("is a no-op on replay once the command has reached a terminal state", async () => {
      await seedPost(firestore, "post-replay", "replay-author");

      const ref = firestore.collection("moderationCommands").doc();
      const data = { kind: "removeFeedPost", postId: "post-replay" };
      await ref.set(data);

      await handlers.onCommandCreated(ref.id, data);
      const firstCompletedAt = (await ref.get()).get("completedAt");
      assert.equal(typeof firstCompletedAt, "string");

      // If the trigger reprocessed instead of no-oping, it would try to
      // clean up this newly re-seeded post a second time. Re-seeding it
      // between calls is what makes the no-op assertion below meaningful
      // rather than coincidental with natural delete idempotency.
      await seedPost(firestore, "post-replay", "replay-author");

      await handlers.onCommandCreated(ref.id, data);
      const after = await ref.get();
      assert.equal(after.get("status"), "completed");
      assert.equal(after.get("completedAt"), firstCompletedAt);

      const post = await firestore.doc("feedPosts/post-replay").get();
      assert.equal(post.exists, true);
    });

    it("completes without a removedAuthorUid when the post is already gone", async () => {
      const ref = firestore.collection("moderationCommands").doc();
      const data = { kind: "removeFeedPost", postId: "post-does-not-exist" };
      await ref.set(data);

      await handlers.onCommandCreated(ref.id, data);

      const after = await ref.get();
      assert.equal(after.get("status"), "completed");
      assert.equal(after.get("removedAuthorUid"), undefined);
    });
  },
);

async function seedPost(firestore: Firestore, postId: string, authorUid: string): Promise<void> {
  await firestore.doc(`feedPosts/${postId}`).set({
    authorUid,
    status: "published",
    thumbnailStoragePath: `feed-thumbnails/${authorUid}/${postId}/route-preview.png`,
    thumbnailObjectGeneration: "7",
  });
}

async function clearCollections(
  firestore: Firestore,
  collectionNames: readonly string[],
): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    if (snapshot.empty) {
      continue;
    }
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}
