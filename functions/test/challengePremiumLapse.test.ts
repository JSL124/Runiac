// Premium-lapse grace + eviction for challenge participation.
//
// Written test-first, before `functions/src/challenge/challengePremiumLapse.ts`
// existed. The matrix below is the behavioural contract:
//
//   sync   — opening a hold, refusing to open one, clearing one, and above all
//            NOT extending an existing one (users/{uid} is written on every
//            completeRun, so an extending sync would make the window immortal)
//   sweep  — what actually happens when the 24h window closes: member removal,
//            owner ownership-transfer, whole-instance cancellation when no
//            eligible successor exists, and the re-subscribe race
//
// Emulator-backed, in the `test:challenge` group.

import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  PREMIUM_LAPSE_GRACE_MS,
  runChallengePremiumLapseSweep,
  syncChallengePremiumHold,
} from "../src/challenge/challengePremiumLapse.js";
import { buildChallengeRulesSnapshot } from "../src/challenge/challengeCatalog.js";
import type { ChallengeTierId } from "../src/challenge/challengeTypes.js";

const PROJECT_ID = "demo-runiac-challenge";

const OWNER = "lapse-owner";
const M1 = "lapse-member-1";
const M2 = "lapse-member-2";
const OUTSIDER = "lapse-outsider";
const ALL_UIDS = [OWNER, M1, M2, OUTSIDER] as const;

// A premium-only tier under the default config, and an open one.
const PREMIUM_TIER: ChallengeTierId = "100K";
const OPEN_TIER: ChallengeTierId = "10K";

const NOW = Date.UTC(2026, 7, 4, 3, 0, 0);
const HOUR = 60 * 60 * 1000;

let firestore: Firestore;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  await firestore.recursiveDelete(firestore.collection("challengeInstances"));
  await deleteCollection("challengeSlots");
  await deleteCollection("challengePremiumHolds");
  await deleteCollection("challengeInvitations");
  await firestore.doc("config/challengeAccess").delete();
  await Promise.all(
    ALL_UIDS.map(async (uid) => {
      await firestore.doc(`users/${uid}`).delete();
      await firestore.recursiveDelete(firestore.collection(`users/${uid}/challengeHistory`));
    }),
  );
});

// ---------------------------------------------------------------------------
// syncChallengePremiumHold — when a hold opens
// ---------------------------------------------------------------------------

describe("syncChallengePremiumHold — opening a hold", () => {
  it("opens a 24h hold for a basic owner of a RECRUITING premium-tier lobby", async () => {
    const challengeId = await seedChallenge({ status: "RECRUITING", roster: [OWNER] });
    await setSubscription(OWNER, "basic");

    const result = await syncChallengePremiumHold(firestore, OWNER, NOW);

    assert.equal(result.kind, "opened");
    const hold = await holdDoc(OWNER);
    assert.equal(hold.exists, true);
    assert.equal(hold.get("challengeId"), challengeId);
    assert.equal(hold.get("role"), "owner");
    assert.equal(hold.get("tierId"), PREMIUM_TIER);
    assert.equal((hold.get("graceExpiresAt") as Timestamp).toMillis(), NOW + PREMIUM_LAPSE_GRACE_MS);
    assert.equal((hold.get("lapsedAt") as Timestamp).toMillis(), NOW);
  });

  it("is exactly 24 hours", () => {
    assert.equal(PREMIUM_LAPSE_GRACE_MS, 24 * HOUR);
  });

  it("opens a hold for a basic member of an ACTIVE premium-tier challenge", async () => {
    await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(M1, "basic");

    const result = await syncChallengePremiumHold(firestore, M1, NOW);

    assert.equal(result.kind, "opened");
    assert.equal((await holdDoc(M1)).get("role"), "member");
  });

  it("treats a premium subscription whose expiry has passed as lapsed", async () => {
    // Consistency with isPremiumSubscription(): the stored status can still say
    // `premium` while the expiry instant is in the past, which is exactly the
    // window the daily subscription sweep has not yet materialised.
    await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await firestore.doc(`users/${OWNER}`).set({
      subscriptionStatus: "premium",
      subscriptionExpiresAt: Timestamp.fromMillis(NOW - HOUR),
    });

    assert.equal((await syncChallengePremiumHold(firestore, OWNER, NOW)).kind, "opened");
  });
});

