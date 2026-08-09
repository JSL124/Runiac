import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import {
  ACTIVITY_FEEDBACK_PREMIUM_REQUIRED_REASON,
  createActivityFeedbackAgentHandler,
  type ActivityFeedbackCallableRequest,
} from "../src/agent/activityFeedbackAgentHandler.js";
import type {
  ActivityFeedbackModelProvider,
  ActivityFeedbackProviderRequest,
} from "../src/agent/activityFeedbackModel.js";
import {
  activityFeedbackSingaporeDayKey,
  reserveActivityFeedbackQuota,
} from "../src/agent/activityFeedbackQuota.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "activity-feedback-runner";
const BASE_NOW = new Date("2026-07-10T01:00:00.000Z");
const CALLABLE_URL = "http://127.0.0.1:5001/runiac-functions-test/asia-southeast1/activityFeedbackAgent";
let firestore: Firestore;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  const snapshot = await firestore.doc(`agentUsage/${USER_UID}`)
    .collection("activityFeedbackDaily").get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
  // Activity feedback is premium-gated server-side; the shared test runner
  // is premium so the existing behaviour cases stay reachable.
  await firestore.doc(`users/${USER_UID}`).set({
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
  });
});

describe("activityFeedbackAgent callable emulator surface", { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined }, () => {
  it("rejects unauthenticated and malformed requests before quota state exists", async () => {
    // Given
    const handler = injectableHandler(new CountingProvider(safeOutput()));

    // When / Then
    await assert.rejects(() => handler({ data: validRequest() }), hasHttpsCode("unauthenticated"));
    await assert.rejects(
      () => handler(authenticatedRequest({ ...validRequest(), routeName: "Private loop" })),
      hasHttpsCode("invalid-argument"),
    );
    assert.equal((await dailyDocument(BASE_NOW)).exists, false);
  });

  it("denies non-premium runners with the stable premium-required reason", async () => {
    // Given
    const provider = new CountingProvider(safeOutput());
    const handler = injectableHandler(provider);
    await firestore.doc(`users/${USER_UID}`).set({ subscriptionStatus: "basic" });

    // When / Then
    await assert.rejects(
      () => handler(authenticatedRequest(validRequest())),
      hasPremiumRequiredDenial(),
    );
    assert.equal(provider.calls, 0);
    assert.equal((await dailyDocument(BASE_NOW)).exists, false);
  });

  it("denies runners with a lapsed premium expiry or no users document", async () => {
    // Given
    const provider = new CountingProvider(safeOutput());
    const handler = injectableHandler(provider);

    // When / Then — lapsed expiry
    await firestore.doc(`users/${USER_UID}`).set({
      subscriptionStatus: "premium",
      subscriptionExpiresAt: Timestamp.fromDate(new Date("2026-07-01T00:00:00.000Z")),
    });
    await assert.rejects(
      () => handler(authenticatedRequest(validRequest())),
      hasPremiumRequiredDenial(),
    );

    // When / Then — missing users document
    await firestore.doc(`users/${USER_UID}`).delete();
    await assert.rejects(
      () => handler(authenticatedRequest(validRequest())),
      hasPremiumRequiredDenial(),
    );
    assert.equal(provider.calls, 0);
  });

  it("returns generated sections with the exact shared response schema", async () => {
    // Given
    const provider = new CountingProvider(safeOutput());
    const handler = injectableHandler(provider);

    // When
    const result = await handler(authenticatedRequest(validRequest()));

    // Then
    assert.deepEqual(Object.keys(result).sort(), ["delivery", "sections", "source"]);
    assert.equal(result.source, "agent");
    assert.equal(result.delivery, "generated");
    assert.deepEqual(Object.keys(result.sections).sort(), ["improve", "nextFocus", "summary", "wentWell"]);
    assert.equal(provider.calls, 1);
  });

  it("returns deterministic fallback without persisting prompts or generated feedback", async () => {
    // Given
    const handler = injectableHandler(new CountingProvider(() => Promise.reject(new Error("private provider detail"))));

    // When
    const first = await handler(authenticatedRequest(validRequest()));
    const second = await injectableHandler(new CountingProvider({ summary: "malformed" }))(authenticatedRequest(validRequest()));
    const document = await dailyDocument(BASE_NOW);

    // Then
    assert.equal(first.source, "unavailable");
    assert.equal(first.delivery, "fallback");
    assert.deepEqual(second.sections, first.sections);
    // The quota is reserved before the provider is called, so a failed
    // generation still spends an attempt — an attempt that reached the
    // provider and cost money is exactly what the cap is counting. What must
    // never appear is the prompt or any generated text.
    assert.equal(document.get("attemptCount"), 2);
    const persisted = JSON.stringify(document.data());
    for (const forbidden of ["prompt", "summary", "wentWell", "private provider detail", "malformed"]) {
      assert.equal(persisted.includes(forbidden), false);
    }
  });

  it("caps an entitled runner at five model calls a day", async () => {
    // The callable passes no policy, so this exercises the default. It used to
    // default to "unlimited-development", which let any entitled runner drive
    // an unbounded number of paid model calls in production.
    const provider = new CountingProvider(safeOutput());
    const handler = injectableHandler(provider);

    // When
    const results = [];
    for (let attempt = 0; attempt < 6; attempt += 1) {
      results.push(await handler(authenticatedRequest(validRequest())));
    }

    // Then: five generated, the sixth refused, and the provider is never
    // reached for the refused attempt.
    assert.equal(
      results.slice(0, 5).every((result) => result.delivery === "generated"),
      true,
    );
    assert.equal(results[5]?.source, "quota");
    assert.equal(results[5]?.delivery, "quota");
    assert.equal(results[5]?.retryAfterDate, "2026-07-11");
    assert.equal(provider.calls, 5);
    assert.equal((await dailyDocument(BASE_NOW)).get("attemptCount"), 5);
  });

  it("gives each Singapore day its own quota budget", async () => {
    // Given
    const beforeMidnight = new Date("2026-07-10T15:59:59.000Z");
    const afterMidnight = new Date("2026-07-10T16:00:00.000Z");
    const provider = new CountingProvider(safeOutput());

    // When
    await injectableHandler(provider, beforeMidnight)(authenticatedRequest(validRequest()));
    await injectableHandler(provider, afterMidnight)(authenticatedRequest(validRequest()));

    // Then: the day key rolls over, so the second call spends the new day's
    // budget rather than the previous day's.
    assert.equal(activityFeedbackSingaporeDayKey(beforeMidnight), "20260710");
    assert.equal(activityFeedbackSingaporeDayKey(afterMidnight), "20260711");
    assert.equal((await dailyDocument(beforeMidnight)).get("attemptCount"), 1);
    assert.equal((await dailyDocument(afterMidnight)).get("attemptCount"), 1);
    assert.equal(provider.calls, 2);
  });

  it("still allows an explicitly injected development bypass", async () => {
    // The bypass has to stay reachable for emulator drives, but only when a
    // caller asks for it by name.
    const reservations = [];
    for (let attempt = 0; attempt < 6; attempt += 1) {
      reservations.push(await reserveActivityFeedbackQuota({
        firestore,
        uid: USER_UID,
        now: BASE_NOW,
        policy: "unlimited-development",
      }));
    }

    assert.equal(
      reservations.every((reservation) => reservation.kind === "reserved"),
      true,
    );
    assert.equal((await dailyDocument(BASE_NOW)).exists, false);
  });

  it("reserves exactly five attempts a day and stores no prompt content", async () => {
    // Given
    const reservations = [];

    // When
    for (let attempt = 0; attempt < 6; attempt += 1) {
      reservations.push(await reserveActivityFeedbackQuota({
        firestore,
        uid: USER_UID,
        now: BASE_NOW,
        policy: "enforced",
      }));
    }

    // Then
    assert.equal(
      reservations.slice(0, 5).every((reservation) => reservation.kind === "reserved"),
      true,
    );
    assert.deepEqual(reservations[5], {
      kind: "quota",
      retryAfterDate: "2026-07-11",
    });
    const document = await dailyDocument(BASE_NOW);
    assert.equal(document.get("attemptCount"), 5);
    assert.deepEqual(Object.keys(document.data() ?? {}).sort(), [
      "attemptCount",
      "createdAt",
      "dayKey",
      "schemaVersion",
      "updatedAt",
    ]);
    const persisted = JSON.stringify(document.data());
    for (const forbidden of ["prompt", "generated", "summary", "wentWell", "private provider detail"]) {
      assert.equal(persisted.includes(forbidden), false);
    }
  });

  it("keeps enforced quota state independent across Singapore midnight", async () => {
    // Given
    const beforeMidnight = new Date("2026-07-10T15:59:59.000Z");
    const afterMidnight = new Date("2026-07-10T16:00:00.000Z");

    // When
    const before = await reserveActivityFeedbackQuota({
      firestore,
      uid: USER_UID,
      now: beforeMidnight,
      policy: "enforced",
    });
    const after = await reserveActivityFeedbackQuota({
      firestore,
      uid: USER_UID,
      now: afterMidnight,
      policy: "enforced",
    });

    // Then
    assert.deepEqual(before, { kind: "reserved" });
    assert.deepEqual(after, { kind: "reserved" });
    assert.equal((await dailyDocument(beforeMidnight)).get("attemptCount"), 1);
    assert.equal((await dailyDocument(afterMidnight)).get("attemptCount"), 1);
  });

  it("exposes the authenticated callable through the Functions emulator", async () => {
    // Given
    const response = await postCallable(validRequest(), USER_UID);

    // When
    const body: unknown = await response.json();

    // Then
    assert.equal(response.status, 200);
    assert.ok(isRecord(body));
    assert.ok(isRecord(body["result"]));
    assert.ok(body["result"]["source"] === "agent" || body["result"]["source"] === "unavailable");
    assert.ok(isRecord(body["result"]["sections"]));
    assert.deepEqual(Object.keys(body["result"]["sections"]).sort(), ["improve", "nextFocus", "summary", "wentWell"]);
  });
});

