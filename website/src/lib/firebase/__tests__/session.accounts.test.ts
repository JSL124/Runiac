// Unit tests for the Identity Toolkit calls behind website account creation
// and password reset. `fetch` is stubbed, so what this file pins down is the
// wire contract: which REST method each helper hits, in emulator mode and in
// live mode, and how Firebase's error codes are mapped.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  sendPasswordResetEmail,
  signUpWithPassword,
} from "@/lib/firebase/session";

const originalEnv = { ...process.env };

function stubFetch(response: {
  ok: boolean;
  body: Record<string, unknown>;
}) {
  const fetchMock = vi.fn(async () => ({
    ok: response.ok,
    json: async () => response.body,
  }));

  vi.stubGlobal("fetch", fetchMock);

  return fetchMock;
}

function requestFor(fetchMock: ReturnType<typeof stubFetch>) {
  const [url, init] = fetchMock.mock.calls[0] as unknown as [
    string,
    { body: string },
  ];

  return { url, body: JSON.parse(init.body) as Record<string, unknown> };
}

beforeEach(() => {
  delete process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
  process.env.NEXT_PUBLIC_FIREBASE_API_KEY = "test-web-api-key";
});

afterEach(() => {
  vi.unstubAllGlobals();
  process.env = { ...originalEnv };
});

describe("signUpWithPassword", () => {
  it("posts to accounts:signUp with the live web API key", async () => {
    const fetchMock = stubFetch({
      ok: true,
      body: {
        idToken: "id-token",
        localId: "new-uid",
        email: "runner@runiac.app",
      },
    });

    const result = await signUpWithPassword("runner@runiac.app", "password123");

    const { url, body } = requestFor(fetchMock);
    expect(url).toBe(
      "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=test-web-api-key",
    );
    expect(body).toEqual({
      email: "runner@runiac.app",
      password: "password123",
      returnSecureToken: true,
    });
    expect(result).toEqual({
      ok: true,
      idToken: "id-token",
      uid: "new-uid",
      email: "runner@runiac.app",
    });
  });

  it("routes through the Auth emulator when one is configured", async () => {
    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
    process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
    const fetchMock = stubFetch({
      ok: true,
      body: { idToken: "id-token", localId: "new-uid" },
    });

    await signUpWithPassword("runner@runiac.app", "password123");

    expect(requestFor(fetchMock).url).toBe(
      "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key",
    );
  });

  it("maps EMAIL_EXISTS to a sign-in suggestion", async () => {
    stubFetch({ ok: false, body: { error: { message: "EMAIL_EXISTS" } } });

    const result = await signUpWithPassword("runner@runiac.app", "password123");

    expect(result.ok).toBe(false);
    expect(result.ok === false && result.kind).toBe("email-exists");
  });

  it("maps a weak password to its own kind", async () => {
    stubFetch({
      ok: false,
      body: { error: { message: "WEAK_PASSWORD : Password should be..." } },
    });

    const result = await signUpWithPassword("runner@runiac.app", "short");

    expect(result.ok === false && result.kind).toBe("weak-password");
  });

  it("reports a config failure when no API key or emulator is set", async () => {
    delete process.env.NEXT_PUBLIC_FIREBASE_API_KEY;
    const fetchMock = stubFetch({ ok: true, body: {} });

    const result = await signUpWithPassword("runner@runiac.app", "password123");

    expect(result.ok === false && result.kind).toBe("config");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("sendPasswordResetEmail", () => {
  it("posts a PASSWORD_RESET oob code request", async () => {
    const fetchMock = stubFetch({ ok: true, body: {} });

    const result = await sendPasswordResetEmail("runner@runiac.app");

    const { url, body } = requestFor(fetchMock);
    expect(url).toBe(
      "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=test-web-api-key",
    );
    expect(body).toEqual({
      requestType: "PASSWORD_RESET",
      email: "runner@runiac.app",
    });
    expect(result).toEqual({ ok: true });
  });

  it("treats an unknown email as success so accounts cannot be enumerated", async () => {
    stubFetch({ ok: false, body: { error: { message: "EMAIL_NOT_FOUND" } } });

    const result = await sendPasswordResetEmail("stranger@example.com");

    expect(result).toEqual({ ok: true });
  });

  it("reports other failures rather than claiming the mail was sent", async () => {
    stubFetch({
      ok: false,
      body: { error: { message: "TOO_MANY_ATTEMPTS_TRY_LATER" } },
    });

    const result = await sendPasswordResetEmail("runner@runiac.app");

    expect(result.ok).toBe(false);
  });
});
