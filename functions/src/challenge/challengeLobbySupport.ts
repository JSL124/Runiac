import {
  Timestamp,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  Query,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { evaluateFeedRelationship } from "../feed/relationship.js";
import { isChallengeTierId } from "./challengeCatalog.js";
import type {
  ChallengeMode,
  ChallengeRulesSnapshot,
  ChallengeTierId,
} from "./challengeTypes.js";
import { challengeError } from "./challengeErrors.js";

export type CallableRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

export function instanceRef(
  firestore: Firestore,
  challengeId: string,
): DocumentReference {
  return firestore.collection("challengeInstances").doc(challengeId);
}
export function participantRef(
  firestore: Firestore,
  challengeId: string,
  uid: string,
): DocumentReference {
  return instanceRef(firestore, challengeId)
    .collection("participants")
    .doc(uid);
}
export function participantsQuery(
  firestore: Firestore,
  challengeId: string,
): Query {
  return instanceRef(firestore, challengeId).collection("participants");
}
export function invitationRef(
  firestore: Firestore,
  inviteId: string,
): DocumentReference {
  return firestore.collection("challengeInvitations").doc(inviteId);
}
export function invitationsForChallengeQuery(
  firestore: Firestore,
  challengeId: string,
): Query {
  return firestore
    .collection("challengeInvitations")
    .where("challengeId", "==", challengeId);
}
export function slotRef(firestore: Firestore, uid: string): DocumentReference {
  return firestore.collection("challengeSlots").doc(uid);
}
export function profileRef(firestore: Firestore, uid: string): DocumentReference {
  return firestore.collection("userProfiles").doc(uid);
}
export function friendRef(
  firestore: Firestore,
  ownerUid: string,
  otherUid: string,
): DocumentReference {
  return firestore.doc(`users/${ownerUid}/friends/${otherUid}`);
}
export function blockRef(
  firestore: Firestore,
  ownerUid: string,
  otherUid: string,
): DocumentReference {
  return firestore.doc(`users/${ownerUid}/blockedUsers/${otherUid}`);
}

export function invitationId(challengeId: string, recipientUid: string): string {
  return `${challengeId}__${recipientUid}`;
}

export function asRecord(value: unknown): Readonly<Record<string, unknown>> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw challengeError("INVALID_ARGUMENT");
  }
  return value as Readonly<Record<string, unknown>>;
}

export function requireAuthUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw challengeError("UNAUTHENTICATED");
  }
  return uid;
}

export function requireTierId(data: unknown): ChallengeTierId {
  const record = asRecord(data);
  const tierId = record["tierId"];
  if (typeof tierId !== "string") throw challengeError("INVALID_ARGUMENT");
  if (!isChallengeTierId(tierId)) throw challengeError("UNKNOWN_TIER");
  return tierId;
}

export function requireChallengeId(data: unknown): string {
  const record = asRecord(data);
  const challengeId = record["challengeId"];
  if (typeof challengeId !== "string" || challengeId.length === 0) {
    throw challengeError("INVALID_ARGUMENT");
  }
  return challengeId;
}

export function requireInviteId(data: unknown): string {
  const record = asRecord(data);
  const inviteId = record["inviteId"];
  if (typeof inviteId !== "string" || inviteId.length === 0) {
    throw challengeError("INVALID_ARGUMENT");
  }
  return inviteId;
}

export function requireInviteeUids(data: unknown): readonly string[] {
  const record = asRecord(data);
  const uids = record["uids"];
  if (!Array.isArray(uids) || uids.length === 0) {
    throw challengeError("INVALID_ARGUMENT");
  }
  const seen = new Set<string>();
  for (const value of uids) {
    if (typeof value !== "string" || value.length === 0) {
      throw challengeError("INVALID_ARGUMENT");
    }
    seen.add(value);
  }
  return [...seen];
}

