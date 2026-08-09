// Shared plumbing for emulator-integration tests that invoke a real Cloud
// Functions v2 callable over HTTP (through the Functions emulator) using a
// real Firebase Auth emulator ID token, and/or stage a real avatar PNG object
// in the Storage emulator.
//
// Extracted from profileAvatarEmulatorIntegration.test.ts so any other suite
// that needs the same real, end-to-end "sign in, stage a PNG, call the
// deployed callable, inspect the real Storage object" flow does not hand-roll
// its own copy of the wire-format and PNG-encoding details.

import assert from "node:assert/strict";
import type { Auth } from "firebase-admin/auth";
import type { getStorage } from "firebase-admin/storage";

export type EmulatorActor = { readonly uid: string; readonly token: string };

export type CallableResult =
  | { readonly ok: true; readonly data: Readonly<Record<string, unknown>> }
  | { readonly ok: false; readonly status: string; readonly details?: unknown };

type Bucket = ReturnType<ReturnType<typeof getStorage>["bucket"]>;

/**
 * Creates a real Firebase Auth emulator user and signs in through the real
 * Auth emulator REST endpoint for a real ID token — the same token shape a
 * real client callable request carries, so the Functions emulator's own
 * `request.auth` population is exercised, not a hand-rolled stand-in.
 */
export async function createEmulatorActor(
  auth: Auth,
  actorUid: string,
  options: { readonly authEmulatorOrigin: string; readonly signInKey?: string },
): Promise<EmulatorActor> {
  const email = `${actorUid}@example.invalid`;
  const password = `${actorUid}-password`;
  await auth.createUser({ uid: actorUid, email, password, displayName: actorUid });
  const response = await fetch(
    `${options.authEmulatorOrigin}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${options.signInKey ?? "test-key"}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = asRecord(await response.json());
  assert.equal(response.ok, true);
  return { uid: actorUid, token: stringAt(body, "idToken") };
}

/**
 * Invokes a deployed v2 callable over HTTP through the Functions emulator —
 * the same wire shape a real client SDK call produces — so the test exercises
 * the actual exported Cloud Function (region, auth handling, error mapping)
 * rather than an in-process shortcut.
 */
export async function callEmulatorCallable(
  options: { readonly functionsOrigin: string; readonly projectId: string; readonly region: string },
  name: string,
  actor: EmulatorActor | undefined,
  data: Readonly<Record<string, unknown>>,
): Promise<CallableResult> {
  const response = await fetch(`${options.functionsOrigin}/${options.projectId}/${options.region}/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(actor === undefined ? {} : { authorization: `Bearer ${actor.token}` }),
    },
    body: JSON.stringify({ data }),
  });
  const body = asRecord(await response.json());
  if (response.ok) return { ok: true, data: asRecord(body["result"]) };
  const error = asRecord(body["error"]);
  return { ok: false, status: stringAt(error, "status"), details: error["details"] };
}

/** Stages a minimal, valid, real avatar PNG object at `path` in a real Storage bucket. */
export async function stageAvatarPngObject(bucket: Bucket, path: string, ownerUid: string): Promise<void> {
  await bucket.file(path).save(pngBytes(256, 256), {
    resumable: false,
    metadata: { contentType: "image/png", metadata: { ownerUid } },
  });
}

export function objectPathFromEmulatorUrl(url: string): string {
  const match = /\/o\/([^?]+)\?/.exec(url);
  assert.ok(match, `expected an emulator object URL, got: ${url}`);
  const encoded = match?.[1];
  assert.ok(encoded !== undefined);
  return decodeURIComponent(encoded);
}

export function tokenFromEmulatorUrl(url: string): string {
  const parsed = new URL(url);
  const token = parsed.searchParams.get("token");
  assert.ok(token !== null);
  return token;
}

export function asRecord(value: unknown): Readonly<Record<string, unknown>> {
  if (!isRecord(value)) assert.fail("Expected a JSON object.");
  return value;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function stringAt(value: Readonly<Record<string, unknown>>, key: string): string {
  const result = value[key];
  if (typeof result !== "string") assert.fail(`${key} must be a string.`);
  return result;
}

/** Minimal, real, valid PNG bytes — small enough for a fast test fixture, real enough for validateAvatarPng to accept. */
export function pngBytes(width: number, height: number): Uint8Array {
  return Uint8Array.from([
    137, 80, 78, 71, 13, 10, 26, 10,
    ...chunk("IHDR", [...uint32(width), ...uint32(height), 8, 6, 0, 0, 0]),
    ...chunk("IDAT", [0]),
    ...chunk("IEND", []),
  ]);
}

function chunk(type: string, data: readonly number[]): number[] {
  const typeBytes = [...type].map((character) => character.charCodeAt(0));
  return [...uint32(data.length), ...typeBytes, ...data, ...uint32(crc32([...typeBytes, ...data]))];
}

function uint32(value: number): number[] {
  return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255];
}

function crc32(bytes: readonly number[]): number {
  let crc = 0xffff_ffff;
  for (const value of bytes) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1;
  }
  return (crc ^ 0xffff_ffff) >>> 0;
}
