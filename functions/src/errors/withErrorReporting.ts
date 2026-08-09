import { HttpsError } from "firebase-functions/v2/https";
import { reportBackendError } from "./reportBackendError.js";

/**
 * Three thin wrappers — callable, scheduled, trigger — sharing one
 * classification and reporting core. Each wraps a handler so an unexpected
 * fault is reported to errorGroups (source: "functions") and the original
 * error is ALWAYS rethrown unchanged: callable responses, Cloud Logging, and
 * trigger retry semantics are all unaffected.
 *
 * Classification: expected rejections are not errors. HttpsError is how
 * callables signal business-rule denials (invalid-argument,
 * resource-exhausted, unauthenticated, ...) by design, and reporting those
 * would flood the console with users mistyping things. Only a non-HttpsError
 * throw, or an HttpsError carrying "internal"/"unknown", is reported.
 *
 * reportAppError itself must never be wrapped with these — reporting its own
 * failure through itself would recurse.
 */

function isReportableError(error: unknown): boolean {
  if (error instanceof HttpsError) {
    return error.code === "internal" || error.code === "unknown";
  }
  return true;
}

async function reportIfReportable(
  functionName: string,
  error: unknown,
  uid: string | undefined,
): Promise<void> {
  if (!isReportableError(error)) {
    return;
  }
  await reportBackendError({
    functionName,
    error,
    fatal: true,
    ...(uid === undefined ? {} : { uid }),
  });
}

type CallableLikeRequest = {
  readonly auth?: { readonly uid: string };
};

/**
 * Wraps a callable's request handler. The `onCall` options object
 * (region, enforceAppCheck, secrets, ...) is untouched by this — it wraps
 * only the handler function passed alongside it.
 */
export function withCallableErrorReporting<TRequest extends CallableLikeRequest, TResult>(
  functionName: string,
  handler: (request: TRequest) => Promise<TResult>,
): (request: TRequest) => Promise<TResult> {
  return async (request: TRequest): Promise<TResult> => {
    try {
      return await handler(request);
    } catch (error) {
      // Defence in depth: reportIfReportable/reportBackendError already
      // promise never to throw, but no future change to either should ever
      // be able to alter what THIS wrapper throws. The original error must
      // escape unconditionally, no matter what the reporter does.
      try {
        await reportIfReportable(functionName, error, request.auth?.uid);
      } catch {
        // Swallowed: see above.
      }
      throw error;
    }
  };
}

/**
 * Wraps a scheduled job's handler. Scheduled jobs have no calling user, so
 * `affectedUserCount` stays 0 and no `reporters/{uid}` marker is written —
 * never invent a synthetic user.
 */
export function withScheduledErrorReporting<TEvent>(
  functionName: string,
  handler: (event: TEvent) => Promise<void>,
): (event: TEvent) => Promise<void> {
  return async (event: TEvent): Promise<void> => {
    try {
      await handler(event);
    } catch (error) {
      // Defence in depth: see withCallableErrorReporting above.
      try {
        await reportIfReportable(functionName, error, undefined);
      } catch {
        // Swallowed: the original error must escape unconditionally.
      }
      throw error;
    }
  };
}

/**
 * Wraps a Firestore trigger's handler. Like scheduled jobs, triggers have no
 * calling user, so `affectedUserCount` stays 0 and no reporter marker is
 * written.
 */
export function withTriggerErrorReporting<TEvent>(
  functionName: string,
  handler: (event: TEvent) => Promise<void>,
): (event: TEvent) => Promise<void> {
  return async (event: TEvent): Promise<void> => {
    try {
      await handler(event);
    } catch (error) {
      // Defence in depth: see withCallableErrorReporting above.
      try {
        await reportIfReportable(functionName, error, undefined);
      } catch {
        // Swallowed: the original error must escape unconditionally.
      }
      throw error;
    }
  };
}
