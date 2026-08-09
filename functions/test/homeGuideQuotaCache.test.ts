import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import {
  createHomeGuideContextFingerprint,
  finalizeHomeGuideAttemptFailure,
  finalizeHomeGuideAttemptReady,
  reserveHomeGuideQuota,
  singaporeDayKey,
  type HomeGuideBundle,
  type HomeGuideQuotaReservation,
} from "../src/agent/homeGuideQuotaCache.js";
import { parseHomeGuidePlanDisplayContext } from "../src/agent/homeGuideContracts.js";
import { planContext } from "./homeGuideEvidenceFixtures.js";
import { buildHomeGuideEvidence } from "../src/agent/homeGuideEvidence.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "guide-quota-runner";
const BASE_NOW = new Date("2026-07-10T01:00:00.000Z");
let firestore: Firestore;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  const documents = await firestore.collection("agentGuidanceDaily").get();
  await Promise.all(documents.docs.map((document) => document.ref.delete()));
});

describe("home guide daily quota/cache coordinator", { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined }, () => {
  it("uses a versioned canonical SHA-256 fingerprint that includes the active-plan marker", () => {
    const first = fingerprint("plan-alpha");
    const repeat = fingerprint("plan-alpha");
    const changedPlan = fingerprint("plan-beta");

    assert.equal(first, repeat);
    assert.match(first, /^[a-f0-9]{64}$/u);
    assert.notEqual(first, changedPlan);
  });

  it("reserves slots one through three and refuses a fourth without a provider invocation", async () => {
    let realProviderAttempts = 0;

    for (const marker of ["one", "two", "three", "four"]) {
      const result = await reserve(fingerprint(`sequential-${marker}`), BASE_NOW, marker);
      if (result.kind === "reserved") realProviderAttempts += 1;
    }

    const state = await dailyState(BASE_NOW);
    assert.equal(realProviderAttempts, 3);
    assert.equal(state.attemptCount, 3);
    assert.ok(realProviderAttempts <= state.attemptCount);
    assert.ok(state.attemptCount <= 3);
  });

  it("keeps an abandoned reservation consumed while a matching 90-second lease deduplicates", async () => {
    const fingerprintValue = fingerprint("abandoned");
    const abandoned = await reserve(fingerprintValue, BASE_NOW, "abandoned");
    const duplicate = await reserve(fingerprintValue, new Date(BASE_NOW.getTime() + 89_000), "duplicate");

    assert.equal(abandoned.kind, "reserved");
    assert.equal(duplicate.kind, "leased");
    assert.equal((await dailyState(BASE_NOW)).attemptCount, 1);
  });

  it("allows only one active lease for twenty concurrent matching requests", async () => {
    const fingerprintValue = fingerprint("concurrent");
    const results = await Promise.all(
      Array.from({ length: 20 }, (_, index) => reserve(fingerprintValue, BASE_NOW, `concurrent-${index}`)),
    );
    const reserved = results.filter((result) => result.kind === "reserved");
    const leased = results.filter((result) => result.kind === "leased");

    assert.equal(reserved.length, 1);
    assert.equal(leased.length, 19);
    assert.equal((await dailyState(BASE_NOW)).attemptCount, 1);
  });

  it("caps distinct fingerprints at three total committed slots", async () => {
    const results = await Promise.all([
      reserve(fingerprint("distinct-1"), BASE_NOW, "one"),
      reserve(fingerprint("distinct-2"), BASE_NOW, "two"),
      reserve(fingerprint("distinct-3"), BASE_NOW, "three"),
      reserve(fingerprint("distinct-4"), BASE_NOW, "four"),
    ]);

    assert.equal(results.filter((result) => result.kind === "reserved").length, 3);
    assert.equal(results.filter((result) => result.kind === "fallback").length, 1);
    assert.equal((await dailyState(BASE_NOW)).attemptCount, 3);
  });

  it("returns an exact-fingerprint ready cache without incrementing the counter", async () => {
    const fingerprintValue = fingerprint("cache");
    const reservation = await reservationFor(fingerprintValue, BASE_NOW, "cache");
    const generated = bundle("fresh");
    await finalizeHomeGuideAttemptReady({ firestore, uid: USER_UID, now: BASE_NOW, reservation, bundle: generated });

    const cached = await reserve(fingerprintValue, new Date(BASE_NOW.getTime() + 1_000), "cache-repeat");
    assert.equal(cached.kind, "cache");
    assert.deepEqual(cached.bundle, generated);
    assert.equal((await dailyState(BASE_NOW)).attemptCount, 1);
    const document = await firestore.doc(`agentGuidanceDaily/${USER_UID}_${singaporeDayKey(BASE_NOW)}`).get();
    assert.deepEqual(Object.keys(document.data() ?? {}).sort(), [
      "attemptCount",
      "createdAt",
      "dayKey",
      "ownerUid",
      "readyBundle",
      "readyFingerprint",
      "schemaVersion",
      "updatedAt",
    ]);
  });

  it("counts failed attempts, recovers after an expired lease, and rejects an expired finalizer", async () => {
    const fingerprintValue = fingerprint("failed-and-expired");
    const failed = await reservationFor(fingerprintValue, BASE_NOW, "failed");
    assert.equal(await finalizeHomeGuideAttemptFailure({ firestore, uid: USER_UID, now: BASE_NOW, reservation: failed }), true);
    const retry = await reservationFor(fingerprintValue, new Date(BASE_NOW.getTime() + 1_000), "retry");
    const expiredReplacement = await reservationFor(fingerprintValue, new Date(BASE_NOW.getTime() + 92_000), "expired");

    assert.equal(await finalizeHomeGuideAttemptReady({ firestore, uid: USER_UID, now: BASE_NOW, reservation: retry, bundle: bundle("stale") }), false);
    assert.equal(await finalizeHomeGuideAttemptReady({ firestore, uid: USER_UID, now: BASE_NOW, reservation: expiredReplacement, bundle: bundle("current") }), true);
    assert.equal((await dailyState(BASE_NOW)).attemptCount, 3);
  });

  it("rejects a matching finalizer after its lease expires even without a replacement reservation", async () => {
    const reservation = await reservationFor(fingerprint("expired-finalizer"), BASE_NOW, "expired-finalizer");
    const finalized = await finalizeHomeGuideAttemptReady({
      firestore,
      uid: USER_UID,
      now: new Date(BASE_NOW.getTime() + 91_000),
      reservation,
      bundle: bundle("late"),
    });
    const document = await firestore.doc(`agentGuidanceDaily/${USER_UID}_${singaporeDayKey(BASE_NOW)}`).get();

    assert.equal(finalized, false);
    assert.equal(document.get("readyBundle"), undefined);
    assert.equal(document.get("attemptCount"), 1);
    assert.ok(document.get("pendingAttempt").leaseExpiresAt.toMillis() <= BASE_NOW.getTime() + 91_000);
  });

  it("rejects stale completion and never returns a ready bundle for a different fingerprint", async () => {
    const firstFingerprint = fingerprint("prior-ready");
    const first = await reservationFor(firstFingerprint, BASE_NOW, "first");
    await finalizeHomeGuideAttemptReady({ firestore, uid: USER_UID, now: BASE_NOW, reservation: first, bundle: bundle("prior") });
    const secondFingerprint = fingerprint("new-context");
    const second = await reserve(secondFingerprint, new Date(BASE_NOW.getTime() + 1_000), "second");
    assert.equal(second.kind, "reserved");

    assert.equal(await finalizeHomeGuideAttemptReady({ firestore, uid: USER_UID, now: BASE_NOW, reservation: first, bundle: bundle("stale") }), false);
    assert.equal(await finalizeHomeGuideAttemptReady({ firestore, uid: USER_UID, now: BASE_NOW, reservation: second.reservation, bundle: bundle("new") }), true);
    const staleReadyRequest = await reserve(firstFingerprint, new Date(BASE_NOW.getTime() + 2_000), "old-context");
    assert.notEqual(staleReadyRequest.kind, "cache");
  });

  it("starts a new document after the Singapore midnight boundary", async () => {
    const beforeMidnight = new Date("2026-07-10T15:59:59.000Z");
    const afterMidnight = new Date("2026-07-10T16:00:00.000Z");
    assert.equal(singaporeDayKey(beforeMidnight), "2026-07-10");
    assert.equal(singaporeDayKey(afterMidnight), "2026-07-11");

    await reservationFor(fingerprint("day-one", beforeMidnight), beforeMidnight, "day-one");
    await reservationFor(fingerprint("day-two", afterMidnight), afterMidnight, "day-two");
    const documents = await firestore.collection("agentGuidanceDaily").get();

    assert.equal(documents.size, 2);
    assert.equal((await dailyState(beforeMidnight)).attemptCount, 1);
    assert.equal((await dailyState(afterMidnight)).attemptCount, 1);
  });
});