// ---------------------------------------------------------------------------
// syncChallengePremiumHold — when no hold may open
// ---------------------------------------------------------------------------

describe("syncChallengePremiumHold — cases that must NOT open a hold", () => {
  it("leaves a premium runner alone", async () => {
    await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await setSubscription(OWNER, "premium");

    assert.equal((await syncChallengePremiumHold(firestore, OWNER, NOW)).kind, "none");
    assert.equal((await holdDoc(OWNER)).exists, false);
  });

  it("leaves a basic runner on an open (non-premium) tier alone", async () => {
    await seedChallenge({ status: "ACTIVE", roster: [OWNER], tierId: OPEN_TIER });
    await setSubscription(OWNER, "basic");

    assert.equal((await syncChallengePremiumHold(firestore, OWNER, NOW)).kind, "none");
    assert.equal((await holdDoc(OWNER)).exists, false);
  });

  it("honours a stored config that opens every tier", async () => {
    await firestore.doc("config/challengeAccess").set({ premiumOnlyTiers: [] });
    await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await setSubscription(OWNER, "basic");

    assert.equal((await syncChallengePremiumHold(firestore, OWNER, NOW)).kind, "none");
  });

  it("does nothing for a runner holding no slot", async () => {
    await setSubscription(OUTSIDER, "basic");

    assert.equal((await syncChallengePremiumHold(firestore, OUTSIDER, NOW)).kind, "none");
    assert.equal((await holdDoc(OUTSIDER)).exists, false);
  });

  it("does nothing when the slot points at a terminal instance", async () => {
    for (const status of ["CANCELLED", "EXPIRED", "SUCCEEDED", "FAILED"] as const) {
      await firestore.recursiveDelete(firestore.collection("challengeInstances"));
      await deleteCollection("challengeSlots");
      await seedChallenge({ status, roster: [OWNER] });
      await setSubscription(OWNER, "basic");

      assert.equal(
        (await syncChallengePremiumHold(firestore, OWNER, NOW)).kind,
        "none",
        `terminal status ${status} must not open a hold`,
      );
    }
  });

  it("does nothing when the slot points at a missing instance", async () => {
    await firestore.doc(`challengeSlots/${OWNER}`).set({
      uid: OWNER,
      challengeId: "does-not-exist",
      tierId: PREMIUM_TIER,
      role: "owner",
      reservedAt: Timestamp.fromMillis(NOW),
    });
    await setSubscription(OWNER, "basic");

    assert.equal((await syncChallengePremiumHold(firestore, OWNER, NOW)).kind, "none");
    assert.equal((await holdDoc(OWNER)).exists, false);
  });
});

// ---------------------------------------------------------------------------
// syncChallengePremiumHold — idempotency and clearing
// ---------------------------------------------------------------------------

