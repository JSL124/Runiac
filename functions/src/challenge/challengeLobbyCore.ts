// Challenge lobby / invitation / slot / explicit-start transaction cores.
//
// This is the trust-boundary transaction layer for Todo 4. It owns nine
// server-authored operations (catalog read, lobby create, invite, respond,
// withdraw, cancel, start, active read, pending-invitation read). Every mutation
// runs in a single Firestore transaction with no partial writes; every state
// transition goes through the pure state machine; every failure path throws a
// stable reason code via `challengeError`. Lobby expiry is lazily enforced:
// any operation touching a RECRUITING instance at/after its expiry instant
// marks it EXPIRED (releasing slots + expiring invitations) and its writes
// COMMIT even though the caller's requested action then fails with
// LOBBY_EXPIRED. A later scheduled sweep (Todo 6) reuses `shouldExpireLobby`.
//
// This module reads friend/block state directly from the same Firestore
// collections the feed uses (`users/{uid}/friends`, `users/{uid}/blockedUsers`)
// and reuses `evaluateFeedRelationship` — it does NOT import feed storage code.

import { Timestamp, type Firestore, type Transaction } from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { evaluateFeedRelationship } from "../feed/relationship.js";
import {
  CHALLENGE_CATALOG,
  CHALLENGE_TIER_IDS,
  buildChallengeRulesSnapshot,
  isChallengeTierId,
} from "./challengeCatalog.js";
import { CHALLENGE_CATALOG_VERSION } from "./challengeTypes.js";
import type {
  ChallengeMode,
  ChallengeRulesSnapshot,
  ChallengeTierId,
  InstanceState,
  InvitationState,
  ParticipantState,
} from "./challengeTypes.js";
import { challengeError } from "./challengeErrors.js";
import { resolveProfileAvatarUrl, type AvatarUrlContext } from "../profile/avatar/avatarPaths.js";
import { NULL_AVATAR_URL_CONTEXT } from "../profile/avatar/avatarUrlContextDefaults.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../security/accountStatus.js";
import { loadChallengeAccessConfig } from "../config/configLoader.js";
import { isPremiumSubscription } from "../progression/progressionAuditHelpers.js";
import { resolveProfileLevelDisplay } from "../progression/profileLevelDisplay.js";
import {
  emitChallengeInvitationNotifications,
  emitChallengeStartedNotifications,
} from "./challengeNotifications.js";
import { LOBBY_TTL_MS, shouldExpireLobby } from "./challengeExpiry.js";
import { buildParticipantIdentity } from "./challengeIdentity.js";
import {
  isInstanceTerminal,
  transitionInstance,
  transitionInvitation,
  transitionParticipant,
} from "./challengeStateMachine.js";

import {
  deriveChallengeMode,
  instanceRef,
  invitationId,
  invitationRef,
  invitationsForChallengeQuery,
  participantRef,
  participantsQuery,
  profileRef,
  readReciprocalRelationship,
  readNumber,
  readRoster,
  readRules,
  readString,
  requireAuthUid,
  requireChallengeId,
  requireInviteeUids,
  requireInviteId,
  requireResponse,
  requireTierId,
  serializeInstance,
  slotRef,
  sortedParticipantViews,
  timestampToMillis,
  type CallableRequest,
  type ChallengeInstanceView,
  type ChallengeParticipantView,
  type ParticipantLiveDisplay,
} from "./challengeLobbySupport.js";

export type {
  CallableRequest,
  ChallengeInstanceView,
  ChallengeParticipantView,
} from "./challengeLobbySupport.js";

// ---------------------------------------------------------------------------
// Loaded lobby state (single read pass — all reads precede any write)
// ---------------------------------------------------------------------------

type LoadedLobby = {
  readonly ref: DocumentReference;
  readonly data: DocumentData;
  readonly status: InstanceState;
  readonly ownerUid: string;
  readonly roster: readonly string[];
  readonly rules: ChallengeRulesSnapshot | undefined;
  readonly lobbyExpiresAtMs: number;
  readonly participants: QuerySnapshot;
  readonly invitations: QuerySnapshot;
  readonly rosterSlots: ReadonlyMap<string, DocumentSnapshot>;
};

async function loadLobby(
  transaction: Transaction,
  firestore: Firestore,
  challengeId: string,
): Promise<LoadedLobby> {
  const ref = instanceRef(firestore, challengeId);
  const instanceSnap = await transaction.get(ref);
  if (!instanceSnap.exists) throw challengeError("CHALLENGE_NOT_FOUND");
  const data = instanceSnap.data() as DocumentData;
  const roster = readRoster(data);
  const participants = await transaction.get(participantsQuery(firestore, challengeId));
  const invitations = await transaction.get(invitationsForChallengeQuery(firestore, challengeId));
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
    rules: readRules(data),
    lobbyExpiresAtMs: timestampToMillis(data["lobbyExpiresAt"]),
    participants,
    invitations,
    rosterSlots,
  };
}

