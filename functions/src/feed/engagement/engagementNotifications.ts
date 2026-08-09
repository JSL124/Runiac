// Feed engagement notifications: per-interaction (like/comment) inbox pings
// (WP1).
//
// This module turns a single committed like/comment write into a low-noise
// inbox ping for the post's author. It is deliberately decoupled from the
// count-recompute transaction in `engagement.ts`: every emitter runs AFTER
// that transaction has committed and re-reads the committed post/like/
// comment/preference state, so a notification failure can never fail or roll
// back the already-durable engagement count.
//
// Deliberate trade-offs baked into this module (read before changing):
//   - Identity is NOT scrubbed. Unlike the challenge module (which is
//     deliberately identity-free because a departing participant's uid must
//     never linger in a roster ping), a "X liked your run" / "X commented on
//     your run" notification is meaningless without the actor's name. The
//     actor's display name is baked into the notification `title` at WRITE
//     TIME, so a later unfriend/block cannot retroactively scrub it from an
//     already-delivered notification. This is the opposite choice from the
//     challenge module, made deliberately, not by oversight.
//   - Only the FIRST like and FIRST comment from a given actor on a given
//     post ever notifies. The deterministic delivery key
//     `postId:kind:actorUid` is guarded by a transactional create, so a
//     repeat like (unlike/relike) or a repeat comment from the same actor on
//     the same post is silent by design — this is a low-noise social ping,
//     not a full activity log.
//   - Because delivery is keyed by (postId, kind, actorUid) and not by the
//     underlying like/comment document id, a like notification can legally
//     outlive the like itself: unliking after the notification was already
//     written does not retract it. Only a like that is already gone by the
//     time the emitter re-reads it (the double-tap like/unlike race)
//     suppresses the notification.
//   - Minimal allowlisted payload: ONLY the keys in
//     ALLOWED_FEED_ENGAGEMENT_PAYLOAD_KEYS reach the client `data` map —
//     never the actor's uid/display name, the comment id, or the run's
//     distance/duration. The client resolves "who" from the delivered
//     title/body text, not from the payload.
//   - Per-event read cost: each emitter performs a small, fixed number of
//     extra reads (parent post, then the like/comment doc + preferences doc
//     in one batch) to resolve suppression and, for likes only, the actor's
//     display name. This is bounded and only runs on the (comparatively
//     rare) first like/comment per actor per post.
//   - Every emitter is wrapped in `safeEmit` and NEVER throws to its caller:
//     the aggregate count is already committed by the time these run, and v2
//     Firestore triggers do not retry by default, so swallowing here is the
//     correct failure mode, not a shortcut.
//   - The FCM push (see `engagementPush.ts`) is sent ONLY when `persist()`
//     returns "written", never on "duplicate". The inbox writer's
//     transactional create on the deterministic delivery key is already the
//     exactly-once guard, so reusing that result keeps push dedup identical
//     to inbox dedup instead of standing up a second ledger for the same
//     decision.