describe("syncChallengePremiumHold — idempotency and clearing", () => {
  it("never extends an existing hold, however often it re-runs", async () => {
    // The load-bearing case. `users/{uid}` is written by completeRun on every
    // finished run, and the trigger calls this on every such write; an
    // extending sync would push the deadline out forever and eviction would
    // never fire for an active runner.
    await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await setSubscription(OWNER, "basic");

    await syncChallengePremiumHold(firestore, OWNER, NOW);
    const first = (await holdDoc(OWNER)).get("graceExpiresAt") as Timestamp;

    const later = await syncChallengePremiumHold(firestore, OWNER, NOW + 6 * HOUR);
    assert.equal(later.kind, "unchanged");

    const second = (await holdDoc(OWNER)).get("graceExpiresAt") as Timestamp;
    assert.equal(second.toMillis(), first.toMillis());
    assert.equal(second.toMillis(), NOW + PREMIUM_LAPSE_GRACE_MS);
  });

  it("clears the hold when the runner becomes premium again", async () => {
    await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await setSubscription(OWNER, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);
    assert.equal((await holdDoc(OWNER)).exists, true);

    await setSubscription(OWNER, "premium");
    const result = await syncChallengePremiumHold(firestore, OWNER, NOW + HOUR);

    assert.equal(result.kind, "cleared");
    assert.equal((await holdDoc(OWNER)).exists, false);
  });

  it("clears the hold when the runner no longer holds a slot", async () => {
    await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);

    await firestore.doc(`challengeSlots/${M1}`).delete();
    const result = await syncChallengePremiumHold(firestore, M1, NOW + HOUR);

    assert.equal(result.kind, "cleared");
    assert.equal((await holdDoc(M1)).exists, false);
  });

  it("clears the hold when the instance reaches a terminal state", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await setSubscription(OWNER, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);

    await firestore.doc(`challengeInstances/${challengeId}`).update({ status: "SUCCEEDED" });
    const result = await syncChallengePremiumHold(firestore, OWNER, NOW + HOUR);

    assert.equal(result.kind, "cleared");
    assert.equal((await holdDoc(OWNER)).exists, false);
  });

  it("replaces a stale hold that names a different challenge", async () => {
    // The runner lapsed inside challenge A, left it, and joined premium-tier
    // challenge B while still basic. The window must restart against B rather
    // than inherit A's deadline.
    await firestore.doc(`challengePremiumHolds/${OWNER}`).set({
      uid: OWNER,
      challengeId: "stale-challenge",
      tierId: PREMIUM_TIER,
      role: "owner",
      lapsedAt: Timestamp.fromMillis(NOW - 10 * HOUR),
      graceExpiresAt: Timestamp.fromMillis(NOW + 14 * HOUR),
    });
    const challengeId = await seedChallenge({ status: "RECRUITING", roster: [OWNER] });
    await setSubscription(OWNER, "basic");

    const result = await syncChallengePremiumHold(firestore, OWNER, NOW);

    assert.equal(result.kind, "opened");
    const hold = await holdDoc(OWNER);
    assert.equal(hold.get("challengeId"), challengeId);
    assert.equal((hold.get("graceExpiresAt") as Timestamp).toMillis(), NOW + PREMIUM_LAPSE_GRACE_MS);
  });
});

// ---------------------------------------------------------------------------
// Sweep — nothing happens before the window closes
// ---------------------------------------------------------------------------

describe("runChallengePremiumLapseSweep — before the window closes", () => {
  it("evicts nobody while the grace period is still running", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 23 * HOUR);

    assert.equal(result.evictedCount, 0);
    assert.equal((await participantDoc(challengeId, M1)).get("status"), "ACTIVE");
    assert.equal((await holdDoc(M1)).exists, true);
  });

  it("clears the hold instead of evicting when the runner re-subscribed", async () => {
    // The whole point of the grace window. The hold is stale by the time the
    // sweep reaches it, and the per-user transaction re-reads the subscription
    // rather than trusting the query result.
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);
    await setSubscription(M1, "premium");

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.evictedCount, 0);
    assert.equal(result.clearedCount, 1);
    assert.equal((await participantDoc(challengeId, M1)).get("status"), "ACTIVE");
    assert.equal((await holdDoc(M1)).exists, false);
    assert.equal((await slotDoc(M1)).exists, true);
  });
});

// ---------------------------------------------------------------------------
// Sweep — member eviction
// ---------------------------------------------------------------------------

describe("runChallengePremiumLapseSweep — member eviction", () => {
  it("removes a lapsed member and leaves the challenge running for everyone else", async () => {
    const challengeId = await seedChallenge({
      status: "ACTIVE",
      roster: [OWNER, M1],
      teamMeters: 12_000,
      creditedMeters: { [M1]: 5_000 },
    });
    await setSubscription(OWNER, "premium");
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.evictedCount, 1);
    assert.equal(result.cancelledCount, 0);

    const evicted = await participantDoc(challengeId, M1);
    assert.equal(evicted.get("status"), "LEFT");
    assert.equal(evicted.get("result"), "LEFT");
    assert.equal(evicted.get("reward"), "NOT_ELIGIBLE");

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(instance.get("ownerUid"), OWNER);
    // Metres already contributed stay in the team total, exactly as a
    // self-service leave behaves.
    assert.equal(instance.get("teamMeters"), 12_000);

    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "ACTIVE");
    assert.equal((await slotDoc(M1)).exists, false);
    assert.equal((await slotDoc(OWNER)).exists, true);
    assert.equal((await holdDoc(M1)).exists, false);
  });

  it("writes a challengeHistory record preserving the evicted runner's progress", async () => {
    const challengeId = await seedChallenge({
      status: "ACTIVE",
      roster: [OWNER, M1],
      teamMeters: 12_000,
      creditedMeters: { [M1]: 5_000 },
    });
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);

    await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    const history = await firestore.doc(`users/${M1}/challengeHistory/${challengeId}`).get();
    assert.equal(history.exists, true);
    assert.equal(history.get("outcome"), "LEFT");
    assert.equal(history.get("personalMeters"), 5_000);
    assert.equal(history.get("teamMeters"), 12_000);
    assert.equal(history.get("tierId"), PREMIUM_TIER);
  });

  it("does not award a badge to the evicted runner", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);

    await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal((await firestore.doc(`users/${M1}/challengeBadges/${PREMIUM_TIER}`).get()).exists, false);
    assert.equal((await firestore.doc(`challengeRewardGrants/${challengeId}_${M1}`).get()).exists, false);
  });
});

