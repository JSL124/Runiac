// Feed engagement (like/comment) inbox notifications (WP1): pure planner +
// copy/truncation unit tests, `socialActivityEnabled` pure reader tests, and
// emulator dedup/allowlist/terminal-independence tests.

import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";

import { socialActivityEnabled } from "../src/notifications/scheduledPushReaders.js";
import {
  ALLOWED_FEED_ENGAGEMENT_PAYLOAD_KEYS,
  COMMENT_BODY_MAX_CHARS,
  FEED_ENGAGEMENT_FALLBACK_ACTOR_NAME,
  FEED_LIKE_NOTIFICATION_BODY,
  emitFeedCommentNotification,
  emitFeedLikeNotification,
  feedCommentNotificationBody,
  feedCommentNotificationTitle,
  feedEngagementDeliveryKey,
  feedLikeNotificationTitle,
  firestoreFeedEngagementNotificationWriter,
  planFeedCommentNotification,
  planFeedLikeNotification,
  truncateCommentBody,
  type FeedEngagementNotificationWriteStatus,
  type FeedEngagementNotificationWriter,
} from "../src/feed/engagement/engagementNotifications.js";
import type { FeedEngagementMessagingPort } from "../src/feed/engagement/engagementPush.js";

const PROJECT_ID = "demo-runiac-feed";

// Envelope keys permitted at the inbox doc top level (everything else is the
// client-visible `data` payload, which is separately allowlisted).
const ALLOWED_ENVELOPE_KEYS = [
  "ownerUid",
  "deliveryKey",
  "title",
  "body",
  "createdAt",
  "readAt",
  "data",
  "updatedAt",
] as const;

let firestore: Firestore;
let counter = 0;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

function uniqueId(prefix: string): string {
  counter += 1;
  return `${prefix}-${Date.now()}-${counter}`;
}

// ---------------------------------------------------------------------------
// Push wiring test helpers: a fake messaging port + a registered device
// token, so push-send assertions never touch real FCM or the scheduled-push
// module's own tests.
// ---------------------------------------------------------------------------

type CapturedSend = {
  readonly token: string;
  readonly notification: { readonly title: string; readonly body: string };
  readonly data: Readonly<Record<string, string>>;
};

function fakeMessaging(options?: {
  readonly shouldThrow?: boolean;
}): { readonly port: FeedEngagementMessagingPort; readonly sent: CapturedSend[] } {
  const sent: CapturedSend[] = [];
  return {
    sent,
    port: {
      send: async (message) => {
        sent.push(message);
        if (options?.shouldThrow) {
          throw new Error("simulated FCM send failure");
        }
        return "message-id";
      },
    },
  };
}

// A writer stub with a fixed result.
//
// These emulator tests run against `demo-runiac-feed` with the Functions
// emulator on, so writing `feedPosts/{postId}/likes|comments/{id}` fires the
// REAL `feedLikeCreated` / `feedCommentCreated` triggers. Those triggers race
// the direct `emit*` call below to the same `notificationInbox` doc, and the
// writer's exactly-once guard is a transactional exists-check + create. If a
// trigger wins, the direct call sees its own interaction as already-notified,
// returns "duplicate", and sends nothing — so a push fan-out assertion of 2
// intermittently observes 0. That is a test-harness race, not a product bug,
// and it failed in CI on 2026-07-31.
//
// Pinning the writer result isolates the push fan-out contract from the race.
// The real writer's exactly-once behaviour is covered separately by the
// "firestoreFeedEngagementNotificationWriter dedup" suite, so nothing is lost.
function stubWriter(status: FeedEngagementNotificationWriteStatus): FeedEngagementNotificationWriter {
  return { persist: async () => status };
}

async function registerToken(uid: string, tokenFingerprint: string, fcmToken: string): Promise<void> {
  await firestore
    .collection("notificationDevices")
    .doc(uid)
    .collection("tokens")
    .doc(tokenFingerprint)
    .set({ tokenFingerprint, fcmToken, enabled: true });
}

// ---------------------------------------------------------------------------
// Pure: delivery key + copy + truncation
// ---------------------------------------------------------------------------

describe("feedEngagementDeliveryKey (pure)", () => {
  it("is deterministic in postId:kind:actorUid order", () => {
    assert.equal(
      feedEngagementDeliveryKey("post-1", "feed_post_liked", "actor-a"),
      "post-1:feed_post_liked:actor-a",
    );
    assert.equal(
      feedEngagementDeliveryKey("post-1", "feed_post_commented", "actor-a"),
      "post-1:feed_post_commented:actor-a",
    );
  });
});

