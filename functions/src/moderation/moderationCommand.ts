import { getApps, initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import { onDocumentCreated, type FirestoreEvent, type QueryDocumentSnapshot } from "firebase-functions/v2/firestore";
import { beginFeedPostCleanup } from "../feed/lifecycle/core.js";
import { cleanupFeedPost } from "../feed/cleanup.js";
import { firebaseLifecyclePort } from "../feed/lifecycle/firebasePort.js";
import type { DeleteFeedPostResult, FeedLifecyclePort } from "../feed/lifecycle/types.js";
import { withTriggerErrorReporting } from "../errors/withErrorReporting.js";

// The admin console (Next.js server, Admin SDK only) cannot invoke Cloud
// Functions callables directly, so content-moderation actions have to be a
// Firestore write + trigger handoff instead of a callable — the same pattern
// `leaderboardAdminCommand.ts` already uses: the console creates a
// `moderationCommands/{commandId}` document, this trigger consumes it and
// runs the real removal, then merge-writes the outcome back onto the SAME
// document. `onDocumentCreated` fires only on create, so that write-back does
// not re-trigger this function.
//
// Exactly one command kind is supported: "removeFeedPost". "restoreFeedPost"
// is explicitly out of scope for this capsule.
//
// SAFETY: the only trust-bearing input this trigger accepts from the command
// document is `postId`, and it is validated with the same identifier guard
// `functions/src/feed/lifecycle/core.ts` uses for every other feed-lifecycle
// entry point (`^[A-Za-z0-9_-]{1,128}$`) before anything is read or written.
// Nothing else on the document — not `requestedBy`, not any other
// caller-supplied field — is trusted or derived from.
//
// This deliberately does NOT call `deleteFeedPostCore` from core.ts: that
// function's own guard clause requires `ownerUid` to already be a valid
// identifier, so passing `ownerUid: undefined` for an admin override would be
// rejected before ever reaching `beginFeedPostCleanup`. The admin-override
// path — skip the ownership check because `ownerUid` is `undefined` — lives
// one layer down, in `beginFeedPostCleanup` itself, and is already exercised
// by `cleanupFromActivityDeletion` for the activity-deletion system path.
// This module follows that same lower-level composition
// (`beginFeedPostCleanup` + `cleanupFeedPost`) rather than the
// owner-authenticated `deleteFeedPostCore` wrapper.
const moderationCommandsCollection = "moderationCommands";

export type ModerationCommandHandlers = {
  readonly onCommandCreated: (
    commandId: string,
    data: DocumentData,
  ) => Promise<void>;
};

type ModerationRemovalOutcome = {
  readonly result: DeleteFeedPostResult;
  // Only populated when a post was actually removed by THIS call, so a later
  // wave can offer "suspend the reported author" without a second read.
  // `reports/{reportId}` never stores the author uid (only
  // reporterUid/targetType/targetId), so once the post is gone the author is
  // otherwise unrecoverable from that path.
  readonly removedAuthorUid: string | null;
};

export function createModerationCommandHandlers(dependencies: {
  readonly firestore: Firestore;
}): ModerationCommandHandlers {
  return {
    onCommandCreated: async (commandId, data) => {
      const ref = dependencies.firestore
        .collection(moderationCommandsCollection)
        .doc(commandId);

      // Idempotent on replay: re-read the CURRENT persisted state rather
      // than trusting the create-time `data` payload, so a redelivered
      // trigger (or a manually replayed call) never reprocesses a command
      // that already reached a terminal state.
      const existing = await ref.get();
      const existingStatus = readString(existing.data()?.["status"]);
      if (existingStatus === "completed" || existingStatus === "failed") {
        return;
      }

      const kind = readString(data["kind"]);
      if (kind !== "removeFeedPost") {
        await writeFailure(ref, `Unsupported command kind: ${String(kind)}`);
        return;
      }

      const postId = readString(data["postId"]);
      if (postId === null || !isIdentifier(postId)) {
        await writeFailure(ref, "postId must be a valid identifier.");
        return;
      }

      try {
        const outcome = await removeFeedPostForModeration(
          firebaseLifecyclePort(dependencies.firestore),
          postId,
        );
        const outcomeStatus = statusForResult(outcome.result);
        await ref.set(
          {
            status: outcomeStatus.status,
            ...(outcomeStatus.error === undefined ? {} : { error: outcomeStatus.error }),
            ...(outcome.removedAuthorUid === null
              ? {}
              : { removedAuthorUid: outcome.removedAuthorUid }),
            completedAt: new Date().toISOString(),
          },
          { merge: true },
        );
      } catch (error) {
        await writeFailure(ref, error instanceof Error ? error.message : String(error));
        // Rethrow so the fault surfaces in Cloud Logging.
        throw error;
      }
    },
  };
}

export function createModerationCommandTriggers(dependencies: {
  readonly firestore: Firestore;
}) {
  const handlers = createModerationCommandHandlers(dependencies);
  return {
    moderationCommandCreated: onDocumentCreated(
      {
        document: `${moderationCommandsCollection}/{commandId}`,
        region: "asia-southeast1",
      },
      withTriggerErrorReporting(
        "moderationCommandCreated",
        async (
          event: FirestoreEvent<QueryDocumentSnapshot | undefined, { commandId: string }>,
        ) => {
          const data = event.data?.data();
          if (data === undefined) {
            return;
          }
          await handlers.onCommandCreated(event.params.commandId, data);
        },
      ),
    ),
  };
}

if (getApps().length === 0) {
  initializeApp();
}

const productionModerationCommandTriggers = createModerationCommandTriggers({
  firestore: getFirestore(),
});

export const moderationCommandCreated =
  productionModerationCommandTriggers.moderationCommandCreated;

async function removeFeedPostForModeration(
  port: FeedLifecyclePort,
  postId: string,
): Promise<ModerationRemovalOutcome> {
  // ownerUid intentionally omitted: beginFeedPostCleanup treats an undefined
  // ownerUid as the admin-override path and skips the ownership check.
  const beginning = await beginFeedPostCleanup({ port, postId });
  switch (beginning.kind) {
    case "denied":
      return { result: beginning, removedAuthorUid: null };
    case "already_missing":
      return { result: beginning, removedAuthorUid: null };
    case "ready": {
      const authorUid = beginning.post.authorUid;
      const cleanup = await cleanupFeedPost(port, beginning.post);
      return {
        result: { kind: "cleanup", cleanup },
        removedAuthorUid: cleanup.kind === "completed" ? authorUid : null,
      };
    }
    default:
      return assertNever(beginning);
  }
}

function statusForResult(
  result: DeleteFeedPostResult,
): { readonly status: "completed" | "failed"; readonly error?: string } {
  switch (result.kind) {
    case "already_missing":
      return { status: "completed" };
    case "denied":
      return { status: "failed", error: "Feed post removal was denied." };
    case "cleanup":
      switch (result.cleanup.kind) {
        case "completed":
        case "already_missing":
          return { status: "completed" };
        case "retry_required":
          // The post is already marked "deleting" but cleanup did not
          // converge. Surfacing this as failed (rather than completed) lets
          // the admin retry with a new command instead of believing the post
          // is fully gone.
          return {
            status: "failed",
            error: `Cleanup requires retry at step: ${result.cleanup.failedStep}`,
          };
        default:
          return assertNever(result.cleanup);
      }
    default:
      return assertNever(result);
  }
}

async function writeFailure(
  ref: FirebaseFirestore.DocumentReference,
  error: string,
): Promise<void> {
  await ref.set(
    {
      status: "failed",
      error,
      completedAt: new Date().toISOString(),
    },
    { merge: true },
  );
}

function isIdentifier(value: string | undefined): value is string {
  return value !== undefined && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function assertNever(value: never): never {
  throw new TypeError(`Unexpected moderation result: ${JSON.stringify(value)}`);
}