// Release the slot for a roster member if (and only if) it still points at this
// challenge. Prevents clobbering a slot the user re-acquired elsewhere.
function releaseRosterSlot(
  transaction: Transaction,
  firestore: Firestore,
  loaded: LoadedLobby,
  challengeId: string,
  uid: string,
): void {
  const snap = loaded.rosterSlots.get(uid);
  if (snap !== undefined && snap.exists && readString(snap.data(), "challengeId") === challengeId) {
    transaction.delete(snap.ref);
  }
}

// Commit the lazy EXPIRE side effects: instance EXPIRED, roster participants
// CANCELLED, all roster slots released, PENDING invitations EXPIRED. Writes
// COMMIT — the caller signals LOBBY_EXPIRED after the transaction resolves.
function applyLobbyExpiry(
  transaction: Transaction,
  firestore: Firestore,
  loaded: LoadedLobby,
  challengeId: string,
  nowMs: number,
): void {
  const result = transitionInstance(loaded.status, { type: "EXPIRE_LOBBY" }, { kind: "system" });
  if (!result.ok) return; // already terminal — nothing to expire
  transaction.update(loaded.ref, {
    status: "EXPIRED",
    terminalReason: "LOBBY_EXPIRED",
    settledAt: Timestamp.fromMillis(nowMs),
  });
  for (const doc of loaded.participants.docs) {
    cancelParticipantIfActive(transaction, doc);
  }
  for (const uid of loaded.roster) {
    releaseRosterSlot(transaction, firestore, loaded, challengeId, uid);
  }
  for (const doc of loaded.invitations.docs) {
    expirePendingInvitation(transaction, doc);
  }
}

function cancelParticipantIfActive(transaction: Transaction, doc: DocumentSnapshot): void {
  const status = readString(doc.data(), "status") as ParticipantState;
  const role = readString(doc.data(), "role") === "owner" ? "owner" : "member";
  const result = transitionParticipant({ state: status, role }, { type: "CANCEL" }, { kind: "system" });
  if (!result.ok) return;
  transaction.update(doc.ref, { status: "CANCELLED", result: "CANCELLED" });
}

function expirePendingInvitation(transaction: Transaction, doc: DocumentSnapshot): void {
  const status = readString(doc.data(), "status");
  if (status !== "PENDING") return;
  transaction.update(doc.ref, { status: "EXPIRED", respondedAt: Timestamp.now() });
}

function revokePendingInvitation(transaction: Transaction, doc: DocumentSnapshot): void {
  const status = readString(doc.data(), "status");
  if (status !== "PENDING") return;
  transaction.update(doc.ref, { status: "REVOKED", respondedAt: Timestamp.now() });
}

// ---------------------------------------------------------------------------
// 1. getChallengeCatalog
// ---------------------------------------------------------------------------

export async function getChallengeCatalogForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<{
  readonly version: string;
  readonly tiers: readonly (typeof CHALLENGE_CATALOG)[ChallengeTierId][];
  readonly premiumOnlyTiers: readonly string[];
}> {
  requireAuthUid(request);
  // Additive field: clients that predate tier gating ignore it. The catalog
  // entries themselves stay immutable — entitlement lives in config, not here.
  const premiumOnlyTiers = (await loadChallengeAccessConfig(firestore)).premiumOnlyTiers;
  return {
    version: CHALLENGE_CATALOG_VERSION,
    tiers: CHALLENGE_TIER_IDS.map((tierId) => CHALLENGE_CATALOG[tierId]),
    premiumOnlyTiers,
  };
}

// ---------------------------------------------------------------------------
// 2. createChallengeLobby
// ---------------------------------------------------------------------------

export type CreateLobbyResult = {
  readonly challengeId: string;
  readonly status: string;
  readonly idempotent: boolean;
};