describe("copy constants (pure)", () => {
  it("pins the exact like title and body", () => {
    assert.equal(feedLikeNotificationTitle("Jordan"), "Jordan liked your run");
    assert.equal(FEED_LIKE_NOTIFICATION_BODY, "Tap to open your run post.");
  });

  it("pins the exact comment title and quoted body", () => {
    assert.equal(feedCommentNotificationTitle("Jordan"), "Jordan commented on your run");
    assert.equal(feedCommentNotificationBody("Nice pace!"), '"Nice pace!"');
  });

  it("uses Someone as the fallback actor name", () => {
    assert.equal(FEED_ENGAGEMENT_FALLBACK_ACTOR_NAME, "Someone");
  });

  it("caps comment bodies at 80 code points", () => {
    assert.equal(COMMENT_BODY_MAX_CHARS, 80);
  });
});

describe("truncateCommentBody (pure)", () => {
  it("leaves a short body untouched apart from trimming", () => {
    assert.equal(truncateCommentBody("  Nice run!  "), "Nice run!");
  });

  it("collapses every whitespace run to a single space", () => {
    assert.equal(truncateCommentBody("Great   job\n\nout there\t\tfriend"), "Great job out there friend");
  });

  it("keeps a body of exactly 80 code points untouched", () => {
    const body = "a".repeat(80);
    assert.equal(truncateCommentBody(body), body);
    assert.equal(Array.from(truncateCommentBody(body)).length, 80);
  });

  it("truncates a body over 80 code points to 79 code points plus an ellipsis", () => {
    const body = "a".repeat(90);
    const result = truncateCommentBody(body);
    assert.equal(result, `${"a".repeat(79)}…`);
    assert.equal(Array.from(result).length, 80);
  });

  it("slices by code point, never splitting a surrogate-pair emoji in half", () => {
    // 78 "a"s + one surrogate-pair emoji (1 code point, 2 UTF-16 units) + 10
    // "b"s = 89 code points / 90 UTF-16 units. A naive `String#slice(0, 79)`
    // would land mid-surrogate-pair (UTF-16 index 78 is the emoji's high
    // surrogate), producing a corrupted lone surrogate. Code-point-safe
    // slicing must keep the emoji whole and drop the rest.
    const emoji = "\u{1F600}"; // 😀
    const body = `${"a".repeat(78)}${emoji}${"b".repeat(10)}`;
    assert.equal(Array.from(body).length, 89);

    const result = truncateCommentBody(body);

    // The first 79 code points are the 78 "a"s plus the whole emoji.
    assert.equal(result, `${"a".repeat(78)}${emoji}…`);
    // No lone surrogate: every UTF-16 code unit pairs correctly.
    const lonelySurrogate = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/;
    assert.equal(lonelySurrogate.test(result), false);
  });
});

// ---------------------------------------------------------------------------
// Pure: planner suppression + payload shape
// ---------------------------------------------------------------------------

describe("planFeedLikeNotification (pure)", () => {
  const basePost = { authorUid: "author-1", status: "published" } as const;

  it("plans a notification for a genuine like with an allowlisted payload", () => {
    const notification = planFeedLikeNotification({
      postId: "post-1",
      actorUid: "actor-1",
      actorName: "Jordan",
      post: basePost,
      socialActivityEnabled: true,
    });
    assert.ok(notification);
    assert.equal(notification.ownerUid, "author-1");
    assert.equal(notification.deliveryKey, "post-1:feed_post_liked:actor-1");
    assert.equal(notification.title, "Jordan liked your run");
    assert.equal(notification.body, FEED_LIKE_NOTIFICATION_BODY);
    assert.deepEqual(Object.keys(notification.payload).sort(), [...ALLOWED_FEED_ENGAGEMENT_PAYLOAD_KEYS].sort());
    assert.deepEqual(notification.payload, { kind: "feed_post_liked", route: "feedComments", postId: "post-1" });
  });

  it("falls back to Someone when the actor name is empty", () => {
    const notification = planFeedLikeNotification({
      postId: "post-1",
      actorUid: "actor-1",
      actorName: "",
      post: basePost,
      socialActivityEnabled: true,
    });
    assert.equal(notification?.title, "Someone liked your run");
  });

  it("suppresses self-engagement", () => {
    assert.equal(
      planFeedLikeNotification({
        postId: "post-1",
        actorUid: "author-1",
        actorName: "Author",
        post: basePost,
        socialActivityEnabled: true,
      }),
      null,
    );
  });

  it("suppresses when socialActivityEnabled is false", () => {
    assert.equal(
      planFeedLikeNotification({
        postId: "post-1",
        actorUid: "actor-1",
        actorName: "Jordan",
        post: basePost,
        socialActivityEnabled: false,
      }),
      null,
    );
  });

  it("suppresses an empty postId or actorUid", () => {
    assert.equal(
      planFeedLikeNotification({
        postId: "",
        actorUid: "actor-1",
        actorName: "Jordan",
        post: basePost,
        socialActivityEnabled: true,
      }),
      null,
    );
    assert.equal(
      planFeedLikeNotification({
        postId: "post-1",
        actorUid: "",
        actorName: "Jordan",
        post: basePost,
        socialActivityEnabled: true,
      }),
      null,
    );
  });

  it("suppresses a parent post that is not published", () => {
    assert.equal(
      planFeedLikeNotification({
        postId: "post-1",
        actorUid: "actor-1",
        actorName: "Jordan",
        post: { authorUid: "author-1", status: "deleting" },
        socialActivityEnabled: true,
      }),
      null,
    );
  });
});