import { Timestamp, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import type { FeedEngagementNotificationKind } from "../../notifications/types.js";
import { socialActivityEnabled } from "../../notifications/scheduledPushReaders.js";
import { sendFeedEngagementPush, type FeedEngagementMessagingPort } from "./engagementPush.js";

// ---------------------------------------------------------------------------
// Allowlisted client payload
// ---------------------------------------------------------------------------

// The ONLY keys permitted in a persisted feed engagement notification `data`
// map. The payload-allowlist test enumerates this and fails on any extra key.
export const ALLOWED_FEED_ENGAGEMENT_PAYLOAD_KEYS = ["kind", "route", "postId"] as const;

// Foreground destination hint. The client routes on this; it carries no data.
export type FeedEngagementNotificationRoute = "feedComments";

export type FeedEngagementNotificationPayload = {
  readonly kind: FeedEngagementNotificationKind;
  readonly route: FeedEngagementNotificationRoute;
  readonly postId: string;
};

export type FeedEngagementNotification = {
  readonly ownerUid: string;
  readonly deliveryKey: string;
  readonly title: string;
  readonly body: string;
  readonly payload: FeedEngagementNotificationPayload;
};

// ---------------------------------------------------------------------------
// Copy (pinned exactly by tests)
// ---------------------------------------------------------------------------

export const FEED_ENGAGEMENT_FALLBACK_ACTOR_NAME = "Someone";
export const COMMENT_BODY_MAX_CHARS = 80;
export const FEED_LIKE_NOTIFICATION_BODY = "Tap to open your run post.";

export function feedLikeNotificationTitle(actorName: string): string {
  return `${actorName} liked your run`;
}

export function feedCommentNotificationTitle(actorName: string): string {
  return `${actorName} commented on your run`;
}

export function feedCommentNotificationBody(truncatedBody: string): string {
  return `"${truncatedBody}"`;
}

// Trim, collapse internal whitespace runs to a single space, then cap at
// COMMENT_BODY_MAX_CHARS CODE POINTS (never UTF-16 code units, or a surrogate
// pair emoji sitting on the boundary would split in half). `Array.from`
// iterates by code point, so slicing it is safe where `String#slice` is not.
export function truncateCommentBody(rawBody: string): string {
  const collapsed = rawBody.trim().replace(/\s+/g, " ");
  const codePoints = Array.from(collapsed);
  if (codePoints.length <= COMMENT_BODY_MAX_CHARS) {
    return collapsed;
  }
  return `${codePoints.slice(0, COMMENT_BODY_MAX_CHARS - 1).join("")}…`;
}

// ---------------------------------------------------------------------------
// Deterministic delivery key
// ---------------------------------------------------------------------------

// `postId` and `actorUid` are Firestore auto-ids / auth uids (no slashes);
// `:` is a legal doc-id character. Deliberately NOT versioned like the
// challenge module's key: only the first like/comment per actor per post is
// ever meant to notify, so there is no "next version" to fold in.
export function feedEngagementDeliveryKey(
  postId: string,
  kind: FeedEngagementNotificationKind,
  actorUid: string,
): string {
  return `${postId}:${kind}:${actorUid}`;
}

// ---------------------------------------------------------------------------
// Pure planners
// ---------------------------------------------------------------------------

type PlannedParentPost = {
  readonly authorUid: string;
  readonly status: string;
};

function isNotifiable(input: {
  readonly postId: string;
  readonly actorUid: string;
  readonly post: PlannedParentPost;
  readonly socialActivityEnabled: boolean;
}): boolean {
  if (input.postId.length === 0) return false;
  if (input.actorUid.length === 0) return false;
  if (input.actorUid === input.post.authorUid) return false; // never notify on self-engagement.
  if (!input.socialActivityEnabled) return false;
  if (input.post.status !== "published") return false;
  return true;
}

function resolvedActorName(actorName: string): string {
  return actorName.length > 0 ? actorName : FEED_ENGAGEMENT_FALLBACK_ACTOR_NAME;
}

export type PlanFeedLikeNotificationInput = {
  readonly postId: string;
  readonly actorUid: string;
  // Already-resolved actor display name; pass "" to take the Someone fallback.
  readonly actorName: string;
  readonly post: PlannedParentPost;
  readonly socialActivityEnabled: boolean;
};

export function planFeedLikeNotification(
  input: PlanFeedLikeNotificationInput,
): FeedEngagementNotification | null {
  if (!isNotifiable(input)) return null;
  return {
    ownerUid: input.post.authorUid,
    deliveryKey: feedEngagementDeliveryKey(input.postId, "feed_post_liked", input.actorUid),
    title: feedLikeNotificationTitle(resolvedActorName(input.actorName)),
    body: FEED_LIKE_NOTIFICATION_BODY,
    payload: { kind: "feed_post_liked", route: "feedComments", postId: input.postId },
  };
}

export type PlanFeedCommentNotificationInput = {
  readonly postId: string;
  readonly actorUid: string;
  // Already-resolved actor display name; pass "" to take the Someone fallback.
  readonly actorName: string;
  readonly commentBody: string;
  readonly post: PlannedParentPost;
  readonly socialActivityEnabled: boolean;
};

export function planFeedCommentNotification(
  input: PlanFeedCommentNotificationInput,
): FeedEngagementNotification | null {
  if (!isNotifiable(input)) return null;
  const truncated = truncateCommentBody(input.commentBody);
  // An empty (post-trim) comment body has nothing to quote; fall back to the
  // same generic body the like notification uses rather than showing `""`.
  const body = truncated.length === 0 ? FEED_LIKE_NOTIFICATION_BODY : feedCommentNotificationBody(truncated);
  return {
    ownerUid: input.post.authorUid,
    deliveryKey: feedEngagementDeliveryKey(input.postId, "feed_post_commented", input.actorUid),
    title: feedCommentNotificationTitle(resolvedActorName(input.actorName)),
    body,
    payload: { kind: "feed_post_commented", route: "feedComments", postId: input.postId },
  };
}

// ---------------------------------------------------------------------------
// Persistence (deterministic-key create-collision dedup)
// ---------------------------------------------------------------------------

export type FeedEngagementNotificationWriteStatus = "written" | "duplicate";

export type FeedEngagementNotificationWriter = {
  readonly persist: (
    notification: FeedEngagementNotification,
    nowMs: number,
  ) => Promise<FeedEngagementNotificationWriteStatus>;
};

// Writes to notificationInbox/{ownerUid}/items/{deliveryKey}. The
// transactional exists-check + create is the idempotency guard AND the
// correctness guard: it must NEVER overwrite an existing doc, because an
// overwrite would resurrect a `readAt` the recipient already cleared by
// reading the notification. Envelope is exactly 8 keys, matching the existing
// client inbox contract (no `clientManaged` key — that is a different
// module's concern).
export function firestoreFeedEngagementNotificationWriter(
  firestore: Firestore,
): FeedEngagementNotificationWriter {
  return {
    persist: async (notification, nowMs) => {
      const ref = firestore
        .collection("notificationInbox")
        .doc(notification.ownerUid)
        .collection("items")
        .doc(notification.deliveryKey);
      const timestamp = Timestamp.fromMillis(nowMs);
      return firestore.runTransaction(async (transaction) => {
        const existing = await transaction.get(ref);
        if (existing.exists) return "duplicate";
        transaction.create(ref, {
          ownerUid: notification.ownerUid,
          deliveryKey: notification.deliveryKey,
          title: notification.title,
          body: notification.body,
          createdAt: timestamp,
          readAt: null,
          data: { ...notification.payload },
          updatedAt: timestamp,
        });
        return "written";
      });
    },
  };
}

export type FeedEngagementNotificationDeps = {
  readonly writer?: FeedEngagementNotificationWriter;
  readonly messaging?: FeedEngagementMessagingPort;
};

// Runs an emitter body, guaranteeing it never throws to the caller. The count
// recompute this rides alongside is already committed by the time an emitter
// runs, and v2 Firestore triggers do not retry by default, so swallowing here
// is the correct failure mode, not a shortcut.
async function safeEmit(run: () => Promise<void>): Promise<void> {
  try {
    await run();
  } catch (error) {
    console.error("[feedEngagementNotifications] emit failed", error);
  }
}

// ---------------------------------------------------------------------------
// Committed-state readers
// ---------------------------------------------------------------------------

function readString(data: DocumentData | undefined, key: string): string {
  const value = data?.[key];
  return typeof value === "string" ? value : "";
}

// ---------------------------------------------------------------------------
// Per-event emitters (each re-reads committed state, never throws)
// ---------------------------------------------------------------------------

export type EmitFeedLikeNotificationInput = {
  readonly postId: string;
  readonly actorUid: string;
};

// like created → the post author, unless the actor is the author, feed
// notifications are disabled for the author, the post is not published, or
// the like doc is already gone (a fast unlike racing this emitter). The
// actor's own display name read is wrapped in its OWN try/catch so a
// transient profile-read failure degrades the name to the Someone fallback
// rather than losing the notification entirely.
export async function emitFeedLikeNotification(
  firestore: Firestore,
  input: EmitFeedLikeNotificationInput,
  nowMs: number = Date.now(),
  deps: FeedEngagementNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const postRef = firestore.collection("feedPosts").doc(input.postId);
    // The post must be read first: it determines the self-engagement check
    // and the preferences document owner (the author), both needed before the
    // remaining reads can be addressed.
    const postSnap = await postRef.get();
    const postData = postSnap.data();
    const authorUid = readString(postData, "authorUid");
    const status = readString(postData, "status");
    // A missing/malformed parent has no valid preferences-document owner to
    // address; bail before constructing a `.doc("")` reference (Firestore
    // rejects an empty document id), rather than relying on `safeEmit` to
    // paper over it.
    if (authorUid.length === 0) return;

    const [likeSnap, actorName, prefsSnap] = await Promise.all([
      postRef.collection("likes").doc(input.actorUid).get(),
      resolveActorDisplayName(firestore, input.actorUid),
      firestore.collection("notificationPreferences").doc(authorUid).get(),
    ]);

    // The like that triggered this event may already be gone (double-tap
    // like/unlike). Nothing to notify in that case.
    if (!likeSnap.exists) return;

    const writer = deps.writer ?? firestoreFeedEngagementNotificationWriter(firestore);
    const notification = planFeedLikeNotification({
      postId: input.postId,
      actorUid: input.actorUid,
      actorName: actorName ?? "",
      post: { authorUid, status },
      socialActivityEnabled: socialActivityEnabled(prefsSnap.data(), undefined),
    });
    if (notification === null) return;
    const writeStatus = await writer.persist(notification, nowMs);
    // Only a fresh write rings the recipient's phone; a "duplicate" means this
    // exact (postId, kind, actorUid) event already delivered a push earlier.
    if (writeStatus !== "written") return;
    await sendFeedEngagementPush(
      firestore,
      deps.messaging ?? getMessaging(),
      notification,
      new Date(nowMs).toISOString(),
    );
  });
}