export async function createChallengeLobbyForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<CreateLobbyResult> {
  const uid = requireAuthUid(request);
  const tierId = requireTierId(request.data);
  const rules = buildChallengeRulesSnapshot(tierId);
  // Entitlement gate (config/challengeAccess, admin-console-administered):
  // premium-only tiers reject lobby creation for non-premium callers. Loaded
  // outside the transaction — the config doc is not part of the transactional
  // state, and the loader falls back to defaults on any failure. Only lobby
  // CREATION is gated: invited friends may join a premium owner's lobby
  // regardless of their own tier, and an owner whose subscription lapses
  // after creation keeps the already-created lobby.
  const premiumOnlyTiers = (await loadChallengeAccessConfig(firestore)).premiumOnlyTiers;
  const tierRequiresPremium = premiumOnlyTiers.includes(tierId);

  return firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    if (tierRequiresPremium) {
      const callerSnap = await transaction.get(firestore.doc(`users/${uid}`));
      if (!isPremiumSubscription(callerSnap.data(), nowMs)) {
        throw challengeError("PREMIUM_REQUIRED");
      }
    }
    const slotSnap = await transaction.get(slotRef(firestore, uid));
    const profileSnap = await transaction.get(profileRef(firestore, uid));

    if (slotSnap.exists) {
      const heldChallengeId = readString(slotSnap.data(), "challengeId");
      const heldRole = readString(slotSnap.data(), "role");
      const heldTierId = readString(slotSnap.data(), "tierId");
      const heldInstance = await loadHeldInstance(transaction, firestore, heldChallengeId);

      if (heldInstance === undefined || isInstanceTerminal(heldInstance.status)) {
        // Stale slot pointing at a missing/terminal instance — reclaim it.
        transaction.delete(slotSnap.ref);
      } else if (
        heldInstance.status === "RECRUITING" &&
        shouldExpireLobby({
          status: heldInstance.status,
          lobbyExpiresAtMs: heldInstance.lobbyExpiresAtMs,
          nowMs,
        })
      ) {
        applyLobbyExpiry(transaction, firestore, heldInstance, heldChallengeId, nowMs);
      } else if (heldInstance.status === "RECRUITING" && heldRole === "owner" && heldTierId === tierId) {
        // Idempotent retry: caller already owns a live lobby of this tier.
        return { challengeId: heldChallengeId, status: "RECRUITING", idempotent: true };
      } else {
        throw challengeError("ALREADY_HOLDS_SLOT");
      }
    }

    const challengeId = firestore.collection("challengeInstances").doc().id;
    const createdAt = Timestamp.fromMillis(nowMs);
    const expiresAt = Timestamp.fromMillis(nowMs + LOBBY_TTL_MS);
    const identity = buildParticipantIdentity(profileSnap.data());

    transaction.set(instanceRef(firestore, challengeId), {
      challengeId,
      ownerUid: uid,
      tierId,
      catalogVersion: CHALLENGE_CATALOG_VERSION,
      mode: deriveChallengeMode(1),
      status: "RECRUITING",
      rules,
      rosterUids: [uid],
      maxParticipants: rules.maxParticipants,
      teamMeters: 0,
      createdAt,
      lobbyExpiresAt: expiresAt,
    });
    transaction.set(participantRef(firestore, challengeId, uid), {
      uid,
      role: "owner",
      status: "ACCEPTED",
      creditedMeters: 0,
      reward: "NOT_ELIGIBLE",
      displayNameSnapshot: identity.displayNameSnapshot,
      avatarInitialsSnapshot: identity.avatarInitialsSnapshot,
    });
    transaction.set(slotRef(firestore, uid), {
      uid,
      challengeId,
      tierId,
      role: "owner",
      reservedAt: createdAt,
    });

    return { challengeId, status: "RECRUITING", idempotent: false };
  });
}

// Read a slot's referenced instance into a minimal LoadedLobby-lite for
// create's slot arbitration. Returns undefined when the instance is missing.
async function loadHeldInstance(
  transaction: Transaction,
  firestore: Firestore,
  challengeId: string,
): Promise<LoadedLobby | undefined> {
  if (challengeId.length === 0) return undefined;
  const ref = instanceRef(firestore, challengeId);
  const snap = await transaction.get(ref);
  if (!snap.exists) return undefined;
  const data = snap.data() as DocumentData;
  const roster = readRoster(data);
  const participants = await transaction.get(participantsQuery(firestore, challengeId));
  const invitations = await transaction.get(invitationsForChallengeQuery(firestore, challengeId));
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
    rules: readRules(data),
    lobbyExpiresAtMs: timestampToMillis(data["lobbyExpiresAt"]),
    participants,
    invitations,
    rosterSlots,
  };
}

// ---------------------------------------------------------------------------
// 3. inviteChallengeFriends
// ---------------------------------------------------------------------------

export type InviteResult = {
  readonly challengeId: string;
  readonly invited: readonly string[];
  readonly alreadyPending: readonly string[];
};

