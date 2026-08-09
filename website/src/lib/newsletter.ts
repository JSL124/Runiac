"use client";

// Thin client wrapper around the `subscribeNewsletter` Cloud Functions
// callable (asia-southeast1), built on the shared browser Firebase app in
// ./firebase/client.ts — mirrors that file's "one job" scoping: this module
// only calls the callable and shapes its result, it never touches Firestore
// directly and is never a source of truth for subscription state.
//
// Backend contract (subscribeNewsletter, unauthenticated allowed):
//   request  { email: string, website?: string }  // `website` is a honeypot
//   response { status: "pending" | "already-subscribed" }
//   errors   "invalid-argument" (bad email), "resource-exhausted" (rate
//            limited, 5/hour/IP), anything else generic.
// FirebaseError codes surfaced to the client are prefixed with the service
// name (mirroring the "auth/..." codes already handled in ./firebase/client.ts),
// i.e. "functions/invalid-argument" / "functions/resource-exhausted".

import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
  type HttpsCallableResult,
} from "firebase/functions";
import { getClientApp } from "./firebase/client";
import { getFunctionsEmulatorHost } from "./firebase/config";

const NEWSLETTER_FUNCTIONS_REGION = "asia-southeast1";

// connectFunctionsEmulator() throws if called twice on the same Functions
// instance, which a React Fast Refresh / hot reload in dev would otherwise
// trigger on every edit. Module-level guard, mirroring the singleton pattern
// already used for the Firebase app itself in ./firebase/client.ts.
let emulatorConnected = false;

function getNewsletterFunctions() {
  const functions = getFunctions(getClientApp(), NEWSLETTER_FUNCTIONS_REGION);
  const emulatorHost = getFunctionsEmulatorHost();

  if (emulatorHost && !emulatorConnected) {
    const [host, portRaw] = emulatorHost.split(":");
    const port = Number(portRaw);

    if (host && Number.isFinite(port)) {
      connectFunctionsEmulator(functions, host, port);
      emulatorConnected = true;
    }
  }

  return functions;
}

export type NewsletterSubscribeStatus = "pending" | "already-subscribed";

export type NewsletterSubscribeResult =
  | { ok: true; status: NewsletterSubscribeStatus }
  | { ok: false; reason: "invalid-email" | "rate-limited" | "error" };

type SubscribeNewsletterRequest = { email: string; website?: string };
type SubscribeNewsletterResponse = { status: NewsletterSubscribeStatus };

function getSubscribeNewsletterCallable() {
  const functions = getNewsletterFunctions();
  return httpsCallable<SubscribeNewsletterRequest, SubscribeNewsletterResponse>(
    functions,
    "subscribeNewsletter",
  );
}

// `website` is the honeypot field: pass it only when the hidden input was
// actually filled in (a bot did it) — the caller must omit it, or pass an
// empty string, otherwise. Never sent as a required field.
export async function subscribeToNewsletter(
  email: string,
  website?: string,
): Promise<NewsletterSubscribeResult> {
  const trimmedEmail = email.trim();
  const request: SubscribeNewsletterRequest =
    website && website.length > 0
      ? { email: trimmedEmail, website }
      : { email: trimmedEmail };

  let result: HttpsCallableResult<SubscribeNewsletterResponse>;

  try {
    result = await getSubscribeNewsletterCallable()(request);
  } catch (error) {
    const code = (error as { code?: string } | null)?.code;

    if (code === "functions/invalid-argument") {
      return { ok: false, reason: "invalid-email" };
    }

    if (code === "functions/resource-exhausted") {
      return { ok: false, reason: "rate-limited" };
    }

    return { ok: false, reason: "error" };
  }

  return { ok: true, status: result.data.status };
}