function validRequest(): Record<string, unknown> {
  return {
    schemaVersion: 1,
    summary: {
      distanceKm: 5,
      durationSeconds: 1800,
      averagePaceSecondsPerKm: 360,
      caloriesKcal: 310,
      sourceLabel: "Runiac GPS",
    },
    performance: { score: 78, qualityLabel: "Steady", takeaway: "Controlled pacing", nextFocus: "Relaxed start" },
    cadence: { averageSpm: 164, isEstimated: true, confidence: "estimated" },
    unavailable: ["cadence"],
  };
}

function safeOutput(): Readonly<Record<string, unknown>> {
  return {
    summary: "You completed a steady run with useful pacing data.",
    wentWell: "Your effort stayed controlled across the available metrics.",
    improve: "Ease into the first part of the next run.",
    nextFocus: "Keep the next session calm and repeatable.",
  };
}

function authenticatedRequest(data: Record<string, unknown>): ActivityFeedbackCallableRequest {
  return { auth: { uid: USER_UID }, data };
}

function injectableHandler(provider: ActivityFeedbackModelProvider, now: Date = BASE_NOW) {
  return createActivityFeedbackAgentHandler({
    firestore: () => firestore,
    now: () => now,
    providerFactory: () => provider,
  });
}

class CountingProvider implements ActivityFeedbackModelProvider {
  public calls = 0;

