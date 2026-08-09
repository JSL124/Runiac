// Privacy-safe Challenge notifications, inbox payloads, durable history pings
// (Todo 7).
//
// This module turns committed Challenge state transitions (invitation created,
// start, non-owner leave, owner abandon, deadline/target settlement, badge
// grant) into per-recipient inbox notifications. It is deliberately decoupled
// from the transaction cores: every emitter runs AFTER the state transaction has
// committed and re-reads the committed instance/participant state, so a
// notification failure can never fail or roll back a terminal state transition.
//
// Non-negotiable guarantees enforced here:
//   - Terminal state independence: every emitter swallows its own errors; the
//     lobby/settlement hooks call these AFTER their transaction resolves, so a
//     dispatch/persist failure (invalid token, offline inbox write) never
//     blocks history/settlement state.
//   - Deterministic delivery keys (`challengeId : kind : recipientUid : version`)
//     used as the inbox document id, guarded by a transactional create so a
//     retried settlement/sweep run delivers exactly once.
//   - Minimal allowlisted payload: ONLY the keys in ALLOWED_CHALLENGE_PAYLOAD_KEYS
//     reach the client `data` map — never friend uid lists, route geometry,
//     activity ids, raw run timestamps, or any other user's metres/profile.

import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { DocumentData, QuerySnapshot } from "firebase-admin/firestore";
import type { ChallengeNotificationKind } from "../notifications/types.js";
import type { ParticipantState } from "./challengeTypes.js";

// ---------------------------------------------------------------------------
// Allowlisted client payload
// ---------------------------------------------------------------------------

// The ONLY keys permitted in a persisted challenge notification `data` map.
// The payload-allowlist test enumerates this and fails on any extra key.
export const ALLOWED_CHALLENGE_PAYLOAD_KEYS = [
  "challengeId",
  "tierId",
  "kind",
  "route",
  "outcome",
  "creditedMeters",
] as const;

// Foreground destination hints. The client routes on these; they carry no data.
export type ChallengeNotificationRoute =
  | "challengeInvitations"
  | "challengeProgress"
  | "challengeResult";

export type ChallengeNotificationPayload = {
  readonly challengeId: string;
  readonly tierId: string;
  readonly kind: ChallengeNotificationKind;
  readonly route: ChallengeNotificationRoute;
  // The RECIPIENT's own terminal outcome only (never another user's).
  readonly outcome?: string;
  // The RECIPIENT's own credited metres only (never another user's).
  readonly creditedMeters?: number;
};

export type ChallengeNotification = {
  readonly recipientUid: string;
  readonly deliveryKey: string;
  readonly title: string;
  readonly body: string;
  readonly payload: ChallengeNotificationPayload;
};

// One recipient of a planned notification. `outcome`/`creditedMeters` are the
// recipient's own values, included only for result/badge notifications.
export type ChallengeNotificationRecipient = {
  readonly uid: string;
  readonly outcome?: string;
  readonly creditedMeters?: number;
};

// ---------------------------------------------------------------------------
// Pure planner
// ---------------------------------------------------------------------------

export type PlanChallengeNotificationsInput = {
  readonly notificationKind: ChallengeNotificationKind;
  readonly route: ChallengeNotificationRoute;
  readonly title: string;
  readonly body: string;
  readonly challengeId: string;
  readonly tierId: string;
  // Deterministic discriminator folded into the delivery key. For terminal
  // events this is the instance terminalReason (one per challenge → stable key);
  // for repeatable events (leave) a monotonic count keeps distinct events apart
  // without exposing any other user's identity.
  readonly version: string;
  readonly recipients: readonly ChallengeNotificationRecipient[];
};

// Deterministic inbox document id. `challengeId` and `uid` are Firestore
// auto-ids / auth uids (no slashes); `:` is a legal doc-id character.
export function challengeDeliveryKey(
  challengeId: string,
  notificationKind: ChallengeNotificationKind,
  recipientUid: string,
  version: string,
): string {
  return `${challengeId}:${notificationKind}:${recipientUid}:${version}`;
}

export function planChallengeNotifications(
  input: PlanChallengeNotificationsInput,
): readonly ChallengeNotification[] {
  const notifications: ChallengeNotification[] = [];
  const seen = new Set<string>();
  for (const recipient of input.recipients) {
    if (recipient.uid.length === 0 || seen.has(recipient.uid)) continue;
    seen.add(recipient.uid);
    const payload: ChallengeNotificationPayload = {
      challengeId: input.challengeId,
      tierId: input.tierId,
      kind: input.notificationKind,
      route: input.route,
      ...(recipient.outcome === undefined ? {} : { outcome: recipient.outcome }),
      ...(recipient.creditedMeters === undefined
        ? {}
        : { creditedMeters: recipient.creditedMeters }),
    };
    notifications.push({
      recipientUid: recipient.uid,
      deliveryKey: challengeDeliveryKey(
        input.challengeId,
        input.notificationKind,
        recipient.uid,
        input.version,
      ),
      title: input.title,
      body: input.body,
      payload,
    });
  }
  return notifications;
}