export async function inviteChallengeFriendsForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<InviteResult> {
  const uid = requireAuthUid(request);
  const challengeId = requireChallengeId(request.data);
  const targets = requireInviteeUids(request.data);

  const outcome = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const loaded = await loadLobby(transaction, firestore, challengeId);
    if (loaded.ownerUid !== uid) throw challengeError("NOT_LOBBY_OWNER");

    // Read all relationship docs BEFORE any write (transaction ordering).
    const relationships = new Map<string, ReturnType<typeof evaluateFeedRelationship>>();
    for (const targetUid of targets) {
      if (targetUid !== uid) {
        relationships.set(
          targetUid,
          await readReciprocalRelationship(transaction, firestore, uid, targetUid),
        );
      }
    }

    if (
      loaded.status === "RECRUITING" &&
      shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
      return { expired: true as const };
    }
    if (loaded.status !== "RECRUITING") throw challengeError("LOBBY_NOT_RECRUITING");

    const rules = loaded.rules;
    if (rules === undefined) throw challengeError("LOBBY_NOT_RECRUITING");
    const rosterSet = new Set(loaded.roster);

    // Existing invitation state per recipient.
    const inviteStatusByUid = new Map<string, string>();
    for (const doc of loaded.invitations.docs) {
      inviteStatusByUid.set(readString(doc.data(), "recipientUid"), readString(doc.data(), "status"));
    }
    const countedPendingAccepted = [...inviteStatusByUid.values()].filter(
      (status) => status === "PENDING" || status === "ACCEPTED",
    ).length;

    const alreadyPending: string[] = [];
    const newTargets: string[] = [];
    for (const targetUid of targets) {
      if (targetUid === uid) throw challengeError("CANNOT_INVITE_SELF");
      if (rosterSet.has(targetUid)) throw challengeError("INVITEE_ALREADY_PARTICIPANT");
      const existing = inviteStatusByUid.get(targetUid);
      if (existing === "PENDING" || existing === "ACCEPTED") {
        alreadyPending.push(targetUid);
        continue;
      }
      newTargets.push(targetUid);
    }

    if (countedPendingAccepted + newTargets.length > rules.maxInvitedFriends) {
      throw challengeError("INVITE_CAPACITY_EXCEEDED");
    }

    for (const targetUid of newTargets) {
      const decision = relationships.get(targetUid);
      if (decision === undefined || decision.kind === "denied") {
        if (decision?.kind === "denied" && decision.reason === "blocked") {
          throw challengeError("INVITEE_BLOCKED");
        }
        throw challengeError("INVITEE_NOT_RECIPROCAL_FRIEND");
      }
    }

    const createdAt = Timestamp.fromMillis(nowMs);
    const expiresAt = loaded.data["lobbyExpiresAt"] ?? Timestamp.fromMillis(loaded.lobbyExpiresAtMs);
    for (const targetUid of newTargets) {
      const inviteId = invitationId(challengeId, targetUid);
      transaction.set(invitationRef(firestore, inviteId), {
        inviteId,
        challengeId,
        tierId: readString(loaded.data, "tierId"),
        ownerUid: uid,
        recipientUid: targetUid,
        status: "PENDING",
        createdAt,
        expiresAt,
      });
    }

    return { expired: false as const, invited: newTargets, alreadyPending };
  });

  if (outcome.expired) throw challengeError("LOBBY_EXPIRED");

  // Post-commit notification hook. Notifies only the freshly invited recipients;
  // never throws, so a delivery failure cannot roll back the created invitations.
  await emitChallengeInvitationNotifications(firestore, challengeId, outcome.invited);

  return { challengeId, invited: outcome.invited, alreadyPending: outcome.alreadyPending };
}

// ---------------------------------------------------------------------------
// 4. respondToChallengeInvitation
// ---------------------------------------------------------------------------

export type RespondResult = {
  readonly challengeId: string;
  readonly outcome: "accepted" | "declined";
  readonly idempotent: boolean;
};

