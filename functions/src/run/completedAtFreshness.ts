import { HttpsError } from "firebase-functions/v2/https";

/**
 * How far ahead of server time a client-supplied `completedAt` may sit.
 *
 * `dailyCapDate` and `monthlyPeriod` are both derived from the client's
 * `completedAt`, and nothing bounded it against server time — so a caller
 * could name any instant and choose which day's 200 XP cap and which month's
 * leaderboard period their run landed in. Future-dating is the half of that
 * which is never legitimate: a run cannot finish after now. Rejecting it
 * closes "bank XP into next month's board" and "spend a day's cap that has
 * not happened yet" without touching the offline re-upload path, where a
 * genuine `completedAt` is always in the past.
 *
 * The six-hour allowance is not clock jitter — it is wide enough to absorb a
 * device whose timezone is misconfigured by several hours, because a rejected
 * run is a run the runner loses (the pending-run store retries the same
 * payload and would fail forever). Backdating past runs is deliberately still
 * accepted here; bounding that direction needs a policy that cannot strand
 * legitimate offline uploads, and is recorded as separate open work.
 */
export const maxCompletedAtFutureSkewMs = 6 * 60 * 60 * 1000;

/**
 * The instant the progression period keys must be derived from.
 *
 * Accepting a `completedAt` up to six hours ahead keeps a runner with a
 * misconfigured device clock from losing their run — but an accepted future
 * instant must not also get to CHOOSE the accounting period, or the allowance
 * becomes its own exploit: a run submitted near midnight Singapore time could
 * name tomorrow and spend a daily cap that has not opened yet, and one near a
 * month boundary could bank XP into next month's leaderboard. Clamping to
 * server time keeps the activity's own `completedAt` intact for display and
 * history while the cap date and leaderboard period stay on a clock the client
 * does not control.
 *
 * A past `completedAt` passes through unchanged: an offline re-upload must
 * still land in the period it was actually run in.
 */
export function progressionInstantFor(
  completedAt: string,
  nowMs: number = Date.now(),
): string {
  const completedAtMs = Date.parse(completedAt);
  if (Number.isNaN(completedAtMs) || completedAtMs <= nowMs) {
    return completedAt;
  }
  return new Date(nowMs).toISOString();
}

export function assertCompletedAtNotInFuture(
  completedAt: string,
  nowMs: number = Date.now(),
): void {
  if (Date.parse(completedAt) - nowMs > maxCompletedAtFutureSkewMs) {
    throw new HttpsError(
      "invalid-argument",
      "completedAt must not be in the future.",
    );
  }
}
