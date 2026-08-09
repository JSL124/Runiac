import { type Firestore } from "firebase-admin/firestore";
import type { Severity } from "./sanitize.js";

/**
 * Shared errorGroups/{fingerprint} ingest transaction, lifted out of
 * reportAppError.ts's port so both the mobile-facing reportAppError callable
 * and the backend reportBackendError reporter upsert, increment, and
 * preserve triage state identically. No Firebase imports beyond the
 * Firestore type: the transaction itself is the only Firebase-touching code
 * here.
 */

export type ErrorGroupStatus = "new" | "investigating" | "resolved" | "ignored";

/** Shape of an existing errorGroups/{fp} document as read inside the ingest transaction. */
export type ExistingErrorGroup = {
  readonly firstSeenAt: unknown;
  readonly status: ErrorGroupStatus;
  readonly note: string;
  readonly occurrences: number;
  readonly affectedUserCount: number;
};

/** The full document written to errorGroups/{fp} on every ingest. */
export type ErrorGroupDocument = {
  readonly title: string;
  readonly errorType: string;
  readonly screen: string;
  readonly appVersion: string;
  readonly os: string;
  readonly platform: string;
  readonly source: "mobile" | "functions";
  readonly occurrences: number;
  readonly affectedUserCount: number;
  readonly severity: Severity;
  readonly status: ErrorGroupStatus;
  readonly firstSeenAt: unknown;
  readonly lastSeenAt: unknown;
  readonly updatedAt: unknown;
  readonly stackSummary: string;
  readonly sanitized: true;
  readonly note: string;
};

export type IngestErrorGroupInput = {
  readonly fingerprint: string;
  /** Present for callables (uid known); absent for scheduled jobs and Firestore triggers. */
  readonly uid?: string;
  readonly buildDocument: (
    existing: ExistingErrorGroup | undefined,
    isNewReporter: boolean,
  ) => ErrorGroupDocument;
};

export type ErrorGroupStore = {
  readonly ingestErrorGroup: (input: IngestErrorGroupInput) => Promise<void>;
};

export function firestoreErrorGroupStore(firestore: Firestore): ErrorGroupStore {
  return {
    ingestErrorGroup: async ({ fingerprint, uid, buildDocument }) => {
      await firestore.runTransaction(async (transaction) => {
        const groupRef = firestore.collection("errorGroups").doc(fingerprint);
        const reporterRef = uid === undefined ? undefined : groupRef.collection("reporters").doc(uid);
        const [groupSnapshot, reporterSnapshot] = await Promise.all([
          transaction.get(groupRef),
          reporterRef === undefined ? Promise.resolve(undefined) : transaction.get(reporterRef),
        ]);
        const existing = groupSnapshot.exists
          ? (groupSnapshot.data() as ExistingErrorGroup)
          : undefined;
        const isNewReporter = reporterRef !== undefined && reporterSnapshot?.exists !== true;
        const document = buildDocument(existing, isNewReporter);
        transaction.set(groupRef, document);
        if (isNewReporter && reporterRef !== undefined) {
          transaction.set(reporterRef, {});
        }
      });
    },
  };
}
