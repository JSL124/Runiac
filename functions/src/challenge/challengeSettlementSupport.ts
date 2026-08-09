import {
  Timestamp,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { challengeError } from "./challengeErrors.js";
import type { CallableRequest } from "./challengeLobbySupport.js";
import type {
  ChallengeTerminalReason,
  InstanceState,
  ParticipantState,
} from "./challengeTypes.js";

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
export function slotRef(firestore: Firestore, uid: string): DocumentReference {
  return firestore.collection("challengeSlots").doc(uid);
}
export function grantRef(
  firestore: Firestore,
  challengeId: string,
  uid: string,
): DocumentReference {
  return firestore
    .collection("challengeRewardGrants")
    .doc(`${challengeId}_${uid}`);
}
export function badgeRef(
  firestore: Firestore,
  uid: string,
  tierId: string,
): DocumentReference {
  return firestore.doc(`users/${uid}/challengeBadges/${tierId}`);
}
export function historyRef(
  firestore: Firestore,
  uid: string,
  challengeId: string,
): DocumentReference {
  return firestore.doc(`users/${uid}/challengeHistory/${challengeId}`);
}

export function readString(data: DocumentData | undefined, key: string): string {
  const value = data?.[key];
  return typeof value === "string" ? value : "";
}
export function readNumber(data: DocumentData | undefined, key: string): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
export function timestampToMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return 0;
}
export function readRoster(data: DocumentData | undefined): readonly string[] {
  const value = data?.["rosterUids"];
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
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
export function requireChallengeId(data: unknown): string {
  const record = asRecord(data);
  const challengeId = record["challengeId"];
  if (typeof challengeId !== "string" || challengeId.length === 0) {
    throw challengeError("INVALID_ARGUMENT");
  }
  return challengeId;
}

export type LoadedInstance = {
  readonly ref: DocumentReference;
  readonly data: DocumentData;
  readonly status: InstanceState;
  readonly ownerUid: string;
  readonly roster: readonly string[];
  readonly participants: QuerySnapshot;
  readonly rosterSlots: ReadonlyMap<string, DocumentSnapshot>;
};

export async function loadInstanceWithRoster(
  transaction: Transaction,
  firestore: Firestore,
  challengeId: string,
): Promise<LoadedInstance | undefined> {
  const ref = instanceRef(firestore, challengeId);
  const snap = await transaction.get(ref);
  if (!snap.exists) return undefined;
  const data = snap.data() as DocumentData;
  const roster = readRoster(data);
  const participants = await transaction.get(ref.collection("participants"));
  const rosterSlotSnaps = await Promise.all(
    roster.map((uid) => transaction.get(slotRef(firestore, uid))),
  );
  const rosterSlots = new Map<string, DocumentSnapshot>();
  roster.forEach((uid, index) => rosterSlots.set(uid, rosterSlotSnaps[index]!));
  return {
    ref,
    data,
    status: readString(data, "status") as InstanceState,
    ownerUid: readString(data, "ownerUid"),
    roster,
    participants,
    rosterSlots,
  };
}

export function releaseSlotIfHeldHere(
  transaction: Transaction,
  loaded: LoadedInstance,
  challengeId: string,
  uid: string,
): void {
  const snap = loaded.rosterSlots.get(uid);
  if (
    snap !== undefined &&
    snap.exists &&
    readString(snap.data(), "challengeId") === challengeId
  ) {
    transaction.delete(snap.ref);
  }
}

export function buildHistoryDoc(args: {
  readonly challengeId: string;
  readonly instanceData: DocumentData;
  readonly participantData: DocumentData;
  readonly outcome: ParticipantState;
  readonly terminalReason?: ChallengeTerminalReason;
  readonly endedAtMs: number;
}): DocumentData {
  const rules = (args.instanceData["rules"] ?? {}) as DocumentData;
  return {
    challengeId: args.challengeId,
    tierId: readString(args.instanceData, "tierId"),
    mode: readString(args.instanceData, "mode"),
    role:
      readString(args.participantData, "role") === "owner"
        ? "owner"
        : "member",
    outcome: args.outcome,
    ...(args.terminalReason === undefined
      ? {}
      : { terminalReason: args.terminalReason }),
    teamMeters: readNumber(args.instanceData, "teamMeters"),
    personalMeters: readNumber(args.participantData, "creditedMeters"),
    targetMeters: readNumber(rules, "targetMeters"),
    personalMinimumMeters: readNumber(rules, "personalMinimumMeters"),
    startedAt: Timestamp.fromMillis(
      timestampToMillis(args.instanceData["startsAt"]),
    ),
    endedAt: Timestamp.fromMillis(args.endedAtMs),
  };
}