export async function respondToChallengeInvitationForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<RespondResult> {
  const uid = requireAuthUid(request);
  const inviteId = requireInviteId(request.data);
  const response = requireResponse(request.data);
  // Entitlement gate (config/challengeAccess), the acceptance half of the gate
  // `createChallengeLobby` applies at creation: a premium-only tier requires
  // premium of every participant, not only of the runner who opened the lobby.
  // Loaded outside the transaction for the same reason it is there — the config
  // document is not part of the transactional state.
  const premiumOnlyTiers = (await loadChallengeAccessConfig(firestore)).premiumOnlyTiers;

  const result = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const inviteSnap = await transaction.get(invitationRef(firestore, inviteId));
    if (!inviteSnap.exists) throw challengeError("INVITATION_NOT_FOUND");
    const invite = inviteSnap.data() as DocumentData;
    if (readString(invite, "recipientUid") !== uid) throw challengeError("NOT_INVITATION_RECIPIENT");
    const challengeId = readString(invite, "challengeId");
    const inviteStatus = readString(invite, "status");

    const loaded = await loadLobby(transaction, firestore, challengeId);
    const recipientSlotSnap = await transaction.get(slotRef(firestore, uid));
    const profileSnap = await transaction.get(profileRef(firestore, uid));
    // Needed only on the accept path, but reads must precede writes and the
    // lazy-expiry seam below can write.
    const recipientUserSnap = await transaction.get(firestore.doc(`users/${uid}`));
    // Reciprocal relationship read up front (needed only for accept, but reads
    // must precede writes).
    const relationship = await readReciprocalRelationship(
      transaction,
      firestore,
      uid,
      loaded.ownerUid,
    );

    // Idempotent replays of an already-answered invitation.
    if (inviteStatus !== "PENDING") {
      if (inviteStatus === "ACCEPTED" && loaded.roster.includes(uid)) {
        return { expired: false as const, challengeId, outcome: "accepted" as const, idempotent: true };
      }
      if (inviteStatus === "DECLINED") {
        return { expired: false as const, challengeId, outcome: "declined" as const, idempotent: true };
      }
      throw challengeError("INVITATION_NOT_PENDING");
    }

    if (
      loaded.status === "RECRUITING" &&
      shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
      return { expired: true as const };
    }
    if (loaded.status !== "RECRUITING") throw challengeError("LOBBY_NOT_RECRUITING");

    if (response === "decline") {
      const transition = transitionInvitation(
        inviteStatus as InvitationState,
        { type: "DECLINE" },
        { kind: "self" },
      );
      if (!transition.ok) throw challengeError("INVITATION_NOT_PENDING");
      transaction.update(inviteSnap.ref, { status: "DECLINED", respondedAt: Timestamp.fromMillis(nowMs) });
      return { expired: false as const, challengeId, outcome: "declined" as const, idempotent: false };
    }

    // accept
    if (recipientSlotSnap.exists) throw challengeError("ALREADY_HOLDS_SLOT");
    if (relationship.kind !== "allowed_friend") throw challengeError("NOT_RECIPROCAL_FRIEND");
    // Declining is never gated: it is not entitled access, and rejecting it
    // would strand the invitation as PENDING until it expired. The INVITE path
    // is not gated either, deliberately — refusing to send an invitation to a
    // Basic friend would disclose that friend's subscription status to the
    // owner. The recipient learns it about themselves, here, and the client
    // turns this reason into their own paywall.
    if (
      premiumOnlyTiers.includes(readString(loaded.data, "tierId")) &&
      !isPremiumSubscription(recipientUserSnap.data(), nowMs)
    ) {
      throw challengeError("PREMIUM_REQUIRED");
    }
    const maxParticipants = readNumber(loaded.data, "maxParticipants");
    if (loaded.roster.length >= maxParticipants) throw challengeError("LOBBY_FULL");

    const inviteTransition = transitionInvitation(
      inviteStatus as InvitationState,
      { type: "ACCEPT" },
      { kind: "self" },
    );
    if (!inviteTransition.ok) throw challengeError("INVITATION_NOT_PENDING");

    const tierId = readString(loaded.data, "tierId");
    const identity = buildParticipantIdentity(profileSnap.data());
    const reservedAt = Timestamp.fromMillis(nowMs);

    const newRosterUids = [...loaded.roster, uid];

    transaction.update(inviteSnap.ref, { status: "ACCEPTED", respondedAt: reservedAt });
    transaction.update(loaded.ref, {
      rosterUids: newRosterUids,
      mode: deriveChallengeMode(newRosterUids.length),
    });
    transaction.set(participantRef(firestore, challengeId, uid), {
      uid,
      role: "member",
      status: "ACCEPTED",
      creditedMeters: 0,
      reward: "NOT_ELIGIBLE",
      displayNameSnapshot: identity.displayNameSnapshot,
      avatarInitialsSnapshot: identity.avatarInitialsSnapshot,
    });
    transaction.set(slotRef(firestore, uid), {
      uid,
      challengeId,
      tierId,
      role: "member",
      reservedAt,
    });

    return { expired: false as const, challengeId, outcome: "accepted" as const, idempotent: false };
  });

  if (result.expired) throw challengeError("LOBBY_EXPIRED");
  return { challengeId: result.challengeId, outcome: result.outcome, idempotent: result.idempotent };
}

// ---------------------------------------------------------------------------
// 5. withdrawFromChallengeLobby
// ---------------------------------------------------------------------------

export type WithdrawResult = {
  readonly challengeId: string;
  readonly outcome: "withdrew";
  readonly idempotent: boolean;
};

export async function withdrawFromChallengeLobbyForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<WithdrawResult> {
  const uid = requireAuthUid(request);
  const challengeId = requireChallengeId(request.data);

  const result = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const loaded = await loadLobby(transaction, firestore, challengeId);
    const participantSnap = await transaction.get(participantRef(firestore, challengeId, uid));
    if (!participantSnap.exists || !loaded.roster.includes(uid)) {
      // A LEFT participant is no longer in roster; detect idempotent replay.
      if (participantSnap.exists && readString(participantSnap.data(), "status") === "LEFT") {
        return { expired: false as const, idempotent: true };
      }
      throw challengeError("NOT_A_PARTICIPANT");
    }
    const status = readString(participantSnap.data(), "status") as ParticipantState;
    const role = readString(participantSnap.data(), "role") === "owner" ? "owner" : "member";
    if (role === "owner") throw challengeError("OWNER_CANNOT_LEAVE");
    if (status === "LEFT") return { expired: false as const, idempotent: true };

    if (
      loaded.status === "RECRUITING" &&
      shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
      return { expired: true as const };
    }
    if (loaded.status !== "RECRUITING") throw challengeError("LOBBY_NOT_RECRUITING");

    const transition = transitionParticipant({ state: status, role }, { type: "WITHDRAW" }, { kind: "self" });
    if (!transition.ok) {
      if (transition.error === "OWNER_CANNOT_LEAVE") throw challengeError("OWNER_CANNOT_LEAVE");
      throw challengeError("ILLEGAL_STATE");
    }

    const newRosterUids = loaded.roster.filter((entry) => entry !== uid);

    transaction.update(participantSnap.ref, { status: "LEFT", result: "LEFT" });
    transaction.update(loaded.ref, {
      rosterUids: newRosterUids,
      mode: deriveChallengeMode(newRosterUids.length),
    });
    releaseRosterSlot(transaction, firestore, loaded, challengeId, uid);
    return { expired: false as const, idempotent: false };
  });

  if (result.expired) throw challengeError("LOBBY_EXPIRED");
  return { challengeId, outcome: "withdrew", idempotent: result.idempotent };
}

// ---------------------------------------------------------------------------
// 6. cancelChallengeLobby
// ---------------------------------------------------------------------------

export type CancelResult = {
  readonly challengeId: string;
  readonly outcome: "cancelled";
  readonly idempotent: boolean;
};

export async function cancelChallengeLobbyForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<CancelResult> {
  const uid = requireAuthUid(request);
  const challengeId = requireChallengeId(request.data);

  const result = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const loaded = await loadLobby(transaction, firestore, challengeId);
    if (loaded.ownerUid !== uid) throw challengeError("NOT_LOBBY_OWNER");
    if (loaded.status === "CANCELLED") return { expired: false as const, idempotent: true };

    if (
      loaded.status === "RECRUITING" &&
      shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
      return { expired: true as const };
    }
    if (loaded.status !== "RECRUITING") throw challengeError("LOBBY_NOT_RECRUITING");

    const transition = transitionInstance(loaded.status, { type: "CANCEL_LOBBY" }, { kind: "owner" });
    if (!transition.ok) throw challengeError("LOBBY_NOT_RECRUITING");

    transaction.update(loaded.ref, {
      status: "CANCELLED",
      terminalReason: "LOBBY_CANCELLED",
      settledAt: Timestamp.fromMillis(nowMs),
    });
    for (const doc of loaded.participants.docs) {
      cancelParticipantIfActive(transaction, doc);
    }
    for (const rosterUid of loaded.roster) {
      releaseRosterSlot(transaction, firestore, loaded, challengeId, rosterUid);
    }
    for (const doc of loaded.invitations.docs) {
      revokePendingInvitation(transaction, doc);
    }
    return { expired: false as const, idempotent: false };
  });

  if (result.expired) throw challengeError("LOBBY_EXPIRED");
  return { challengeId, outcome: "cancelled", idempotent: result.idempotent };
}

// ---------------------------------------------------------------------------
// 7. startChallenge
// ---------------------------------------------------------------------------

export type StartResult = {
  readonly challengeId: string;
  readonly mode: ChallengeMode;
  readonly rosterUids: readonly string[];
  readonly startsAtMs: number;
  readonly scheduledEndsAtMs: number;
  readonly idempotent: boolean;
};