describe("planFeedCommentNotification (pure)", () => {
  const basePost = { authorUid: "author-1", status: "published" } as const;

  it("plans a notification with the quoted, truncated comment body", () => {
    const notification = planFeedCommentNotification({
      postId: "post-1",
      actorUid: "actor-1",
      actorName: "Jordan",
      commentBody: "  Great   pace out there!  ",
      post: basePost,
      socialActivityEnabled: true,
    });
    assert.ok(notification);
    assert.equal(notification.title, "Jordan commented on your run");
    assert.equal(notification.body, '"Great pace out there!"');
    assert.equal(notification.deliveryKey, "post-1:feed_post_commented:actor-1");
    assert.deepEqual(notification.payload, {
      kind: "feed_post_commented",
      route: "feedComments",
      postId: "post-1",
    });
  });

  it("falls back to the like body when the trimmed comment is empty", () => {
    const notification = planFeedCommentNotification({
      postId: "post-1",
      actorUid: "actor-1",
      actorName: "Jordan",
      commentBody: "   \n\t  ",
      post: basePost,
      socialActivityEnabled: true,
    });
    assert.equal(notification?.body, FEED_LIKE_NOTIFICATION_BODY);
  });

  it("suppresses self-engagement, disabled prefs, empty ids, and a non-published parent", () => {
    assert.equal(
      planFeedCommentNotification({
        postId: "post-1",
        actorUid: "author-1",
        actorName: "Author",
        commentBody: "hi",
        post: basePost,
        socialActivityEnabled: true,
      }),
      null,
    );
    assert.equal(
      planFeedCommentNotification({
        postId: "post-1",
        actorUid: "actor-1",
        actorName: "Jordan",
        commentBody: "hi",
        post: basePost,
        socialActivityEnabled: false,
      }),
      null,
    );
    assert.equal(
      planFeedCommentNotification({
        postId: "",
        actorUid: "actor-1",
        actorName: "Jordan",
        commentBody: "hi",
        post: basePost,
        socialActivityEnabled: true,
      }),
      null,
    );
    assert.equal(
      planFeedCommentNotification({
        postId: "post-1",
        actorUid: "",
        actorName: "Jordan",
        commentBody: "hi",
        post: basePost,
        socialActivityEnabled: true,
      }),
      null,
    );
    assert.equal(
      planFeedCommentNotification({
        postId: "post-1",
        actorUid: "actor-1",
        actorName: "Jordan",
        commentBody: "hi",
        post: { authorUid: "author-1", status: "deleting" },
        socialActivityEnabled: true,
      }),
      null,
    );
  });
});

// ---------------------------------------------------------------------------
// Pure: socialActivityEnabled reader
// ---------------------------------------------------------------------------

