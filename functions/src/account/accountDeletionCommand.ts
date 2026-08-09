// Stages B and C of account deletion, driven by a Firestore trigger.
//
// Same handoff shape as `leaderboardAdminCommand.ts` and
// `moderationCommand.ts`: a client-denied command document is created, this
// trigger consumes it and does the real work, then merge-writes the outcome
// back onto the SAME document. `onDocumentCreated` fires only on create, so the
// write-back cannot re-trigger this function.
//
// The reason for the handoff differs from the other two, though. Those exist
// because the Admin-SDK admin console cannot invoke callables. This one exists
// because the work is unbounded: erasing an account touches every collection
// the runner ever wrote to, and a callable that times out mid-way would have
// already told the user their account was deleted.

import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type DocumentReference,
  type Firestore,
} from "firebase-admin/firestore";
import { getStorage, type Storage } from "firebase-admin/storage";
import {
  onDocumentCreated,
  type FirestoreEvent,
  type QueryDocumentSnapshot,
} from "firebase-functions/v2/firestore";

import { withTriggerErrorReporting } from "../errors/withErrorReporting.js";
import { runAccountDeletionFanOut } from "./accountDeletionCore.js";
import {
  ACCOUNT_DELETION_COMMANDS,
  TERMINAL_COMMAND_STATUSES,
  type AccountDeletionCommandStatus,
} from "./accountDeletionCommandTypes.js";

export type AccountDeletionCommandHandlers = {
  readonly onCommandCreated: (uid: string, data: DocumentData) => Promise<void>;
};

export type AccountDeletionCommandDependencies = {
  readonly firestore: Firestore;
  readonly storage: Storage;
  readonly auth: Auth;
  readonly now?: () => number;
};

export function createAccountDeletionCommandHandlers(
  dependencies: AccountDeletionCommandDependencies,
): AccountDeletionCommandHandlers {
  const { firestore } = dependencies;
  const now = dependencies.now ?? (() => Date.now());

  return {
    onCommandCreated: async (uid, data) => {
      const ref = firestore.collection(ACCOUNT_DELETION_COMMANDS).doc(uid);

      // Re-read the CURRENT persisted state rather than trusting the
      // create-time payload, so a redelivered trigger never reprocesses a
      // command that already reached a terminal state.
      const existing = await ref.get();
      const existingStatus = existing.get("status") as AccountDeletionCommandStatus | undefined;
      if (existingStatus !== undefined && TERMINAL_COMMAND_STATUSES.includes(existingStatus)) {
        return;
      }

      // Trust exactly one thing from the document: that its id is the uid to
      // erase. Nothing else on it is read as an instruction. `completedSteps`
      // is read as a resume cursor, and it can only ever cause work to be
      // SKIPPED that this same function previously recorded as done — and every
      // step is independently idempotent anyway, so a corrupted cursor costs a
      // redundant scan, never a missed erase.
      if (uid !== readString(data["uid"]) && readString(data["uid"]) !== null) {
        await writeFailure(ref, "Command id does not match its uid field.");
        return;
      }

      await ref.set({ status: "erasing", startedAt: new Date().toISOString() }, { merge: true });

      try {
        const result = await runAccountDeletionFanOut(dependencies, uid, now(), {
          completedSteps: readStringArray(existing.get("completedSteps")),
          onStepCompleted: async (outcome) => {
            await ref.set(
              {
                completedSteps: FieldValue.arrayUnion(outcome.stepId),
                ...(outcome.truncated
                  ? { truncatedSteps: FieldValue.arrayUnion(outcome.stepId) }
                  : {}),
              },
              { merge: true },
            );
          },
        });

        await ref.set(
          {
            status: "completed",
            completedAt: new Date().toISOString(),
            // Per-step counts, kept for operator confidence that the erase
            // actually reached each area rather than silently no-oping.
            stepCounts: Object.fromEntries(
              result.outcomes.map((step) => [step.stepId, step.deletedCount]),
            ),
          },
          { merge: true },
        );
      } catch (error) {
        await writeFailure(ref, error instanceof Error ? error.message : String(error));
        // Rethrow so the fault surfaces in Cloud Logging. The account stays
        // locked out either way: stage A already revoked its tokens and
        // disabled the Auth user, so a failed erase leaves an unusable account
        // with residual data, never a usable one.
        throw error;
      }
    },
  };
}

export function createAccountDeletionCommandTriggers(
  dependencies: AccountDeletionCommandDependencies,
) {
  const handlers = createAccountDeletionCommandHandlers(dependencies);
  return {
    accountDeletionCommandCreated: onDocumentCreated(
      {
        document: `${ACCOUNT_DELETION_COMMANDS}/{uid}`,
        region: "asia-southeast1",
      },
      withTriggerErrorReporting(
        "accountDeletionCommandCreated",
        async (event: FirestoreEvent<QueryDocumentSnapshot | undefined, { uid: string }>) => {
          const data = event.data?.data();
          if (data === undefined) return;
          await handlers.onCommandCreated(event.params.uid, data);
        },
      ),
    ),
  };
}

if (getApps().length === 0) {
  initializeApp();
}

const productionAccountDeletionTriggers = createAccountDeletionCommandTriggers({
  firestore: getFirestore(),
  storage: getStorage(),
  auth: getAuth(),
});

export const accountDeletionCommandCreated =
  productionAccountDeletionTriggers.accountDeletionCommandCreated;

async function writeFailure(ref: DocumentReference, error: string): Promise<void> {
  await ref.set(
    { status: "failed", error, completedAt: new Date().toISOString() },
    { merge: true },
  );
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function readStringArray(value: unknown): readonly string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}
