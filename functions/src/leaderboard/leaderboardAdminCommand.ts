import { getApps, initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import { onDocumentCreated, type FirestoreEvent, type QueryDocumentSnapshot } from "firebase-functions/v2/firestore";
import {
  currentSingaporeMonthKey,
  refreshMonthlyLeaderboardSnapshots,
} from "./monthlyLeaderboard.js";
import { withTriggerErrorReporting } from "../errors/withErrorReporting.js";
import { avatarUrlContextFromEnvironment } from "../profile/avatar/context.js";

// The admin console (Next.js server, Admin SDK only) cannot invoke Cloud
// Functions callables directly, so "request a recalculation" has to be a
// Firestore write + trigger handoff instead of a callable: the console
// creates a `leaderboardAdminCommands/{commandId}` document, this trigger
// consumes it and runs the real aggregation, then merge-writes the outcome
// back onto the SAME document. `onDocumentCreated` fires only on create, so
// that write-back does not re-trigger this function.
//
// SAFETY: admin recalculation is deliberately restricted to the CURRENT
// Singapore month, and the period is derived here rather than trusted from
// the command document. `refreshMonthlyLeaderboardSnapshots` is not a
// period-scoped operation: it repoints `leaderboardPeriods/monthly_current`
// to whatever key it is given and then runs
// `cleanupExpiredProjections(retainedPeriodKeys(key))`, which deletes every
// snapshot/rank outside the three-month window around that key. So a command
// naming an older month (`2026-05` while July is live) would repoint the
// document the app reads first AND delete the live July/June projections,
// and a syntactically-valid-but-impossible month (`2026-13`, which
// `retainedPeriodKeys` cannot parse and degrades to a single-key retention
// set) would delete essentially everything. The scheduled job never had this
// exposure because it always passes the current month; this trigger is the
// only path that accepts external input, so it must fail closed.
const leaderboardAdminCommandsCollection = "leaderboardAdminCommands";

export type LeaderboardAdminCommandHandlers = {
  readonly onCommandCreated: (
    commandId: string,
    data: DocumentData,
  ) => Promise<void>;
};

export function createLeaderboardAdminCommandHandlers(dependencies: {
  readonly firestore: Firestore;
}): LeaderboardAdminCommandHandlers {
  return {
    onCommandCreated: async (commandId, data) => {
      const ref = dependencies.firestore
        .collection(leaderboardAdminCommandsCollection)
        .doc(commandId);
      const command = readString(data["command"]);
      const requestedPeriodKey = readString(data["periodKey"]);
      // Derived, never taken from the document — see the SAFETY note above.
      const periodKey = currentSingaporeMonthKey(new Date());

      if (command !== "refresh" || requestedPeriodKey !== periodKey) {
        // Invalid input is a business denial, not an infrastructure fault:
        // merge-write a rejection and return without throwing.
        //
        // A requested key that is merely stale rather than malicious is
        // possible if the console computed it just before a month rollover;
        // rejecting is still correct, and the admin simply retries.
        await ref.set(
          {
            status: "rejected",
            error: rejectionReason(command, requestedPeriodKey, periodKey),
            completedAt: new Date().toISOString(),
          },
          { merge: true },
        );
        return;
      }

      try {
        // Reused as-is: this already claims the
        // leaderboardAggregationLocks/monthly_{periodKey} lease, so locking is
        // not reimplemented here.
        const result = await refreshMonthlyLeaderboardSnapshots(
          dependencies.firestore,
          periodKey,
          {},
          avatarUrlContextFromEnvironment(),
        );
        await ref.set(
          {
            status: result.status,
            buildId: result.buildId,
            snapshotCount: result.snapshotCount,
            rankCount: result.rankCount,
            currentViewCount: result.currentViewCount,
            completedAt: new Date().toISOString(),
          },
          { merge: true },
        );
      } catch (error) {
        await ref.set(
          {
            status: "failed",
            error: error instanceof Error ? error.message : String(error),
            completedAt: new Date().toISOString(),
          },
          { merge: true },
        );
        // Rethrow so the fault surfaces in Cloud Logging.
        throw error;
      }
    },
  };
}

export function createLeaderboardAdminCommandTriggers(dependencies: {
  readonly firestore: Firestore;
}) {
  const handlers = createLeaderboardAdminCommandHandlers(dependencies);
  return {
    leaderboardAdminCommandCreated: onDocumentCreated(
      {
        document: `${leaderboardAdminCommandsCollection}/{commandId}`,
        region: "asia-southeast1",
      },
      withTriggerErrorReporting(
        "leaderboardAdminCommandCreated",
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

const productionLeaderboardAdminCommandTriggers =
  createLeaderboardAdminCommandTriggers({
    firestore: getFirestore(),
  });

export const leaderboardAdminCommandCreated =
  productionLeaderboardAdminCommandTriggers.leaderboardAdminCommandCreated;

function rejectionReason(
  command: string | null,
  requestedPeriodKey: string | null,
  currentPeriodKey: string,
): string {
  if (command !== "refresh") {
    return `Unsupported command: ${String(command)}`;
  }
  return `Only the current period can be recalculated. Requested ${String(requestedPeriodKey)}, current is ${currentPeriodKey}.`;
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}