describe("socialActivityEnabled (pure)", () => {
  it("defaults true when the preferences document is absent", () => {
    assert.equal(socialActivityEnabled(undefined, undefined), true);
  });

  it("defaults true when the key is absent from an existing preferences document", () => {
    assert.equal(socialActivityEnabled({}, undefined), true);
  });

  it("honours an explicit false", () => {
    assert.equal(socialActivityEnabled({ socialActivityEnabled: false }, undefined), false);
  });

  it("honours an explicit true", () => {
    assert.equal(socialActivityEnabled({ socialActivityEnabled: true }, undefined), true);
  });

  it("falls back to the legacy userProfiles.notificationPreferences map when no top-level doc exists", () => {
    assert.equal(
      socialActivityEnabled(undefined, { notificationPreferences: { socialActivityEnabled: false } }),
      false,
    );
  });

  it("defaults true for a non-boolean value", () => {
    assert.equal(socialActivityEnabled({ socialActivityEnabled: "false" }, undefined), true);
  });
});

// ---------------------------------------------------------------------------
// Emulator: writer dedup + envelope/allowlist + emitter behaviour
// ---------------------------------------------------------------------------

describe("firestoreFeedEngagementNotificationWriter dedup", () => {
  it("writes once, then reports duplicate without disturbing createdAt/readAt", async () => {
    const writer = firestoreFeedEngagementNotificationWriter(firestore);
    const notification = planFeedLikeNotification({
      postId: uniqueId("post"),
      actorUid: "actor-dedup",
      actorName: "Jordan",
      post: { authorUid: "author-dedup", status: "published" },
      socialActivityEnabled: true,
    });
    assert.ok(notification);

    const first = await writer.persist(notification, Date.parse("2026-07-13T00:00:00.000Z"));
    assert.equal(first, "written");

    const items = await inboxItems(notification.ownerUid);
    assert.equal(items.length, 1);
    const doc = items[0]!;
    assert.equal(doc.id, notification.deliveryKey);
    assert.ok(doc.get("createdAt") instanceof Timestamp);
    assert.equal(doc.get("readAt"), null);

    // Simulate the recipient reading it before a replay arrives.
    await doc.ref.update({ readAt: Timestamp.fromMillis(Date.parse("2026-07-13T02:00:00.000Z")) });

    const second = await writer.persist(notification, Date.parse("2026-07-13T01:00:00.000Z"));
    assert.equal(second, "duplicate");

    const afterReplay = await doc.ref.get();
    assert.equal((await inboxItems(notification.ownerUid)).length, 1);
    assert.ok(afterReplay.get("readAt") instanceof Timestamp);
    assert.equal(afterReplay.get("readAt").toMillis(), Date.parse("2026-07-13T02:00:00.000Z"));
    assert.equal(afterReplay.get("createdAt").toMillis(), Date.parse("2026-07-13T00:00:00.000Z"));
  });

  it("persists only the 8 allowlisted envelope keys and allowlisted payload keys", async () => {
    const writer = firestoreFeedEngagementNotificationWriter(firestore);
    const notification = planFeedCommentNotification({
      postId: uniqueId("post"),
      actorUid: "actor-envelope",
      actorName: "Jordan",
      commentBody: "Nice split!",
      post: { authorUid: "author-envelope", status: "published" },
      socialActivityEnabled: true,
    });
    assert.ok(notification);
    await writer.persist(notification, Date.now());

    const items = await inboxItems(notification.ownerUid);
    const doc = items.find((item) => item.id === notification.deliveryKey);
    assert.ok(doc);
    for (const key of Object.keys(doc.data())) {
      assert.ok((ALLOWED_ENVELOPE_KEYS as readonly string[]).includes(key), `unexpected envelope key: ${key}`);
    }
    const data = doc.get("data") as Record<string, unknown>;
    for (const key of Object.keys(data)) {
      assert.ok(
        (ALLOWED_FEED_ENGAGEMENT_PAYLOAD_KEYS as readonly string[]).includes(key),
        `unexpected payload key: ${key}`,
      );
    }
    for (const forbidden of ["actorUid", "actorDisplayName", "commentId", "distance", "duration"]) {
      assert.equal(data[forbidden], undefined, `payload leaked forbidden key: ${forbidden}`);
    }
  });
});

