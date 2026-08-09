import assert from "node:assert/strict";
import { describe, it } from "node:test";
import * as productionFunctions from "../src/index.js";

const PROJECT_ID = "demo-runiac-challenge";
const OWNER = "ch-surface-owner";
const base = `http://127.0.0.1:5001/${PROJECT_ID}/asia-southeast1`;

const challengeExports = [
  "getChallengeCatalog",
  "createChallengeLobby",
  "inviteChallengeFriends",
  "respondToChallengeInvitation",
  "withdrawFromChallengeLobby",
  "cancelChallengeLobby",
  "startChallenge",
  "getActiveChallenge",
  "getChallengeInvitations",
] as const;

describe("Challenge callable production surface", () => {
  it("exports exactly the nine Challenge callables through the production entrypoint", () => {
    for (const name of challengeExports) {
      assert.equal(name in productionFunctions, true, `${name} must be a deployed Function export`);
    }
  });

  it("does not leak Challenge core or error helpers through the production entrypoint", () => {
    for (const name of [
      "createChallengeLobbyForCallable",
      "startChallengeForCallable",
      "challengeError",
      "shouldExpireLobby",
      "buildParticipantIdentity",
    ]) {
      assert.equal(name in productionFunctions, false, `${name} must not be a deployed Function export`);
    }
  });
});

describe("Challenge callable emulator surface", () => {
  it("rejects an unauthenticated catalog read", async () => {
    const response = await postCallable("getChallengeCatalog", {}, undefined);
    const body: unknown = await response.json();
    assert.equal(response.status, 401);
    assert.equal(readErrorStatus(body), "UNAUTHENTICATED");
  });

  it("returns the nine-tier catalog to an authenticated caller", async () => {
    const response = await postCallable("getChallengeCatalog", {}, OWNER);
    const body: unknown = await response.json();
    assert.equal(response.status, 200);
    const result = readResult(body);
    assert.equal(result["version"], "challenge-distance-v1");
    assert.ok(Array.isArray(result["tiers"]));
    assert.equal((result["tiers"] as unknown[]).length, 9);
  });

  it("surfaces stable reason codes through the callable error body", async () => {
    const response = await postCallable("createChallengeLobby", { tierId: "not-a-tier" }, OWNER);
    const body: unknown = await response.json();
    assert.equal(response.status, 400);
    assert.equal(readErrorStatus(body), "INVALID_ARGUMENT");
    assert.equal(readErrorReason(body), "UNKNOWN_TIER");
  });

  it("creates a lobby for an authenticated caller", async () => {
    const response = await postCallable("createChallengeLobby", { tierId: "10K" }, `${OWNER}-create`);
    const body: unknown = await response.json();
    assert.equal(response.status, 200);
    const result = readResult(body);
    assert.equal(typeof result["challengeId"], "string");
    assert.equal(result["status"], "RECRUITING");
  });
});

async function postCallable(name: string, data: Record<string, unknown>, uid: string | undefined): Promise<Response> {
  return fetch(`${base}/${name}`, {
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
  return Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function readResult(body: unknown): Record<string, unknown> {
  assert.ok(isObject(body) && isObject(body["result"]));
  return body["result"] as Record<string, unknown>;
}

function readErrorStatus(body: unknown): string {
  assert.ok(isObject(body) && isObject(body["error"]));
  return String((body["error"] as Record<string, unknown>)["status"]);
}

function readErrorReason(body: unknown): string {
  assert.ok(isObject(body) && isObject(body["error"]));
  const details = (body["error"] as Record<string, unknown>)["details"];
  assert.ok(isObject(details));
  return String((details as Record<string, unknown>)["reason"]);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