  public constructor(private readonly result: unknown | (() => Promise<unknown>)) {}

  public async invoke(_request: ActivityFeedbackProviderRequest): Promise<unknown> {
    this.calls += 1;
    return typeof this.result === "function" ? this.result() : this.result;
  }
}

async function dailyDocument(now: Date) {
  return firestore.doc(`agentUsage/${USER_UID}/activityFeedbackDaily/${activityFeedbackSingaporeDayKey(now)}`).get();
}

function hasHttpsCode(code: string): (error: unknown) => boolean {
  return (error) => isRecord(error) && error["code"] === code;
}

function hasPremiumRequiredDenial(): (error: unknown) => boolean {
  return (error) =>
    isRecord(error)
    && error["code"] === "permission-denied"
    && isRecord(error["details"])
    && error["details"]["reason"] === ACTIVITY_FEEDBACK_PREMIUM_REQUIRED_REASON;
}

async function postCallable(data: Record<string, unknown>, uid: string): Promise<Response> {
  return fetch(CALLABLE_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${emulatorJwt(uid)}`,
    },
    body: JSON.stringify({ data }),
  });
}

function emulatorJwt(uid: string): string {
  const header = base64UrlEncode(JSON.stringify({ alg: "none", typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify({ sub: uid, uid }));
  return `${header}.${payload}.signature`;
}

function base64UrlEncode(value: string): string {
  return Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