describe("emitFeedLikeNotification (emulator)", () => {
  beforeEach(async () => {
    await deleteCollection("feedPosts");
    await deleteCollection("notificationInbox");
    await deleteCollection("userProfiles");
    await deleteCollection("notificationPreferences");
    await deleteDevices();
  });

  it("writes exactly one inbox doc resolving the actor's display name from userProfiles", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author";
    const actorUid = "emit-actor";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    await firestore.doc(`userProfiles/${actorUid}`).set({ displayName: "Riley" });

    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.parse("2026-07-20T00:00:00.000Z"));

    const items = await inboxItems(authorUid);
    assert.equal(items.length, 1);
    assert.equal(items[0]!.get("title"), "Riley liked your run");
    assert.ok(items[0]!.get("createdAt") instanceof Timestamp);
    assert.equal(items[0]!.get("readAt"), null);
  });

  it("falls back to Someone when no profile displayName is available", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-2";
    const actorUid = "emit-actor-2";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    // No userProfiles/{actorUid} document at all.

    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now());

    const items = await inboxItems(authorUid);
    assert.equal(items.length, 1);
    assert.equal(items[0]!.get("title"), "Someone liked your run");
  });

  it("writes nothing when the like doc is already gone (double-tap like/unlike race)", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-3";
    const actorUid = "emit-actor-3";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    // Deliberately no likes/{actorUid} doc: it was already removed by the time
    // this emitter re-reads committed state.

    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now());

    assert.equal((await inboxItems(authorUid)).length, 0);
  });

  it("never throws when the injected writer throws (terminal-state independence)", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-4";
    const actorUid = "emit-actor-4";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    const throwingWriter: FeedEngagementNotificationWriter = {
      persist: async () => {
        throw new Error("simulated persist failure");
      },
    };

    await assert.doesNotReject(() =>
      emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now(), { writer: throwingWriter }),
    );
  });

  it("does not notify a self-like", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-5";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${authorUid}`).set({ userUid: authorUid });

    await emitFeedLikeNotification(firestore, { postId, actorUid: authorUid }, Date.now());

    assert.equal((await inboxItems(authorUid)).length, 0);
  });

  it("sends a push to every enabled token on a written (first) like", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-push-1";
    const actorUid = "emit-actor-push-1";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    await registerToken(authorUid, "fp-1", "token-1");
    await registerToken(authorUid, "fp-2", "token-2");
    const { port, sent } = fakeMessaging();

    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now(), {
      messaging: port,
      writer: stubWriter("written"),
    });

    assert.equal(sent.length, 2);
    assert.deepEqual(sent.map((call) => call.token).sort(), ["token-1", "token-2"]);
    for (const call of sent) {
      assert.deepEqual(call.data, { kind: "feed_post_liked", route: "feedComments", postId });
    }
  });

  it("sends nothing on a duplicate (already-notified) like", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-push-2";
    const actorUid = "emit-actor-push-2";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    await registerToken(authorUid, "fp-1", "token-1");

    // This call establishes the already-notified state. It may itself return
    // "duplicate" rather than "written", because the real `feedLikeCreated`
    // trigger fires on the like write above and may reach the inbox doc first
    // (see `stubWriter`). Either way the state this test needs is in place, so
    // the assertion below is unaffected — only the reason differs.
    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now());

    const { port, sent } = fakeMessaging();
    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now(), { messaging: port });

    assert.equal(sent.length, 0);
  });

  it("still resolves when the push send fails, and does not affect the inbox write", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-push-3";
    const actorUid = "emit-actor-push-3";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port } = fakeMessaging({ shouldThrow: true });

    await assert.doesNotReject(() =>
      emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now(), { messaging: port }),
    );

    assert.equal((await inboxItems(authorUid)).length, 1);
  });

  it("suppresses before any device read: self-like never attempts a send even with an enabled token registered", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-push-4";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${authorUid}`).set({ userUid: authorUid });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port, sent } = fakeMessaging();

    await emitFeedLikeNotification(firestore, { postId, actorUid: authorUid }, Date.now(), { messaging: port });

    assert.equal(sent.length, 0);
  });

  it("suppresses before any device read when socialActivityEnabled is false", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-push-5";
    const actorUid = "emit-actor-push-5";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    await firestore.doc(`notificationPreferences/${authorUid}`).set({ socialActivityEnabled: false });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port, sent } = fakeMessaging();

    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now(), { messaging: port });

    assert.equal(sent.length, 0);
  });

  it("suppresses before any device read for an unpublished parent post", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-author-push-6";
    const actorUid = "emit-actor-push-6";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "deleting" });
    await firestore.doc(`feedPosts/${postId}/likes/${actorUid}`).set({ userUid: actorUid });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port, sent } = fakeMessaging();

    await emitFeedLikeNotification(firestore, { postId, actorUid }, Date.now(), { messaging: port });

    assert.equal(sent.length, 0);
  });
});