export async function startChallengeForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<StartResult> {
  const uid = requireAuthUid(request);
  const challengeId = requireChallengeId(request.data);

  const result = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const loaded = await loadLobby(transaction, firestore, challengeId);
    if (loaded.ownerUid !== uid) throw challengeError("NOT_LOBBY_OWNER");

    if (loaded.status === "ACTIVE") {
      // Idempotent replay of a successful start.
      return {
        expired: false as const,
        idempotent: true,
        mode: readString(loaded.data, "mode") as ChallengeMode,
        rosterUids: loaded.roster,
        startsAtMs: timestampToMillis(loaded.data["startsAt"]),
        scheduledEndsAtMs: timestampToMillis(loaded.data["scheduledEndsAt"]),
      };
    }

    if (
      loaded.status === "RECRUITING" &&
      shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
      return { expired: true as const };
    }
    if (loaded.status !== "RECRUITING") throw challengeError("LOBBY_NOT_RECRUITING");

    const rules = loaded.rules;
    if (rules === undefined) throw challengeError("LOBBY_NOT_RECRUITING");
    const rosterSize = loaded.roster.length;
    const mode: ChallengeMode = deriveChallengeMode(rosterSize);

    const transition = transitionInstance(
      loaded.status,
      { type: "START", mode, rosterSize },
      { kind: "owner" },
    );
    if (!transition.ok) throw challengeError("ILLEGAL_STATE");

    const startsAt = Timestamp.fromMillis(nowMs);
    const scheduledEndsAt = Timestamp.fromMillis(nowMs + rules.durationMs);

    transaction.update(loaded.ref, {
      status: "ACTIVE",
      mode,
      startsAt,
      scheduledEndsAt,
    });
    for (const doc of loaded.participants.docs) {
      activateParticipant(transaction, doc);
    }
    // Expire every unanswered PENDING invitation at start.
    for (const doc of loaded.invitations.docs) {
      expirePendingInvitation(transaction, doc);
    }

    return {
      expired: false as const,
      idempotent: false,
      mode,
      rosterUids: loaded.roster,
      startsAtMs: nowMs,
      scheduledEndsAtMs: nowMs + rules.durationMs,
    };
  });

  if (result.expired) throw challengeError("LOBBY_EXPIRED");

  // Post-commit notification hook. Notifies the roster (except the owner, who
  // initiated the start) only on the first start; never throws.
  if (!result.idempotent) {
    await emitChallengeStartedNotifications(firestore, challengeId);
  }

  return {
    challengeId,
    mode: result.mode,
    rosterUids: result.rosterUids,
    startsAtMs: result.startsAtMs,
    scheduledEndsAtMs: result.scheduledEndsAtMs,
    idempotent: result.idempotent,
  };
}

function activateParticipant(transaction: Transaction, doc: DocumentSnapshot): void {
  const status = readString(doc.data(), "status") as ParticipantState;
  const role = readString(doc.data(), "role") === "owner" ? "owner" : "member";
  const transition = transitionParticipant({ state: status, role }, { type: "ACTIVATE" }, { kind: "system" });
  if (!transition.ok) return;
  transaction.update(doc.ref, { status: "ACTIVE" });
}

// ---------------------------------------------------------------------------
// 8. getActiveChallenge
// ---------------------------------------------------------------------------

export type ActiveChallengeView = {
  readonly challenge: {
    readonly instance: ChallengeInstanceView;
    readonly participants: readonly ChallengeParticipantView[];
  } | null;
  // The CALLER's own premium-lapse grace window, or null. Never another roster
  // member's: `challengePremiumHolds` is denied to every client precisely so
  // that one runner's subscription state is not visible to their lobby-mates,
  // and this relay keeps that property by reading only `{uid}`.
  readonly premiumHold: { readonly graceExpiresAtMs: number } | null;
};

export async function getActiveChallengeForCallable(
  request: CallableRequest,
  firestore: Firestore,
  // Injected by the callable layer (see profile/avatar/context.ts); defaults
  // to a context that can never match a real avatar URL, so an omitted
  // context still fails closed to avatarUrlSnapshot: "" for every roster
  // member.
  avatarContext: AvatarUrlContext = NULL_AVATAR_URL_CONTEXT,
): Promise<ActiveChallengeView> {
  const uid = requireAuthUid(request);

  return firestore.runTransaction(async (transaction) => {
    const nowMs = Date.now();
    const [slotSnap, holdSnap] = await transaction.getAll(
      slotRef(firestore, uid),
      firestore.doc(`challengePremiumHolds/${uid}`),
    );
    const premiumHold =
      holdSnap !== undefined && holdSnap.exists
        ? { graceExpiresAtMs: timestampToMillis(holdSnap.data()?.["graceExpiresAt"]) }
        : null;

    if (slotSnap === undefined || !slotSnap.exists) return { challenge: null, premiumHold };
    const challengeId = readString(slotSnap.data(), "challengeId");
    if (challengeId.length === 0) return { challenge: null, premiumHold };

    let loaded: LoadedLobby;
    try {
      loaded = await loadLobby(transaction, firestore, challengeId);
    } catch {
      return { challenge: null, premiumHold };
    }

    if (
      loaded.status === "RECRUITING" &&
      shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
      return { challenge: null, premiumHold };
    }

    // Level and avatar are both backend-owned and display-only: resolve each
    // roster member's current level label and avatar URL live from their
    // profile (no write), exactly the same live-overlay treatment as
    // displayNameSnapshot/avatarInitialsSnapshot get at write time. All
    // transaction reads happen before any write, and this happy path
    // performs none.
    const participantUids = loaded.participants.docs.map((doc) =>
      readString(doc.data(), "uid"),
    );
    const liveDisplayByUid = await readParticipantLiveDisplays(transaction, firestore, participantUids, avatarContext);

    return {
      challenge: {
        instance: serializeInstance(challengeId, loaded.data),
        participants: sortedParticipantViews(loaded.participants, liveDisplayByUid),
      },
      premiumHold,
    };
  });
}

