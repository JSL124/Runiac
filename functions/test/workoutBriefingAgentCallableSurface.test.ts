import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import {
  WORKOUT_BRIEFING_PREMIUM_REQUIRED_REASON,
  createWorkoutBriefingAgentHandler,
  type WorkoutBriefingCallableRequest,
} from "../src/agent/workoutBriefingAgentHandler.js";
import type {
  WorkoutBriefingModelProvider,
  WorkoutBriefingProviderRequest,
} from "../src/agent/workoutBriefingModel.js";
import { workoutBriefingSingaporeDayKey } from "../src/agent/workoutBriefingQuota.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "workout-briefing-runner";
const BASE_NOW = new Date("2026-07-10T01:00:00.000Z");
const CALLABLE_URL = "http://127.0.0.1:5001/runiac-functions-test/asia-southeast1/workoutBriefingAgent";
let firestore: Firestore;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  const snapshot = await firestore.doc(`agentUsage/${USER_UID}`)
    .collection("workoutBriefingDaily").get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
  await firestore.doc(`users/${USER_UID}`).set({
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
  });
});

describe("workoutBriefingAgent callable emulator surface", { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined }, () => {
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

  it("returns generated sections with the exact response schema", async () => {
    // Given
    const provider = new CountingProvider(safeOutput());
    const handler = injectableHandler(provider);

    // When
    const result = await handler(authenticatedRequest(validRequest()));

    // Then
    assert.deepEqual(Object.keys(result).sort(), ["delivery", "sections", "source"]);
    assert.equal(result.source, "agent");
    assert.equal(result.delivery, "generated");
    assert.deepEqual(Object.keys(result.sections).sort(), [
      "beforeYouStart",
      "howItFeels",
      "todaySession",
      "whyItHelps",
    ]);
    assert.equal(provider.calls, 1);
  });

  it("returns deterministic fallback without persisting prompts or generated copy", async () => {
    // Given
    const handler = injectableHandler(
      new CountingProvider(() => Promise.reject(new Error("private provider detail"))),
    );

    // When
    const first = await handler(authenticatedRequest(validRequest()));
    const second = await injectableHandler(new CountingProvider({ todaySession: "malformed" }))(
      authenticatedRequest(validRequest()),
    );
    const document = await dailyDocument(BASE_NOW);

    // Then
    assert.equal(first.source, "unavailable");
    assert.equal(first.delivery, "fallback");
    assert.deepEqual(second.sections, first.sections);
    // Quota is reserved before generation, so the counter exists but carries
    // only counting metadata.
    assert.equal(document.get("attemptCount"), 2);
    const persisted = JSON.stringify(document.data());
    for (const forbidden of ["prompt", "todaySession", "Thursday", "private provider detail"]) {
      assert.equal(persisted.includes(forbidden), false, `${forbidden} must not be persisted`);
    }
  });

  it("enforces five attempts per Singapore day and then answers with quota", async () => {
    // Given
    const provider = new CountingProvider(safeOutput());
    const handler = injectableHandler(provider);

    // When
    const results = [];
    for (let attempt = 0; attempt < 6; attempt += 1) {
      results.push(await handler(authenticatedRequest(validRequest())));
    }

    // Then
    assert.equal(results.slice(0, 5).every((result) => result.delivery === "generated"), true);
    const exhausted = results[5];
    assert.equal(exhausted?.source, "quota");
    assert.equal(exhausted?.delivery, "quota");
    assert.equal(
      exhausted !== undefined && "retryAfterDate" in exhausted ? exhausted.retryAfterDate : undefined,
      "2026-07-11",
    );
    // The sixth attempt never reaches the model.
    assert.equal(provider.calls, 5);
    assert.equal((await dailyDocument(BASE_NOW)).get("attemptCount"), 5);
  });

  it("keeps quota state independent across the Asia Singapore midnight boundary", async () => {
    // Given
    const beforeMidnight = new Date("2026-07-10T15:59:59.000Z");
    const afterMidnight = new Date("2026-07-10T16:00:00.000Z");
    const provider = new CountingProvider(safeOutput());

    // When
    await injectableHandler(provider, beforeMidnight)(authenticatedRequest(validRequest()));
    await injectableHandler(provider, afterMidnight)(authenticatedRequest(validRequest()));

    // Then
    assert.equal(workoutBriefingSingaporeDayKey(beforeMidnight), "20260710");
    assert.equal(workoutBriefingSingaporeDayKey(afterMidnight), "20260711");
    assert.equal((await dailyDocument(beforeMidnight)).get("attemptCount"), 1);
    assert.equal((await dailyDocument(afterMidnight)).get("attemptCount"), 1);
  });

  it("writes only counting metadata to the quota document", async () => {
    // Given
    const handler = injectableHandler(new CountingProvider(safeOutput()));

    // When
    await handler(authenticatedRequest(validRequest()));
    const document = await dailyDocument(BASE_NOW);

    // Then
    assert.deepEqual(Object.keys(document.data() ?? {}).sort(), [
      "attemptCount",
      "createdAt",
      "dayKey",
      "schemaVersion",
      "updatedAt",
    ]);
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
    assert.deepEqual(Object.keys(body["result"]["sections"]).sort(), [
      "beforeYouStart",
      "howItFeels",
      "todaySession",
      "whyItHelps",
    ]);
  });
});

