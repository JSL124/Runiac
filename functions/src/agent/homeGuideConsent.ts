import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { shouldEnforceAppCheck } from "../security/appCheck.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";

export const HOME_GUIDE_DISCLOSURE_VERSION = 1;
const HOME_GUIDE_CONSENT_SCHEMA_VERSION = 1;

type HomeGuideConsentRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

type HomeGuideConsentResult = {
  readonly granted: boolean;
  readonly disclosureVersion: number;
};

type HomeGuideConsentDependencies = {
  readonly firestore: () => Firestore;
  readonly now: () => Date;
};

export const homeGuideConsent = onCall(
  {
    region: "asia-southeast1",
    enforceAppCheck: shouldEnforceAppCheck(),
  },
  withCallableErrorReporting(
    "homeGuideConsent",
    createHomeGuideConsentHandler({
      firestore: getFirestore,
      now: () => new Date(),
    }),
  ),
);

export function createHomeGuideConsentHandler(
  dependencies: HomeGuideConsentDependencies,
): (request: HomeGuideConsentRequest) => Promise<HomeGuideConsentResult> {
  return async (request) => {
    const uid = authenticatedUid(request);
    const action = parseConsentAction(request.data);
    const firestore = dependencies.firestore();

    if (action.kind === "read") {
      return readHomeGuideConsent(firestore, uid);
    }

    const now = Timestamp.fromDate(dependencies.now());
    await firestore.collection("homeGuideConsents").doc(uid).set({
      ownerUid: uid,
      schemaVersion: HOME_GUIDE_CONSENT_SCHEMA_VERSION,
      disclosureVersion: HOME_GUIDE_DISCLOSURE_VERSION,
      granted: action.granted,
      updatedAt: now,
      grantedAt: action.granted ? now : null,
      revokedAt: action.granted ? null : now,
    });
    return consentResult(action.granted);
  };
}

export async function requireCurrentHomeGuideConsent(
  firestore: Firestore,
  uid: string,
): Promise<void> {
  const consent = await readHomeGuideConsent(firestore, uid);
  if (!consent.granted) {
    throw new HttpsError(
      "failed-precondition",
      "Current Home Guide data consent is required.",
    );
  }
}

async function readHomeGuideConsent(
  firestore: Firestore,
  uid: string,
): Promise<HomeGuideConsentResult> {
  const snapshot = await firestore.collection("homeGuideConsents").doc(uid).get();
  const granted =
    snapshot.exists &&
    snapshot.get("ownerUid") === uid &&
    snapshot.get("schemaVersion") === HOME_GUIDE_CONSENT_SCHEMA_VERSION &&
    snapshot.get("disclosureVersion") === HOME_GUIDE_DISCLOSURE_VERSION &&
    snapshot.get("granted") === true;
  return consentResult(granted);
}

function consentResult(granted: boolean): HomeGuideConsentResult {
  return {
    granted,
    disclosureVersion: HOME_GUIDE_DISCLOSURE_VERSION,
  };
}

function authenticatedUid(request: HomeGuideConsentRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication is required to manage Home Guide data consent.",
    );
  }
  return uid;
}

type ConsentAction =
  | { readonly kind: "read" }
  | { readonly kind: "update"; readonly granted: boolean };

function parseConsentAction(data: unknown): ConsentAction {
  if (!isRecord(data) || typeof data["action"] !== "string") {
    throw invalidConsentRequest();
  }
  if (data["action"] === "read" && Object.keys(data).length === 1) {
    return { kind: "read" };
  }
  if (
    data["action"] === "update" &&
    Object.keys(data).length === 3 &&
    typeof data["granted"] === "boolean" &&
    data["disclosureVersion"] === HOME_GUIDE_DISCLOSURE_VERSION
  ) {
    return { kind: "update", granted: data["granted"] };
  }
  throw invalidConsentRequest();
}

function invalidConsentRequest(): HttpsError {
  return new HttpsError(
    "invalid-argument",
    "A valid current-version Home Guide consent action is required.",
  );
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