// Reads the display-only level label AND avatar URL for each participant from
// their trusted `userProfiles/{uid}` document, in a single getAll pass so the
// two are always resolved against the same profile snapshot. The level label
// falls back to `Lv.{level}` when only the numeric level is present, and to an
// empty label (client renders `Lv.0`) when neither exists. The avatar URL
// always passes through resolveProfileAvatarUrl, so a foreign, malformed, or
// missing stored value resolves to "" — never relayed as-is. Deduplicates
// refs so one getAll covers the whole roster.
async function readParticipantLiveDisplays(
  transaction: Transaction,
  firestore: Firestore,
  uids: readonly string[],
  avatarContext: AvatarUrlContext,
): Promise<ReadonlyMap<string, ParticipantLiveDisplay>> {
  const displays = new Map<string, ParticipantLiveDisplay>();
  const unique = [...new Set(uids)].filter((uid) => uid.length > 0);
  if (unique.length === 0) return displays;
  const snaps = await transaction.getAll(...unique.map((uid) => profileRef(firestore, uid)));
  unique.forEach((uid, index) => {
    const data = snaps[index]?.data();
    // Both level halves come from the one shared reader `getFriendLevels` and
    // `getFeedAuthorLevels` use, so a roster row's level and ring read exactly
    // like the same runner's Friends row. It replaces a local level-label
    // helper this file used to keep, which had drifted into a duplicate of
    // that reader's label rules.
    const levelDisplay = resolveProfileLevelDisplay(data);
    displays.set(uid, {
      levelLabel: levelDisplay.levelLabel,
      avatarUrl: resolveProfileAvatarUrl(data, avatarContext),
      levelProgressPercent: levelDisplay.levelProgressPercent,
    });
  });
  return displays;
}

// ---------------------------------------------------------------------------
// 9. getChallengeInvitations
// ---------------------------------------------------------------------------

export type PendingInvitationView = {
  readonly inviteId: string;
  readonly challengeId: string;
  readonly tierId: string;
  readonly ownerUid: string;
  readonly createdAtMs: number;
  readonly expiresAtMs: number;
  readonly rules: ChallengeRulesSnapshot | null;
};

// ---------------------------------------------------------------------------
// Scheduled-sweep lazy-expiry entry point (Todo 6)
// ---------------------------------------------------------------------------

// Transactionally applies the existing lazy-expiry seam to one RECRUITING
// lobby. Used by the deadline-settlement sweep; identical side effects to the
// callable paths (instance EXPIRED, participants CANCELLED, slots released,
// PENDING invitations EXPIRED). Idempotent: re-invocation on a non-RECRUITING
// or still-live lobby is a no-op.
export async function expireChallengeLobbyById(
  firestore: Firestore,
  challengeId: string,
  nowMs: number,
): Promise<{ readonly expired: boolean }> {
  return firestore.runTransaction(async (transaction) => {
    let loaded: LoadedLobby;
    try {
      loaded = await loadLobby(transaction, firestore, challengeId);
    } catch {
      return { expired: false };
    }
    if (
      !shouldExpireLobby({ status: loaded.status, lobbyExpiresAtMs: loaded.lobbyExpiresAtMs, nowMs })
    ) {
      return { expired: false };
    }
    applyLobbyExpiry(transaction, firestore, loaded, challengeId, nowMs);
    return { expired: true };
  });
}

export async function getChallengeInvitationsForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<{ readonly invitations: readonly PendingInvitationView[] }> {
  const uid = requireAuthUid(request);
  const snapshot = await firestore
    .collection("challengeInvitations")
    .where("recipientUid", "==", uid)
    .where("status", "==", "PENDING")
    .get();

  const invitations = snapshot.docs
    .map((doc): PendingInvitationView => {
      const data = doc.data();
      const tierId = readString(data, "tierId");
      const rules = isChallengeTierId(tierId) ? buildChallengeRulesSnapshot(tierId) : null;
      return {
        inviteId: readString(data, "inviteId"),
        challengeId: readString(data, "challengeId"),
        tierId,
        ownerUid: readString(data, "ownerUid"),
        createdAtMs: timestampToMillis(data["createdAt"]),
        expiresAtMs: timestampToMillis(data["expiresAt"]),
        rules,
      };
    })
    .sort((left, right) => right.createdAtMs - left.createdAtMs);

  return { invitations };
}
