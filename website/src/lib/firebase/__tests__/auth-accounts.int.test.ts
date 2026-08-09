// Auth-emulator integration tests for website account creation and password
// reset. Unlike session.accounts.test.ts (which stubs fetch and only pins the
// request shape), this file drives the real Identity Toolkit endpoints on the
// emulator, proving the endpoints exist, accept these payloads, and behave the
// way the sign-up and reset flows assume.
//
// Skips itself entirely when no Auth emulator is configured, so
// `npm run test:integration` never talks to a live project.

import { randomUUID } from "node:crypto";

import { describe, expect, it } from "vitest";

import {
  sendPasswordResetEmail,
  signInWithPassword,
  signUpWithPassword,
} from "@/lib/firebase/session";

function authEmulatorAvailable(): boolean {
  return Boolean(
    process.env.FIREBASE_AUTH_EMULATOR_HOST &&
      process.env.FIRESTORE_EMULATOR_HOST,
  );
}

function uniqueEmail(): string {
  return `website-signup-${randomUUID()}@runiac.test`;
}

describe.skipIf(!authEmulatorAvailable())(
  "website account creation — Auth emulator integration",
  () => {
    it("creates an account that can then sign in with the same credentials", async () => {
      // The whole point of website sign-up: the runner signs in *in the app*
      // with what they typed here.
      const email = uniqueEmail();

      const created = await signUpWithPassword(email, "password123");

      expect(created.ok).toBe(true);

      const signedIn = await signInWithPassword(email, "password123");

      expect(signedIn.ok).toBe(true);
      expect(signedIn.ok === true && signedIn.uid).toBe(
        created.ok === true ? created.uid : null,
      );
    });

    it("rejects a second account for the same email", async () => {
      const email = uniqueEmail();

      await signUpWithPassword(email, "password123");
      const duplicate = await signUpWithPassword(email, "password456");

      expect(duplicate.ok).toBe(false);
      expect(duplicate.ok === false && duplicate.kind).toBe("email-exists");
    });

    it("rejects a password the emulator considers too weak", async () => {
      const weak = await signUpWithPassword(uniqueEmail(), "abc");

      expect(weak.ok).toBe(false);
      expect(weak.ok === false && weak.kind).toBe("weak-password");
    });

    it("accepts a reset request for a real account", async () => {
      const email = uniqueEmail();
      await signUpWithPassword(email, "password123");

      await expect(sendPasswordResetEmail(email)).resolves.toEqual({
        ok: true,
      });
    });

    it("reports the same result for an email with no account", async () => {
      await expect(sendPasswordResetEmail(uniqueEmail())).resolves.toEqual({
        ok: true,
      });
    });
  },
);