function validRequest(): Record<string, unknown> {
  return {
    schemaVersion: 1,
    workout: {
      dayLabel: "Thursday · Easy Run",
      planTitle: "First Continuous Running Start",
      effortGuide: "Keep the effort easy enough to talk in full sentences.",
      weekNumber: 3,
      weekFocus: "Build repeatable easy minutes.",
    },
    metrics: [
      { label: "Distance", value: "3.0 km" },
      { label: "Time", value: "20 min" },
    ],
    steps: [{ title: "Warm up", detail: "Walk briskly for five minutes." }],
    coachNotes: ["Start slower than you think."],
  };
}

function safeOutput(): Readonly<Record<string, unknown>> {
  return {
    todaySession: "Today is a short easy run with a walking warm up first.",
    whyItHelps: "Easy running like this builds the habit without wearing you out.",
    howItFeels: "You should be able to speak in full sentences the whole way.",
    beforeYouStart: "Set off slower than feels natural and walk whenever you need to.",
  };
}

function authenticatedRequest(data: Record<string, unknown>): WorkoutBriefingCallableRequest {
  return { auth: { uid: USER_UID }, data };
}

function injectableHandler(provider: WorkoutBriefingModelProvider, now: Date = BASE_NOW) {
  return createWorkoutBriefingAgentHandler({
    firestore: () => firestore,
    now: () => now,
    providerFactory: () => provider,
  });
}

class CountingProvider implements WorkoutBriefingModelProvider {
  public calls = 0;

  public constructor(private readonly result: unknown | (() => Promise<unknown>)) {}

  public async invoke(_request: WorkoutBriefingProviderRequest): Promise<unknown> {
    this.calls += 1;
    return typeof this.result === "function" ? this.result() : this.result;
  }
}

async function dailyDocument(now: Date) {
  return firestore
    .doc(`agentUsage/${USER_UID}/workoutBriefingDaily/${workoutBriefingSingaporeDayKey(now)}`)
    .get();
}

function hasHttpsCode(code: string): (error: unknown) => boolean {
  return (error) => isRecord(error) && error["code"] === code;
}

function hasPremiumRequiredDenial(): (error: unknown) => boolean {
  return (error) =>
    isRecord(error)
    && error["code"] === "permission-denied"
    && isRecord(error["details"])
    && error["details"]["reason"] === WORKOUT_BRIEFING_PREMIUM_REQUIRED_REASON;
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