export type EmitFeedCommentNotificationInput = {
  readonly postId: string;
  readonly commentId: string;
};

// comment created → the post author, unless the actor is the author, feed
// notifications are disabled for the author, the post is not published, or
// the comment doc is already gone. No profile read here — `authorUid`,
// `authorDisplayName`, and `body` all live on the comment doc itself.
export async function emitFeedCommentNotification(
  firestore: Firestore,
  input: EmitFeedCommentNotificationInput,
  nowMs: number = Date.now(),
  deps: FeedEngagementNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const postRef = firestore.collection("feedPosts").doc(input.postId);
    // As with likes, the post must be read first to determine the
    // self-engagement check and the preferences document owner.
    const postSnap = await postRef.get();
    const postData = postSnap.data();
    const authorUid = readString(postData, "authorUid");
    const status = readString(postData, "status");
    // See the matching guard in emitFeedLikeNotification: a missing/malformed
    // parent has no valid preferences-document owner to address.
    if (authorUid.length === 0) return;

    const [commentSnap, prefsSnap] = await Promise.all([
      postRef.collection("comments").doc(input.commentId).get(),
      firestore.collection("notificationPreferences").doc(authorUid).get(),
    ]);

    if (!commentSnap.exists) return;
    const commentData = commentSnap.data();
    const actorUid = readString(commentData, "authorUid");
    const actorName = readString(commentData, "authorDisplayName");
    const commentBody = readString(commentData, "body");

    const writer = deps.writer ?? firestoreFeedEngagementNotificationWriter(firestore);
    const notification = planFeedCommentNotification({
      postId: input.postId,
      actorUid,
      actorName,
      commentBody,
      post: { authorUid, status },
      socialActivityEnabled: socialActivityEnabled(prefsSnap.data(), undefined),
    });
    if (notification === null) return;
    const writeStatus = await writer.persist(notification, nowMs);
    // See the matching comment in emitFeedLikeNotification: push rides the
    // inbox writer's exactly-once result rather than getting its own guard.
    if (writeStatus !== "written") return;
    await sendFeedEngagementPush(
      firestore,
      deps.messaging ?? getMessaging(),
      notification,
      new Date(nowMs).toISOString(),
    );
  });
}

// Wrapped in its own try/catch (never rejects) so a transient failure here
// only degrades the actor's name to the fallback, not the whole notification.
async function resolveActorDisplayName(firestore: Firestore, actorUid: string): Promise<string | null> {
  try {
    const snap = await firestore.collection("userProfiles").doc(actorUid).get();
    const displayName = readString(snap.data(), "displayName");
    return displayName.length > 0 ? displayName : null;
  } catch {
    return null;
  }
}