export function requireResponse(data: unknown): "accept" | "decline" {
  const record = asRecord(data);
  const response = record["response"];
  if (response === "accept" || response === "decline") return response;
  throw challengeError("INVALID_ARGUMENT");
}

export function readString(data: DocumentData | undefined, key: string): string {
  const value = data?.[key];
  return typeof value === "string" ? value : "";
}

export function readNumber(data: DocumentData | undefined, key: string): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export function readRoster(data: DocumentData | undefined): readonly string[] {
  const value = data?.["rosterUids"];
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

// The single source of truth for how `mode` follows a roster: SOLO for
// exactly the owner alone, GROUP once anyone else has joined. Every
// transaction that writes `rosterUids` on `challengeInstances/{id}` (create,
// accept, withdraw, start) must pass its post-write roster size through this
// function so the stored `mode` field can never drift from the roster that
// actually backs it — the bug this closes was `rosterUids` growing on accept
// while `mode` stayed whatever it was set to at create. `serializeInstance`
// also re-derives `mode` through this same function at read time rather than
// trusting the stored value verbatim, so a document written before every
// mutation kept them in sync self-heals on the next read instead of relaying
// a stale label.
export function deriveChallengeMode(rosterSize: number): ChallengeMode {
  return rosterSize <= 1 ? "SOLO" : "GROUP";
}

export function readRules(
  data: DocumentData | undefined,
): ChallengeRulesSnapshot | undefined {
  const value = data?.["rules"];
  if (typeof value !== "object" || value === null) return undefined;
  return value as ChallengeRulesSnapshot;
}

export function timestampToMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "object" && value !== null) {
    const seconds = (value as { readonly _seconds?: unknown })._seconds;
    if (typeof seconds === "number") return seconds * 1000;
  }
  return 0;
}

export async function readReciprocalRelationship(
  transaction: Transaction,
  firestore: Firestore,
  viewerUid: string,
  authorUid: string,
): Promise<ReturnType<typeof evaluateFeedRelationship>> {
  const [viewerFriend, authorFriend, viewerBlock, authorBlock] =
    await Promise.all([
      transaction.get(friendRef(firestore, viewerUid, authorUid)),
      transaction.get(friendRef(firestore, authorUid, viewerUid)),
      transaction.get(blockRef(firestore, viewerUid, authorUid)),
      transaction.get(blockRef(firestore, authorUid, viewerUid)),
    ]);
  return evaluateFeedRelationship({
    viewerUid,
    authorUid,
    viewerHasAuthorFriend: viewerFriend.exists,
    authorHasViewerFriend: authorFriend.exists,
    viewerBlockedAuthor: viewerBlock.exists,
    authorBlockedViewer: authorBlock.exists,
  });
}

export type ChallengeInstanceView = {
  readonly challengeId: string;
  readonly ownerUid: string;
  readonly tierId: string;
  readonly catalogVersion: string;
  readonly mode: string;
  readonly status: string;
  readonly rules: ChallengeRulesSnapshot | null;
  readonly rosterUids: readonly string[];
  readonly maxParticipants: number;
  readonly teamMeters: number;
  readonly createdAtMs: number;
  readonly lobbyExpiresAtMs: number;
  readonly startsAtMs: number | null;
  readonly scheduledEndsAtMs: number | null;
  readonly terminalReason: string | null;
};

export type ChallengeParticipantView = {
  readonly uid: string;
  readonly role: string;
  readonly status: string;
  readonly creditedMeters: number;
  readonly reward: string;
  readonly displayNameSnapshot: string;
  readonly avatarInitialsSnapshot: string;
  // Backend-owned, display-only level label (e.g. "Lv.2") resolved live from
  // the participant's profile when the roster is served. Empty when the
  // participant's profile has no level yet; the client falls back to "Lv.0".
  readonly levelLabelSnapshot: string;
  // Backend-owned, display-only avatar URL resolved live from the
  // participant's profile when the roster is served, exactly like
  // levelLabelSnapshot above — never derived from anything the participant
  // doc itself stores, and never relayed unless it passes
  // resolveProfileAvatarUrl. Empty when the participant has no avatar set, or
  // when the stored value is foreign/malformed.
  readonly avatarUrlSnapshot: string;
  // Backend-owned progress toward the next level, 0..100, resolved live from
  // the participant's profile alongside levelLabelSnapshot and through the
  // same shared reader. Drives the XP ring the client draws around the roster
  // avatar; 0 when the profile carries no usable percent, which renders the
  // empty ring every roster row showed before this field existed.
  readonly levelProgressPercentSnapshot: number;
};