// ---------------------------------------------------------------------------
// Sweep — owner eviction and ownership transfer
// ---------------------------------------------------------------------------

describe("runChallengePremiumLapseSweep — owner eviction", () => {
  it("transfers ownership to the remaining premium member and removes the lapsed owner", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(OWNER, "basic");
    await setSubscription(M1, "premium");
    await syncChallengePremiumHold(firestore, OWNER, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.evictedCount, 1);
    assert.equal(result.cancelledCount, 0);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(instance.get("ownerUid"), M1);

    const successor = await participantDoc(challengeId, M1);
    assert.equal(successor.get("role"), "owner");
    assert.equal(successor.get("status"), "ACTIVE");
    assert.equal((await slotDoc(M1)).get("role"), "owner");

    const departed = await participantDoc(challengeId, OWNER);
    assert.equal(departed.get("status"), "LEFT");
    assert.equal(departed.get("role"), "member", "the lapsed owner must be demoted before removal");
    assert.equal((await slotDoc(OWNER)).exists, false);
  });

  it("picks the earliest-joined eligible member as successor", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1, M2] });
    await setSubscription(OWNER, "basic");
    await setSubscription(M1, "premium");
    await setSubscription(M2, "premium");
    await syncChallengePremiumHold(firestore, OWNER, NOW);

    await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal((await instanceDoc(challengeId)).get("ownerUid"), M1);
    assert.equal((await participantDoc(challengeId, M2)).get("role"), "member");
  });

  it("skips a member who is themselves lapsed and picks the next premium one", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1, M2] });
    await setSubscription(OWNER, "basic");
    await setSubscription(M1, "basic");
    await setSubscription(M2, "premium");
    await syncChallengePremiumHold(firestore, OWNER, NOW);
    await syncChallengePremiumHold(firestore, M1, NOW);

    await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal((await instanceDoc(challengeId)).get("ownerUid"), M2);
    assert.equal((await participantDoc(challengeId, M2)).get("role"), "owner");
    // M1 lapsed at the same instant and is evicted in the same sweep.
    assert.equal((await participantDoc(challengeId, M1)).get("status"), "LEFT");
  });

  it("skips a member who already left", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1, M2] });
    await firestore
      .doc(`challengeInstances/${challengeId}/participants/${M1}`)
      .update({ status: "LEFT", result: "LEFT" });
    await setSubscription(OWNER, "basic");
    await setSubscription(M1, "premium");
    await setSubscription(M2, "premium");
    await syncChallengePremiumHold(firestore, OWNER, NOW);

    await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal((await instanceDoc(challengeId)).get("ownerUid"), M2);
  });
});

// ---------------------------------------------------------------------------
// Sweep — cancellation when no successor exists
// ---------------------------------------------------------------------------

describe("runChallengePremiumLapseSweep — cancellation with no eligible successor", () => {
  it("cancels a SOLO ACTIVE challenge whose owner lapsed", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER], mode: "SOLO" });
    await setSubscription(OWNER, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.cancelledCount, 1);
    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "CANCELLED");
    assert.equal(instance.get("terminalReason"), "OWNER_PREMIUM_LAPSED");
    assert.ok(instance.get("settledAt") instanceof Timestamp);

    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "CANCELLED");
    assert.equal((await slotDoc(OWNER)).exists, false);
    assert.equal((await holdDoc(OWNER)).exists, false);
    assert.equal((await firestore.doc(`users/${OWNER}/challengeHistory/${challengeId}`).get()).get("outcome"), "CANCELLED");
  });

  it("cancels a RECRUITING lobby and revokes its pending invitations", async () => {
    const challengeId = await seedChallenge({ status: "RECRUITING", roster: [OWNER] });
    await seedPendingInvitation(challengeId, M2);
    await setSubscription(OWNER, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.cancelledCount, 1);
    assert.equal((await instanceDoc(challengeId)).get("status"), "CANCELLED");
    assert.equal((await invitationDoc(challengeId, M2)).get("status"), "REVOKED");
  });

  it("cancels for everyone when every remaining member is also lapsed", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(OWNER, "basic");
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);
    await syncChallengePremiumHold(firestore, M1, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.cancelledCount, 1);
    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "CANCELLED");
    assert.equal(instance.get("terminalReason"), "OWNER_PREMIUM_LAPSED");
    assert.equal((await participantDoc(challengeId, M1)).get("status"), "CANCELLED");
    assert.equal((await slotDoc(M1)).exists, false);
    // Both holds are resolved by the cancellation, not left behind for a
    // second sweep to trip over.
    assert.equal((await holdDoc(OWNER)).exists, false);
    assert.equal((await holdDoc(M1)).exists, false);
  });
});