// ---------------------------------------------------------------------------
// Persistence (deterministic-key create-collision dedup)
// ---------------------------------------------------------------------------

export type ChallengeNotificationWriteStatus = "written" | "duplicate";

export type ChallengeNotificationWriter = {
  readonly persist: (
    notification: ChallengeNotification,
    nowMs: number,
  ) => Promise<ChallengeNotificationWriteStatus>;
};

// Writes to notificationInbox/{uid}/items/{deliveryKey}. The transactional
// exists-check + create is the idempotency guard: a retried settlement/sweep
// run that re-plans the same delivery key finds the doc present and skips it, so
// each recipient is delivered exactly once. Doc shape matches the existing
// client inbox contract (title/body/createdAt/readAt/data) so the challenge
// payload rides in the client-visible `data` map.
export function firestoreChallengeNotificationWriter(
  firestore: Firestore,
): ChallengeNotificationWriter {
  return {
    persist: async (notification, nowMs) => {
      const ref = firestore
        .collection("notificationInbox")
        .doc(notification.recipientUid)
        .collection("items")
        .doc(notification.deliveryKey);
      const timestamp = Timestamp.fromMillis(nowMs);
      return firestore.runTransaction(async (transaction) => {
        const existing = await transaction.get(ref);
        if (existing.exists) return "duplicate";
        transaction.create(ref, {
          ownerUid: notification.recipientUid,
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

export type ChallengeNotificationDeps = {
  readonly writer?: ChallengeNotificationWriter;
};

async function persistAll(
  writer: ChallengeNotificationWriter,
  notifications: readonly ChallengeNotification[],
  nowMs: number,
): Promise<void> {
  for (const notification of notifications) {
    await writer.persist(notification, nowMs);
  }
}

// Runs an emitter body, guaranteeing it never throws to the caller. This is the
// structural backbone of terminal-state independence: the lobby/settlement hooks
// await these AFTER their state transaction commits, and a swallowed failure
// here can never propagate back to roll the transaction back.
async function safeEmit(run: () => Promise<void>): Promise<void> {
  try {
    await run();
  } catch (error) {
    console.error("[challengeNotifications] emit failed", error);
  }
}

// ---------------------------------------------------------------------------
// Committed-state readers
// ---------------------------------------------------------------------------

function readString(data: DocumentData | undefined, key: string): string {
  const value = data?.[key];
  return typeof value === "string" ? value : "";
}

function readNumber(data: DocumentData | undefined, key: string): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function readRoster(data: DocumentData | undefined): readonly string[] {
  const value = data?.["rosterUids"];
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

type LoadedChallenge = {
  readonly instance: DocumentData | undefined;
  readonly participants: QuerySnapshot;
};

async function loadChallenge(
  firestore: Firestore,
  challengeId: string,
): Promise<LoadedChallenge> {
  const ref = firestore.collection("challengeInstances").doc(challengeId);
  const [instanceSnap, participantsSnap] = await Promise.all([
    ref.get(),
    ref.collection("participants").get(),
  ]);
  return { instance: instanceSnap.data(), participants: participantsSnap };
}

function participantRole(data: DocumentData): "owner" | "member" {
  return readString(data, "role") === "owner" ? "owner" : "member";
}

function participantStatus(data: DocumentData): ParticipantState {
  return readString(data, "status") as ParticipantState;
}

// ---------------------------------------------------------------------------
// Per-event emitters (each re-reads committed state, never throws)
// ---------------------------------------------------------------------------

// invitation received → the invited recipients only.
export async function emitChallengeInvitationNotifications(
  firestore: Firestore,
  challengeId: string,
  recipientUids: readonly string[],
  nowMs: number = Date.now(),
  deps: ChallengeNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    if (recipientUids.length === 0) return;
    const writer = deps.writer ?? firestoreChallengeNotificationWriter(firestore);
    const { instance } = await loadChallenge(firestore, challengeId);
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_invitation_received",
      route: "challengeInvitations",
      title: "Challenge invitation",
      body: "You've been invited to a distance challenge.",
      challengeId,
      tierId: readString(instance, "tierId"),
      version: "invite",
      recipients: recipientUids.map((uid) => ({ uid })),
    });
    await persistAll(writer, notifications, nowMs);
  });
}

// challenge started → all roster except the owner (the owner initiated it).
export async function emitChallengeStartedNotifications(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
  deps: ChallengeNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const writer = deps.writer ?? firestoreChallengeNotificationWriter(firestore);
    const { instance } = await loadChallenge(firestore, challengeId);
    const ownerUid = readString(instance, "ownerUid");
    const recipients = readRoster(instance)
      .filter((uid) => uid !== ownerUid)
      .map((uid) => ({ uid }));
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_started",
      route: "challengeProgress",
      title: "Challenge started",
      body: "Your distance challenge is now underway.",
      challengeId,
      tierId: readString(instance, "tierId"),
      version: "start",
      recipients,
    });
    await persistAll(writer, notifications, nowMs);
  });
}