function fingerprint(activePlanMarker: string, now: Date = BASE_NOW): string {
  return createHomeGuideContextFingerprint({
    dayKey: singaporeDayKey(now),
    activePlanMarker,
    planContext: parseHomeGuidePlanDisplayContext(planContext()),
    latestAcceptedActivityMarker: "accepted-activity-marker",
    evidence: buildHomeGuideEvidence({ now, activities: [] }),
  });
}

function bundle(marker: string): HomeGuideBundle {
  return {
    planSummary: `Summary ${marker}.`,
    runningTip: `Tip ${marker}.`,
    progressionCheckIn: `Check-in ${marker}.`,
  };
}

async function reserve(fingerprintValue: string, now: Date, marker: string) {
  return reserveHomeGuideQuota({
    firestore,
    uid: USER_UID,
    now,
    fingerprint: fingerprintValue,
    fallback: bundle(`fallback-${marker}`),
  });
}

async function reservationFor(fingerprintValue: string, now: Date, marker: string): Promise<HomeGuideQuotaReservation> {
  const result = await reserve(fingerprintValue, now, marker);
  assert.equal(result.kind, "reserved");
  return result.reservation;
}

async function dailyState(now: Date) {
  const document = await firestore.doc(`agentGuidanceDaily/${USER_UID}_${singaporeDayKey(now)}`).get();
  return { attemptCount: document.get("attemptCount") };
}