// ---------------------------------------------------------------------------
// Sweep — idempotency and defensive cases
// ---------------------------------------------------------------------------

describe("runChallengePremiumLapseSweep — idempotency and defensive cases", () => {
  it("is a no-op on a second run", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER, M1] });
    await setSubscription(OWNER, "premium");
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, M1, NOW);

    const first = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);
    const second = await runChallengePremiumLapseSweep(firestore, NOW + 26 * HOUR);

    assert.equal(first.evictedCount, 1);
    assert.equal(second.evictedCount, 0);
    assert.equal(second.cancelledCount, 0);
    assert.equal((await instanceDoc(challengeId)).get("status"), "ACTIVE");
    assert.equal((await participantDoc(challengeId, M1)).get("status"), "LEFT");
  });

  it("clears the hold without touching an already-terminal instance", async () => {
    const challengeId = await seedChallenge({ status: "ACTIVE", roster: [OWNER] });
    await setSubscription(OWNER, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);
    await firestore.doc(`challengeInstances/${challengeId}`).update({ status: "SUCCEEDED" });

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.evictedCount, 0);
    assert.equal(result.cancelledCount, 0);
    assert.equal(result.clearedCount, 1);
    assert.equal((await instanceDoc(challengeId)).get("status"), "SUCCEEDED");
    assert.equal((await holdDoc(OWNER)).exists, false);
  });

  it("drops a hold whose instance no longer exists", async () => {
    await firestore.doc(`challengePremiumHolds/${OWNER}`).set({
      uid: OWNER,
      challengeId: "vanished",
      tierId: PREMIUM_TIER,
      role: "owner",
      lapsedAt: Timestamp.fromMillis(NOW),
      graceExpiresAt: Timestamp.fromMillis(NOW + PREMIUM_LAPSE_GRACE_MS),
    });
    await setSubscription(OWNER, "basic");

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.clearedCount, 1);
    assert.equal((await holdDoc(OWNER)).exists, false);
  });

  it("evicts every due runner across separate challenges in one pass", async () => {
    const first = await seedChallenge({ status: "ACTIVE", roster: [OWNER], mode: "SOLO" });
    const second = await seedChallenge({
      challengeId: "second-challenge",
      status: "ACTIVE",
      roster: [M1],
      mode: "SOLO",
    });
    await setSubscription(OWNER, "basic");
    await setSubscription(M1, "basic");
    await syncChallengePremiumHold(firestore, OWNER, NOW);
    await syncChallengePremiumHold(firestore, M1, NOW);

    const result = await runChallengePremiumLapseSweep(firestore, NOW + 25 * HOUR);

    assert.equal(result.cancelledCount, 2);
    assert.equal((await instanceDoc(first)).get("status"), "CANCELLED");
    assert.equal((await instanceDoc(second)).get("status"), "CANCELLED");
  });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Deletes before writing, deliberately, so the write is a CREATE and never an
// UPDATE.
//
// This suite runs with the Functions emulator on, so the real
// `challengeSubscriptionChanged` trigger is live and reacts to `users/{uid}`
// updates by calling `syncChallengePremiumHold` with the REAL clock. These
// tests drive the same core with a fixed simulated clock; letting both write
// the same hold made the outcome depend on which won. It is not hypothetical —
// it is what actually happened: a trigger invocation that took 2.0s landed
// between a test's `seedChallenge` and its own `syncChallengePremiumHold`,
// stamping a real-clock deadline roughly four hours beyond the simulated sweep
// instant, so the owner was silently not due and ownership never transferred.
//
// `onDocumentUpdated` does not fire for a create, so this removes the race at
// its source while leaving the trigger itself untouched (it has no simulated
// clock in production, where this ambiguity cannot arise).
async function setSubscription(uid: string, status: "basic" | "premium"): Promise<void> {
  await firestore.doc(`users/${uid}`).delete();
  await firestore.doc(`users/${uid}`).set({ subscriptionStatus: status });
}