describe("emitFeedCommentNotification (emulator)", () => {
  beforeEach(async () => {
    await deleteCollection("feedPosts");
    await deleteCollection("notificationInbox");
    await deleteCollection("notificationPreferences");
    await deleteDevices();
  });

  it("writes exactly one inbox doc using the comment's own denormalised author fields", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author";
    const actorUid = "emit-c-actor";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "Great effort out there!",
    });

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now());

    const items = await inboxItems(authorUid);
    assert.equal(items.length, 1);
    assert.equal(items[0]!.get("title"), "Sam commented on your run");
    assert.equal(items[0]!.get("body"), '"Great effort out there!"');
  });

  it("does not notify when the preferences document disables social activity", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-2";
    const actorUid = "emit-c-actor-2";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "hello",
    });
    await firestore.doc(`notificationPreferences/${authorUid}`).set({ socialActivityEnabled: false });

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now());

    assert.equal((await inboxItems(authorUid)).length, 0);
  });

  it("writes nothing for a non-published (deleting) parent post", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-3";
    const actorUid = "emit-c-actor-3";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "deleting" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "hello",
    });

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now());

    assert.equal((await inboxItems(authorUid)).length, 0);
  });

  it("sends a push to every enabled token on a written (first) comment", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-push-1";
    const actorUid = "emit-c-actor-push-1";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "Great effort out there!",
    });
    await registerToken(authorUid, "fp-1", "token-1");
    await registerToken(authorUid, "fp-2", "token-2");
    const { port, sent } = fakeMessaging();

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now(), {
      messaging: port,
      writer: stubWriter("written"),
    });

    assert.equal(sent.length, 2);
    assert.deepEqual(sent.map((call) => call.token).sort(), ["token-1", "token-2"]);
    for (const call of sent) {
      assert.equal(call.notification.title, "Sam commented on your run");
      assert.equal(call.notification.body, '"Great effort out there!"');
      assert.deepEqual(call.data, { kind: "feed_post_commented", route: "feedComments", postId });
    }
  });

  it("sends nothing on a duplicate (already-notified) comment", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-push-2";
    const actorUid = "emit-c-actor-push-2";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "hello",
    });
    await registerToken(authorUid, "fp-1", "token-1");

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now());

    const { port, sent } = fakeMessaging();
    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now(), {
      messaging: port,
    });

    assert.equal(sent.length, 0);
  });

  it("still resolves when the push send fails, and does not affect the inbox write", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-push-3";
    const actorUid = "emit-c-actor-push-3";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "hello",
    });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port } = fakeMessaging({ shouldThrow: true });

    await assert.doesNotReject(() =>
      emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now(), { messaging: port }),
    );

    assert.equal((await inboxItems(authorUid)).length, 1);
  });

  it("suppresses before any device read when socialActivityEnabled is false", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-push-4";
    const actorUid = "emit-c-actor-push-4";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "published" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "hello",
    });
    await firestore.doc(`notificationPreferences/${authorUid}`).set({ socialActivityEnabled: false });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port, sent } = fakeMessaging();

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now(), {
      messaging: port,
    });

    assert.equal(sent.length, 0);
  });

  it("suppresses before any device read for an unpublished parent post", async () => {
    const postId = uniqueId("post");
    const authorUid = "emit-c-author-push-5";
    const actorUid = "emit-c-actor-push-5";
    await firestore.doc(`feedPosts/${postId}`).set({ authorUid, status: "deleting" });
    await firestore.doc(`feedPosts/${postId}/comments/comment-1`).set({
      authorUid: actorUid,
      authorDisplayName: "Sam",
      body: "hello",
    });
    await registerToken(authorUid, "fp-1", "token-1");
    const { port, sent } = fakeMessaging();

    await emitFeedCommentNotification(firestore, { postId, commentId: "comment-1" }, Date.now(), {
      messaging: port,
    });

    assert.equal(sent.length, 0);
  });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function inboxItems(uid: string) {
  return (await firestore.collection("notificationInbox").doc(uid).collection("items").get()).docs;
}

async function deleteCollection(name: string): Promise<void> {
  const snapshot = await firestore.collection(name).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}

async function deleteDevices(): Promise<void> {
  const snapshot = await firestore.collection("notificationDevices").get();
  await Promise.all(
    snapshot.docs.map(async (doc) => {
      const tokens = await doc.ref.collection("tokens").get();
      await Promise.all(tokens.docs.map((token) => token.ref.delete()));
      await doc.ref.delete();
    }),
  );
}