/** The live, per-uid display values `sortedParticipantViews` overlays onto each stored participant doc. */
export type ParticipantLiveDisplay = {
  readonly levelLabel: string;
  readonly avatarUrl: string;
  readonly levelProgressPercent: number;
};

const EMPTY_PARTICIPANT_LIVE_DISPLAY: ParticipantLiveDisplay = {
  levelLabel: "",
  avatarUrl: "",
  levelProgressPercent: 0,
};

export function serializeInstance(
  challengeId: string,
  data: DocumentData,
): ChallengeInstanceView {
  const startsAt = data["startsAt"];
  const scheduledEndsAt = data["scheduledEndsAt"];
  const terminalReason = data["terminalReason"];
  const rosterUids = readRoster(data);
  return {
    challengeId,
    ownerUid: readString(data, "ownerUid"),
    tierId: readString(data, "tierId"),
    catalogVersion: readString(data, "catalogVersion"),
    // Derived from the roster rather than read back verbatim: a legacy
    // instance written before every roster mutation kept `mode` in sync (see
    // `deriveChallengeMode`) would otherwise relay a stale SOLO/GROUP label.
    // Re-deriving here means the read path can never surface an inconsistent
    // mode, regardless of what is stored.
    mode: deriveChallengeMode(rosterUids.length),
    status: readString(data, "status"),
    rules: readRules(data) ?? null,
    rosterUids,
    maxParticipants: readNumber(data, "maxParticipants"),
    teamMeters: readNumber(data, "teamMeters"),
    createdAtMs: timestampToMillis(data["createdAt"]),
    lobbyExpiresAtMs: timestampToMillis(data["lobbyExpiresAt"]),
    startsAtMs: startsAt === undefined ? null : timestampToMillis(startsAt),
    scheduledEndsAtMs:
      scheduledEndsAt === undefined
        ? null
        : timestampToMillis(scheduledEndsAt),
    terminalReason: typeof terminalReason === "string" ? terminalReason : null,
  };
}

export function serializeParticipant(
  data: DocumentData,
  liveDisplay: ParticipantLiveDisplay = EMPTY_PARTICIPANT_LIVE_DISPLAY,
): ChallengeParticipantView {
  return {
    uid: readString(data, "uid"),
    role: readString(data, "role"),
    status: readString(data, "status"),
    creditedMeters: readNumber(data, "creditedMeters"),
    reward: readString(data, "reward"),
    displayNameSnapshot: readString(data, "displayNameSnapshot"),
    avatarInitialsSnapshot: readString(data, "avatarInitialsSnapshot"),
    levelLabelSnapshot: liveDisplay.levelLabel,
    avatarUrlSnapshot: liveDisplay.avatarUrl,
    levelProgressPercentSnapshot: liveDisplay.levelProgressPercent,
  };
}

export function sortedParticipantViews(
  snapshot: QuerySnapshot,
  liveDisplayByUid: ReadonlyMap<string, ParticipantLiveDisplay> = new Map(),
): readonly ChallengeParticipantView[] {
  return snapshot.docs
    .map((doc) => {
      const data = doc.data();
      return serializeParticipant(data, liveDisplayByUid.get(readString(data, "uid")) ?? EMPTY_PARTICIPANT_LIVE_DISPLAY);
    })
    .sort((left, right) => left.uid.localeCompare(right.uid));
}