type SeedArgs = {
  readonly status: string;
  readonly roster: readonly string[];
  readonly challengeId?: string;
  readonly tierId?: ChallengeTierId;
  readonly mode?: "SOLO" | "GROUP";
  readonly teamMeters?: number;
  readonly creditedMeters?: Readonly<Record<string, number>>;
};

// Seeds an instance, its participants and their slots directly rather than
// driving the lobby callables, so a test can place the challenge in any state
// (including ACTIVE and terminal ones) without a multi-step setup.
async function seedChallenge(args: SeedArgs): Promise<string> {
  const challengeId = args.challengeId ?? `challenge-${args.roster.join("-")}-${args.status}`;
  const tierId = args.tierId ?? PREMIUM_TIER;
  const mode = args.mode ?? (args.roster.length > 1 ? "GROUP" : "SOLO");
  const rules = buildChallengeRulesSnapshot(tierId);
  const isActive = args.status === "ACTIVE";

  await firestore.doc(`challengeInstances/${challengeId}`).set({
    challengeId,
    ownerUid: args.roster[0],
    tierId,
    catalogVersion: rules.catalogVersion,
    mode,
    status: args.status,
    rules,
    rosterUids: [...args.roster],
    maxParticipants: rules.maxParticipants,
    teamMeters: args.teamMeters ?? 0,
    createdAt: Timestamp.fromMillis(NOW - HOUR),
    lobbyExpiresAt: Timestamp.fromMillis(NOW + 23 * HOUR),
    ...(isActive
      ? {
          startsAt: Timestamp.fromMillis(NOW - HOUR),
          scheduledEndsAt: Timestamp.fromMillis(NOW - HOUR + rules.durationMs),
        }
      : {}),
  });

  await Promise.all(
    args.roster.map(async (uid, index) => {
      const role = index === 0 ? "owner" : "member";
      await firestore.doc(`challengeInstances/${challengeId}/participants/${uid}`).set({
        uid,
        role,
        status: isActive ? "ACTIVE" : "ACCEPTED",
        creditedMeters: args.creditedMeters?.[uid] ?? 0,
        reward: "NOT_ELIGIBLE",
        displayNameSnapshot: `Runner ${uid}`,
        avatarInitialsSnapshot: uid.slice(0, 2).toUpperCase(),
      });
      await firestore.doc(`challengeSlots/${uid}`).set({
        uid,
        challengeId,
        tierId,
        role,
        reservedAt: Timestamp.fromMillis(NOW - HOUR),
      });
    }),
  );

  return challengeId;
}

async function seedPendingInvitation(challengeId: string, recipientUid: string): Promise<void> {
  const id = `${challengeId}__${recipientUid}`;
  await firestore.doc(`challengeInvitations/${id}`).set({
    inviteId: id,
    challengeId,
    tierId: PREMIUM_TIER,
    ownerUid: OWNER,
    recipientUid,
    status: "PENDING",
    createdAt: Timestamp.fromMillis(NOW - HOUR),
    expiresAt: Timestamp.fromMillis(NOW + 23 * HOUR),
  });
}

async function instanceDoc(challengeId: string) {
  return firestore.doc(`challengeInstances/${challengeId}`).get();
}

async function participantDoc(challengeId: string, uid: string) {
  return firestore.doc(`challengeInstances/${challengeId}/participants/${uid}`).get();
}

async function invitationDoc(challengeId: string, recipientUid: string) {
  return firestore.doc(`challengeInvitations/${challengeId}__${recipientUid}`).get();
}

async function slotDoc(uid: string) {
  return firestore.doc(`challengeSlots/${uid}`).get();
}

async function holdDoc(uid: string) {
  return firestore.doc(`challengePremiumHolds/${uid}`).get();
}

async function deleteCollection(name: string): Promise<void> {
  const snapshot = await firestore.collection(name).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}
