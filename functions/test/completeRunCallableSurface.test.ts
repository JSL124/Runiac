import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "runner-surface-001";
const COMPLETE_RUN_URL =
  "http://127.0.0.1:5001/runiac-functions-test/asia-southeast1/completeRun";

let firestore: Firestore;

before(() => {
  if (getApps().length === 0) {
    initializeApp({ projectId: PROJECT_ID });
  }

  firestore = getFirestore();
});

beforeEach(async () => {
  await clearCollections([
    "activities",
    "runSummaries",
    "progressionEvents",
    "users",
    "userProfiles",
    "leaderboardContributions",
  ]);
  await firestore.doc(`userProfiles/${USER_UID}`).set({
    nickname: "Surface Runner",
    locationLabel: "Jurong East, Singapore",
  });
});

describe("completeRun callable emulator surface", () => {
  it("rejects unauthenticated callable HTTP requests", async () => {
    const response = await postCallable(validPayload(), undefined);
    const body: unknown = await response.json();

    assert.equal(response.status, 401);
    assert.equal(readCallableErrorStatus(body), "UNAUTHENTICATED");
  });

  it("accepts authenticated callable HTTP requests and writes backend-owned documents", async () => {
    const response = await postCallable(validPayload(), USER_UID);
    const body: unknown = await response.json();
    const result = readCallableResult(body);

    assert.equal(response.status, 200);
    assert.equal(result.validationStatus, "validated");
    assert.equal(result.progressionDisplay.xpDelta, 60);
    assert.equal(result.progressionDisplay.countsTowardLeaderboard, true);

    const activity = await firestore.doc(`activities/${result.activityId}`).get();
    const summary = await firestore.doc(`runSummaries/${result.summaryId}`).get();
    const progressionEvent = await firestore.doc(`progressionEvents/${result.progressionEventId}`).get();
    const contribution = await firestore
      .doc(`leaderboardContributions/${USER_UID}_monthly_2026-06`)
      .get();

    assert.equal(activity.get("ownerUid"), USER_UID);
    assert.equal(activity.get("validationStatus"), "validated");
    assert.equal(summary.get("ownerUid"), USER_UID);
    assert.equal(progressionEvent.get("xpDelta"), 60);
    assert.equal(progressionEvent.get("countsTowardLeaderboard"), true);
    assert.equal(contribution.get("ownerUid"), USER_UID);
    assert.equal(contribution.get("scoreXp"), 60);
    assert.equal(contribution.get("regionId"), "jurong-east");
  });

  it("accepts paused duration fields through the callable HTTP surface", async () => {
    const response = await postCallable(pausedRunPayload(), USER_UID);
    const body: unknown = await response.json();
    const result = readCallableResult(body);

    assert.equal(response.status, 200);
    assert.equal(result.validationStatus, "validated");

    const activity = await firestore.doc(`activities/${result.activityId}`).get();
    const summary = await firestore.doc(`runSummaries/${result.summaryId}`).get();

    assert.equal(activity.get("durationSeconds"), 3207);
    assert.equal(activity.get("activeDurationSeconds"), 3207);
    assert.equal(activity.get("elapsedWallSeconds"), 3900);
    assert.equal(activity.get("pausedDurationSeconds"), 693);
    assert.equal(summary.get("durationSeconds"), 3207);
    assert.equal(summary.get("activeDurationSeconds"), 3207);
    assert.equal(summary.get("elapsedWallSeconds"), 3900);
    assert.equal(summary.get("pausedDurationSeconds"), 693);
  });
});

type CallableSuccessBody = {
  result: {
    activityId: string;
    summaryId: string;
    progressionEventId: string;
    validationStatus: string;
    progressionDisplay: {
      xpDelta: number;
      countsTowardLeaderboard: boolean;
    };
  };
};

type CallableErrorBody = {
  error: {
    status: string;
  };
};

function readCallableResult(body: unknown): CallableSuccessBody["result"] {
  assert.ok(isObject(body));
  assert.ok("result" in body);
  const result = body["result"];
  assert.ok(isObject(result));
  assert.equal(typeof result["activityId"], "string");
  assert.equal(typeof result["summaryId"], "string");
  assert.equal(typeof result["progressionEventId"], "string");
  assert.equal(typeof result["validationStatus"], "string");
  assert.ok(isObject(result["progressionDisplay"]));
  assert.equal(typeof result["progressionDisplay"]["xpDelta"], "number");
  assert.equal(typeof result["progressionDisplay"]["countsTowardLeaderboard"], "boolean");

  return result as CallableSuccessBody["result"];
}

function readCallableErrorStatus(body: unknown): string {
  assert.ok(isObject(body));
  assert.ok("error" in body);
  const error = body["error"];
  assert.ok(isObject(error));
  assert.equal(typeof error["status"], "string");

  return (error as CallableErrorBody["error"]).status;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

async function postCallable(data: Record<string, unknown>, uid: string | undefined): Promise<Response> {
  return fetch(COMPLETE_RUN_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(uid === undefined ? {} : { authorization: `Bearer ${emulatorJwt(uid)}` }),
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
  return Buffer.from(value)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function validPayload(): Record<string, unknown> {
  return {
    clientRunSessionId: "surface-session-001",
    startedAt: "2026-06-14T09:00:00.000Z",
    completedAt: "2026-06-14T09:25:00.000Z",
    durationSeconds: 1500,
    distanceMeters: 3200,
    avgPaceSecondsPerKm: 469,
    source: "mobile",
    routePrivacy: "private",
  };
}

function pausedRunPayload(): Record<string, unknown> {
  return {
    clientRunSessionId: "surface-paused-session-001",
    startedAt: "2026-06-14T09:00:00.000Z",
    completedAt: "2026-06-14T10:05:00.000Z",
    durationSeconds: 3207,
    activeDurationSeconds: 3207,
    elapsedWallSeconds: 3900,
    pausedDurationSeconds: 693,
    distanceMeters: 8460,
    avgPaceSecondsPerKm: 379,
    source: "mobile",
    routePrivacy: "private",
  };
}

async function clearCollections(collectionNames: readonly string[]): Promise<void> {
  await Promise.all(
    collectionNames.map(async (collectionName) => {
      const snapshot = await firestore.collection(collectionName).get();
      await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
    }),
  );
}