// participant left → remaining active roster (not the leaver, who self-exited).
// The notification is an identity-free ping; who left is read by the client from
// the member-scoped participant roster, never carried in the payload.
export async function emitChallengeParticipantLeftNotifications(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
  deps: ChallengeNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const writer = deps.writer ?? firestoreChallengeNotificationWriter(firestore);
    const { instance, participants } = await loadChallenge(firestore, challengeId);
    // Monotonic version so each successive departure yields a distinct key
    // without exposing the leaver's uid.
    const leftCount = participants.docs.filter(
      (doc) => participantStatus(doc.data()) === "LEFT",
    ).length;
    const recipients = participants.docs
      .filter((doc) => participantStatus(doc.data()) === "ACTIVE")
      .map((doc) => ({ uid: doc.id }));
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_participant_left",
      route: "challengeProgress",
      title: "A participant left",
      body: "Someone left your challenge. Their distance still counts for the team.",
      challengeId,
      tierId: readString(instance, "tierId"),
      version: `left:${leftCount}`,
      recipients,
    });
    await persistAll(writer, notifications, nowMs);
  });
}

// owner cancelled (abandon) → all non-owner participants who were still in it
// (status CANCELLED at abandon time); leavers already exited.
export async function emitChallengeOwnerCancelledNotifications(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
  deps: ChallengeNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const writer = deps.writer ?? firestoreChallengeNotificationWriter(firestore);
    const { instance, participants } = await loadChallenge(firestore, challengeId);
    const recipients = participants.docs
      .filter(
        (doc) =>
          participantRole(doc.data()) !== "owner" &&
          participantStatus(doc.data()) === "CANCELLED",
      )
      .map((doc) => ({ uid: doc.id, outcome: "CANCELLED" }));
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_owner_cancelled",
      route: "challengeResult",
      title: "Challenge cancelled",
      body: "The owner cancelled this challenge.",
      challengeId,
      tierId: readString(instance, "tierId"),
      version: "OWNER_ABANDONED",
      recipients,
    });
    await persistAll(writer, notifications, nowMs);
  });
}

// result ready → every participant who reached a settlement terminal state in
// this event (SUCCEEDED / INELIGIBLE / FAILED). Each recipient carries ONLY
// their own outcome + credited metres.
export async function emitChallengeResultReadyNotifications(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
  deps: ChallengeNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const writer = deps.writer ?? firestoreChallengeNotificationWriter(firestore);
    const { instance, participants } = await loadChallenge(firestore, challengeId);
    const terminalReason = readString(instance, "terminalReason");
    const settledStates: ReadonlySet<ParticipantState> = new Set<ParticipantState>([
      "SUCCEEDED",
      "INELIGIBLE",
      "FAILED",
    ]);
    const recipients = participants.docs
      .filter((doc) => settledStates.has(participantStatus(doc.data())))
      .map((doc) => ({
        uid: doc.id,
        outcome: participantStatus(doc.data()),
        creditedMeters: readNumber(doc.data(), "creditedMeters"),
      }));
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_result_ready",
      route: "challengeResult",
      title: "Challenge result ready",
      body: "Your challenge result is ready to view.",
      challengeId,
      tierId: readString(instance, "tierId"),
      version: terminalReason.length > 0 ? terminalReason : "settled",
      recipients,
    });
    await persistAll(writer, notifications, nowMs);
  });
}

// badge issued → each successful earner with an issued reward.
export async function emitChallengeBadgeIssuedNotifications(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
  deps: ChallengeNotificationDeps = {},
): Promise<void> {
  await safeEmit(async () => {
    const writer = deps.writer ?? firestoreChallengeNotificationWriter(firestore);
    const { instance, participants } = await loadChallenge(firestore, challengeId);
    const recipients = participants.docs
      .filter(
        (doc) =>
          participantStatus(doc.data()) === "SUCCEEDED" &&
          readString(doc.data(), "reward") === "ISSUED",
      )
      .map((doc) => ({ uid: doc.id, outcome: "SUCCEEDED" }));
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_badge_issued",
      route: "challengeResult",
      title: "Badge earned",
      body: "You earned a challenge badge.",
      challengeId,
      tierId: readString(instance, "tierId"),
      version: "TARGET_REACHED",
      recipients,
    });
    await persistAll(writer, notifications, nowMs);
  });
}
