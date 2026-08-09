"use server";

// Server actions for the three key admin mutation flows: user role/status,
// plan publishing, and report resolution. Every action re-verifies the caller
// is an authenticated Platform Administrator (never trust the client), then:
//   * Firebase configured  -> perform the Firestore mutation (which also writes
//     the adminAuditLogs entry) and return { live: true } so the client can
//     router.refresh() to re-read server data.
//   * Firebase absent      -> return { live: false }; the client keeps its
//     local mock-state behavior so the demo UX is unchanged.

import { requireAdmin, type ActingAdmin } from "@/lib/actions/require-admin";
import {
  validateAutomationConfig,
  validateChallengeAccessConfig,
  validateCharacterAccessConfig,
  validateFeatureAccessConfig,
  validateLeaderboardConfig,
  validateProgressionConfig,
} from "@/lib/admin/config-validation";
import type {
  AutomationConfig,
  ChallengeAccessConfig,
  CharacterAccessConfig,
  FeatureAccessConfig,
  LeaderboardConfig,
  ProgressionConfig,
} from "@/lib/admin/config-validation";
import {
  mergePaywallConfig,
  validatePaywallConfig,
  type PaywallConfig,
} from "@/lib/admin/paywall-config";
import { validateSitePricing } from "@/lib/site-pricing";
import { validateSiteTestimonials } from "@/lib/site-testimonials";
import { validateSiteTeam } from "@/lib/site-team";
import { validateSiteDocuments } from "@/lib/site-documents";
import { validateSiteDownload } from "@/lib/site-download";
import { validateSiteProblem } from "@/lib/site-problem";
import { validateSiteSolution } from "@/lib/site-solution";
import { validateSitePersonalizedPlan } from "@/lib/site-personalized-plan";
import {
  validateSiteJourneyMap,
  validateSiteXpProgression,
  validateSiteTerritorial,
  validateSitePostRunSummary,
} from "@/lib/site-highlight";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import {
  clearUserAvatar as clearUserAvatarInDb,
  createLeaderboardReport,
  currentSingaporeMonthKey,
  dismissAdminNotification,
  getConfigDoc,
  getConfigHistoryEntry,
  getLeaderboardCommand,
  getLeaderboardSnapshotById,
  getModerationCommand,
  getUserProgression,
  requestLeaderboardRecalculation as requestLeaderboardRecalculationInDb,
  requestModerationCommand,
  setConfigDoc,
  setErrorGroupTriage,
  setFeedbackClosed,
  setFeedbackTriage,
  setReportResolution,
  setUserAccountStatus as setUserAccountStatusInDb,
  setUserModeration as setUserModerationInDb,
  setUserProgression,
  setUserRole as setUserRoleInDb,
  setUserSubscription as setUserSubscriptionInDb,
} from "@/lib/firebase/firestore";
import type { UserModerationAction, UserSubscriptionStatus } from "@/lib/firebase/firestore";
import type {
  LeaderboardCommandRow,
  LeaderboardSnapshotRow,
  ModerationCommandRow,
} from "@/lib/firebase/types";
import { getAdminDb } from "@/lib/firebase/admin";
import type {
  AccountStatus,
  ErrorStatus,
  FeedbackStatus,
  ReportResolutionStatus,
  UserRole,
  WebsiteContent,
} from "@/lib/admin/types";
import {
  levelForTotalXp,
  xpForLevel,
  type UserProgressionFields,
} from "@/lib/admin/progression-curve";
import {
  DEFAULT_PROGRESSION_CONFIG,
  deepMerge,
} from "@/lib/admin/config-validation";
import { getLiveProgressionConfig } from "@/lib/admin/live-data";

export type AdminActionResult =
  | { ok: true; live: boolean }
  | { ok: false; error: string };

const USER_ROLES: UserRole[] = ["runner", "platformAdmin"];

const ACCOUNT_STATUSES: AccountStatus[] = ["active", "suspended", "banned"];

const SUBSCRIPTION_STATUSES: UserSubscriptionStatus[] = ["basic", "premium"];

const MODERATION_ACTIONS: UserModerationAction[] = [
  "warn",
  "suspend",
  "ban",
  "restore",
];

const RESOLUTION_STATUSES: ReportResolutionStatus[] = [
  "pending",
  "reviewing",
  "resolved",
  "dismissed",
];

const FEEDBACK_STATUSES: FeedbackStatus[] = [
  "new",
  "responded",
  "resolved",
  "dismissed",
  "escalated",
];

const ERROR_STATUSES: ErrorStatus[] = [
  "new",
  "investigating",
  "resolved",
  "ignored",
];

// requireAdmin() and the ActingAdmin type it returns now live in
// ./require-admin (a plain module, not a server action) so they can be
// imported outside "use server" files too. See that module's header comment.

async function runMutation(
  mutate: (admin: ActingAdmin) => Promise<void>,
): Promise<AdminActionResult> {
  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    await mutate(auth.admin);
    return { ok: true, live: true };
  } catch (error) {
    console.warn("[admin-action] Mutation failed.", error);
    return {
      ok: false,
      error: "The backend rejected this action. Try again.",
    };
  }
}

// Granting platformAdmin hands over the whole governance surface, so a role
// change is held to the same bar as suspension and subscription overrides: a
// mandatory reason, and a before/after audit snapshot read from the live
// document rather than trusted from the client.
export async function changeUserRole(
  uid: string,
  role: UserRole,
  reason: string,
): Promise<AdminActionResult> {
  if (!uid || !USER_ROLES.includes(role)) {
    return { ok: false, error: "Invalid role change request." };
  }

  const trimmedReason = reason?.trim();
  if (!trimmedReason) {
    return { ok: false, error: "A reason is required for this action." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    const db = getAdminDb();
    const data = (await db.collection("users").doc(uid).get()).data();
    const before = {
      userRole: typeof data?.userRole === "string" ? data.userRole : null,
    };

    await setUserRoleInDb(uid, role, auth.admin.email, trimmedReason, before);
    return { ok: true, live: true };
  } catch (error) {
    console.warn(`[admin-action] Role mutation failed for user ${uid}.`, error);
    return {
      ok: false,
      error: "The backend rejected this role change. Try again.",
    };
  }
}

export async function setUserAccountStatus(
  uid: string,
  status: AccountStatus,
): Promise<AdminActionResult> {
  if (!uid || !ACCOUNT_STATUSES.includes(status)) {
    return { ok: false, error: "Invalid account status request." };
  }

  return runMutation((admin) =>
    setUserAccountStatusInDb(uid, status, admin.email),
  );
}

// --- user subscription + moderation (users/{uid}) ---------------------------
//
// Both operations are privileged, audited overrides with real immediate
// effect (subscription gates Basic/Premium feature access only; moderation
// changes accountStatus). Each requires a non-empty reason, re-verifies the
// caller via requireAdmin(), reads the users/{uid} document as the audit
// "before" snapshot, and writes through src/lib/firebase/firestore.ts, which
// appends the full before/after audit trail.

// `expiresAtIso` is an optional end date for a Premium grant (the client sends
// a plain `YYYY-MM-DD`, interpreted as the end of that day). Omitting it keeps
// the pre-existing "never lapses" behaviour. Switching to basic always clears
// any stored expiry.
export async function setUserSubscription(
  uid: string,
  status: UserSubscriptionStatus,
  reason: string,
  expiresAtIso?: string,
): Promise<AdminActionResult> {
  if (!uid || !SUBSCRIPTION_STATUSES.includes(status)) {
    return { ok: false, error: "Invalid subscription request." };
  }

  const trimmedReason = reason?.trim();
  if (!trimmedReason) {
    return { ok: false, error: "A reason is required for this action." };
  }

  const trimmedExpiry = expiresAtIso?.trim();
  let expiresAt: Date | null = null;

  if (trimmedExpiry) {
    // End of the selected day, so a grant "through 31 Mar" stays live all day.
    const parsed = new Date(`${trimmedExpiry}T23:59:59.999Z`);

    if (Number.isNaN(parsed.getTime())) {
      return { ok: false, error: "The expiry date is not a valid date." };
    }

    if (parsed.getTime() <= Date.now()) {
      return { ok: false, error: "The expiry date must be in the future." };
    }

    expiresAt = parsed;
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    const db = getAdminDb();
    const snapshot = await db.collection("users").doc(uid).get();
    const data = snapshot.data();
    const storedExpiry = data?.subscriptionExpiresAt;
    const before = {
      subscriptionStatus:
        typeof data?.subscriptionStatus === "string"
          ? data.subscriptionStatus
          : null,
      subscriptionExpiresAt:
        storedExpiry && typeof storedExpiry.toDate === "function"
          ? (storedExpiry.toDate() as Date).toISOString()
          : null,
    };

    await setUserSubscriptionInDb(
      uid,
      status,
      auth.admin.email,
      trimmedReason,
      before,
      expiresAt,
    );
  } catch (error) {
    console.warn(`[admin-action] Subscription mutation failed for user ${uid}.`, error);
    return {
      ok: false,
      error: "The backend rejected this subscription update. Try again.",
    };
  }

  // Outside the try, as in runProgressionMutation: the subscription change is
  // already committed and audited, so a refresh failure must not present it as
  // a failed save.
  //
  // The aggregation recomputes the premium set from users/{uid} on every run,
  // so a subscription change only reaches the board when it next runs.
  await refreshLeaderboardAfter(`subscription for ${uid}`);
  return { ok: true, live: true };
}

export async function moderateUser(
  uid: string,
  action: UserModerationAction,
  reason: string,
): Promise<AdminActionResult> {
  if (!uid || !MODERATION_ACTIONS.includes(action)) {
    return { ok: false, error: "Invalid moderation request." };
  }

  const trimmedReason = reason?.trim();
  if (!trimmedReason) {
    return { ok: false, error: "A reason is required for this action." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    const db = getAdminDb();
    const snapshot = await db.collection("users").doc(uid).get();
    const data = snapshot.data();
    const before = {
      accountStatus:
        typeof data?.accountStatus === "string" ? data.accountStatus : null,
    };

    await setUserModerationInDb(
      uid,
      action,
      auth.admin.email,
      trimmedReason,
      before,
    );
    return { ok: true, live: true };
  } catch (error) {
    console.warn(`[admin-action] Moderation mutation failed for user ${uid}.`, error);
    return {
      ok: false,
      error: "The backend rejected this moderation action. Try again.",
    };
  }
}

// --- avatar takedown (userProfiles/{uid} avatarXxx fields) ------------------
//
// Explicit admin "clear avatar" control, modelled on setUserXp() above: a
// mandatory reason, re-verification via requireAdmin(), and a real backend
// mutation through src/lib/firebase/firestore.ts, which deletes the Cloud
// Storage object(s) before clearing the Firestore fields and appends the
// audit trail. The Firestore field is not the enforcement boundary — the
// avatar's Storage download token bypasses Storage rules entirely — so this
// is the only way to actually stop a stored photo from being fetchable.
// setUserAccountStatus()/moderateUser() call the exact same underlying
// routine automatically when a suspend/ban transition locks the account out
// (see firestore.ts), so this action and that wiring can never drift apart.
export async function clearUserAvatar(
  uid: string,
  reason: string,
): Promise<AdminActionResult> {
  if (!uid) {
    return { ok: false, error: "Missing user id." };
  }

  const trimmedReason = reason?.trim();
  if (!trimmedReason) {
    return { ok: false, error: "A reason is required for this action." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    await clearUserAvatarInDb(uid, auth.admin.email, trimmedReason, "user.avatar.clear");
  } catch (error) {
    console.warn(`[admin-action] Avatar takedown failed for user ${uid}.`, error);
    return {
      ok: false,
      error: "The backend rejected this avatar takedown. Try again.",
    };
  }

  // Deliberately outside the try, matching setUserSubscription()/
  // runProgressionMutation() below: the takedown is already committed and
  // audited by this point, so a refresh failure must not be reported as a
  // failed save. This only closes the gap sooner than the hourly rebuild —
  // the next aggregation run re-derives every snapshot row's avatarUrl from
  // the (now-cleared) profile regardless.
  await refreshLeaderboardAfter(`avatar takedown for ${uid}`);
  return { ok: true, live: true };
}

export async function resolveReport(
  reportId: string,
  resolutionStatus: ReportResolutionStatus,
  note?: string,
): Promise<AdminActionResult> {
  if (!reportId || !RESOLUTION_STATUSES.includes(resolutionStatus)) {
    return { ok: false, error: "Invalid report resolution request." };
  }

  return runMutation((admin) =>
    setReportResolution(reportId, resolutionStatus, admin.email, note),
  );
}

// Dismisses an overview attention item (adminNotifications/{id}). Mirrors
// resolveReport() above: requireAdmin() -> hasFirebaseEnv() gate ->
// dismissAdminNotification() via runMutation().
export async function dismissAttentionItem(
  id: string,
): Promise<AdminActionResult> {
  if (!id) {
    return { ok: false, error: "Missing attention item id." };
  }

  return runMutation((admin) => dismissAdminNotification(id, admin.email));
}

// --- feed-post moderation (moderationCommands/{commandId}) -----------------
//
// The Exception Queue's "Remove post" action for reported-feed-post cases.
// The admin console only holds Admin SDK access and cannot invoke Cloud
// Functions callables, so removal is a Firestore command-document handoff
// exactly like requestLeaderboardRecalculation() below: this action creates
// a `moderationCommands` document, the moderationCommandCreated Cloud
// Function trigger (functions/src/moderation/moderationCommand.ts) consumes
// it and performs the real removal via the feed lifecycle port, then
// merge-writes the outcome back onto the same document.
// getModerationCommandStatus() below polls that document for the client.
// `AdminActionResult` is not reused here for the same reason
// LeaderboardRecalculationRequestResult isn't: the client needs the new
// command id back on success, which the shared shape does not carry.

export type ModerationCommandRequestResult =
  | { ok: true; live: true; commandId: string }
  | { ok: true; live: false }
  | { ok: false; error: string };

export async function requestFeedPostRemoval(
  postId: string,
): Promise<ModerationCommandRequestResult> {
  if (!postId) {
    return { ok: false, error: "Missing post id." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    const commandId = await requestModerationCommand(
      "removeFeedPost",
      postId,
      auth.admin.email,
    );
    return { ok: true, live: true, commandId };
  } catch (error) {
    console.warn(
      `[admin-action] Feed post removal request failed for ${postId}.`,
      error,
    );
    return {
      ok: false,
      error: "The backend rejected this removal request. Try again.",
    };
  }
}

export type ModerationCommandStatusResult =
  | { ok: true; command: ModerationCommandRow | null }
  | { ok: false; error: string };

export async function getModerationCommandStatus(
  commandId: string,
): Promise<ModerationCommandStatusResult> {
  if (!commandId) {
    return { ok: false, error: "Missing moderation command id." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, command: null };
  }

  try {
    const command = await getModerationCommand(commandId);
    return { ok: true, command };
  } catch (error) {
    console.warn(
      `[admin-action] Moderation command status read failed for ${commandId}.`,
      error,
    );
    return {
      ok: false,
      error: "Could not read the removal status. Try again.",
    };
  }
}

// --- leaderboard anomaly flags (reports, from Leaderboard Oversight) -------
//
// "Send to Exception Queue" on the Leaderboard Oversight page routes a
// real anomaly-detection finding (getLiveSuspiciousScores() in
// src/lib/admin/live-data.ts) into the same `reports` collection user
// reports land in, so it shows up in the Exception Queue for human review
// instead of only disappearing from local UI state. Follows the same
// requireAdmin() -> hasFirebaseEnv() -> try/catch shape as runMutation()
// above; the evidence (reason/region/flaggedScore) came from a live read
// moments earlier, so it is trusted here rather than re-derived.
export async function flagLeaderboardScore(input: {
  ownerUid: string;
  contributionId: string;
  reason: string;
  region: string;
  flaggedScore: number;
}): Promise<AdminActionResult> {
  if (!input.ownerUid || !input.contributionId || !input.reason) {
    return { ok: false, error: "Invalid anomaly flag request." };
  }

  return runMutation(async (admin) => {
    await createLeaderboardReport({
      ownerUid: input.ownerUid,
      contributionId: input.contributionId,
      reason: input.reason,
      description: `Flagged by leaderboard anomaly detection. Region: ${input.region}. Flagged score: ${input.flaggedScore} XP.`,
      adminEmail: admin.email,
      adminUid: admin.uid,
    });
  });
}

// --- leaderboard recalculation (leaderboardAdminCommands/{commandId}) ------
//
// The admin console only holds Admin SDK access (Auth + Firestore) and cannot
// invoke Cloud Functions callables, so "request a recalculation" is a
// Firestore command-document handoff: this action creates a
// `leaderboardAdminCommands` document, the leaderboardAdminCommandCreated
// Cloud Function trigger consumes it and runs the real aggregation, then
// merge-writes the outcome back onto the same document.
// getLeaderboardRecalculationStatus() below polls that document for the
// client. `AdminActionResult` is deliberately not reused here: this action
// needs to return the new command id on success so the client knows what to
// poll, which the shared shape does not carry.

export type LeaderboardRecalculationRequestResult =
  | { ok: true; live: true; commandId: string }
  | { ok: true; live: false }
  | { ok: false; error: string };

// `periodKey` defaults to the current Singapore month (mirroring the
// scheduled refreshLeaderboardSnapshots job) when the caller does not supply
// one.
export async function requestLeaderboardRecalculation(
  periodKey?: string,
): Promise<LeaderboardRecalculationRequestResult> {
  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  const resolvedPeriodKey = periodKey?.trim() || currentSingaporeMonthKey(new Date());

  try {
    const commandId = await requestLeaderboardRecalculationInDb(
      resolvedPeriodKey,
      auth.admin.email,
    );
    return { ok: true, live: true, commandId };
  } catch (error) {
    console.warn("[admin-action] Leaderboard recalculation request failed.", error);
    return {
      ok: false,
      error: "The backend rejected this recalculation request. Try again.",
    };
  }
}

export type LeaderboardRecalculationStatusResult =
  | { ok: true; command: LeaderboardCommandRow | null }
  | { ok: false; error: string };

export async function getLeaderboardRecalculationStatus(
  commandId: string,
): Promise<LeaderboardRecalculationStatusResult> {
  if (!commandId) {
    return { ok: false, error: "Missing recalculation command id." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, command: null };
  }

  try {
    const command = await getLeaderboardCommand(commandId);
    return { ok: true, command };
  } catch (error) {
    console.warn(
      `[admin-action] Leaderboard recalculation status read failed for ${commandId}.`,
      error,
    );
    return {
      ok: false,
      error: "Could not read the recalculation status. Try again.",
    };
  }
}

// --- standings viewer (leaderboardSnapshots/{snapshotId}) -------------------
//
// The read-only "Standings viewer" on the Leaderboard Oversight page loads a
// single region x division snapshot on demand rather than preloading the
// whole leaderboardSnapshots collection into the client. Snapshot document
// ids are deterministic (`monthly_{regionId}_{divisionKey}_{periodKey}`,
// mirroring functions/src/leaderboard/monthlyLeaderboardPlanner.ts), so this
// action can go straight to a single-document read. A null `snapshot` is a
// normal result, not an error: most region x division combinations
// legitimately have no runners for a given period.

export type LeaderboardSnapshotLookupResult =
  | { ok: true; snapshot: LeaderboardSnapshotRow | null }
  | { ok: false; error: string };

export async function loadLeaderboardSnapshot(
  regionId: string,
  divisionKey: string,
  periodKey: string,
): Promise<LeaderboardSnapshotLookupResult> {
  if (!regionId || !divisionKey || !periodKey) {
    return { ok: false, error: "Region, division, and period are required." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, snapshot: null };
  }

  try {
    const snapshotId = `monthly_${regionId}_${divisionKey}_${periodKey}`;
    const snapshot = await getLeaderboardSnapshotById(snapshotId);
    return { ok: true, snapshot };
  } catch (error) {
    console.warn(
      `[admin-action] Leaderboard snapshot lookup failed for ${regionId}/${divisionKey}/${periodKey}.`,
      error,
    );
    return {
      ok: false,
      error: "Could not load that leaderboard standing. Try again.",
    };
  }
}

// --- feedback triage (feedback/{feedbackId}) --------------------------------
//
// Status and note mutations for the Feedback & Complaints inbox. Mirrors
// resolveReport() above: re-verifies the caller via requireAdmin(), then
// writes through setFeedbackTriage() in src/lib/firebase/firestore.ts, which
// merge-writes the change and appends the audit trail. `note` is optional so
// the same action serves both "advance status" (no note change) and "save
// note" (status held, note updated) from the client.

export async function triageFeedback(
  feedbackId: string,
  status: FeedbackStatus,
  note?: string,
): Promise<AdminActionResult> {
  if (!feedbackId || !FEEDBACK_STATUSES.includes(status)) {
    return { ok: false, error: "Invalid feedback triage request." };
  }

  return runMutation((admin) =>
    setFeedbackTriage(feedbackId, status, admin.email, note),
  );
}

export async function closeFeedback(
  feedbackId: string,
  closed: boolean,
): Promise<AdminActionResult> {
  if (!feedbackId) {
    return { ok: false, error: "Missing feedback id." };
  }

  return runMutation((admin) =>
    setFeedbackClosed(feedbackId, closed, admin.email),
  );
}

// --- app error triage (errorGroups/{groupId}) -------------------------------
//
// Status and note mutations for the App Errors console. Mirrors
// triageFeedback() above: re-verifies the caller via requireAdmin(), then
// writes through setErrorGroupTriage() in src/lib/firebase/firestore.ts,
// which merge-writes the change and appends the audit trail. `note` is
// optional so the same action serves both "advance status" (no note change)
// and "save note" (status held, note updated) from the client.

export async function triageErrorGroup(
  groupId: string,
  status: ErrorStatus,
  note?: string,
): Promise<AdminActionResult> {
  if (!groupId || !ERROR_STATUSES.includes(status)) {
    return { ok: false, error: "Invalid error triage request." };
  }

  return runMutation((admin) =>
    setErrorGroupTriage(groupId, status, admin.email, note),
  );
}

// --- backend config (config/progression, config/leaderboard,
//     config/featureAccess, config/siteContent) ---------------------------
//
// Unlike the mutations above, these write plain configuration documents
// rather than backend-computed state, but they still go through the same
// requireAdmin() re-verification, and every write is validated with the exact
// rule set the Cloud Functions runtime enforces (src/lib/admin/config-validation.ts,
// mirroring functions/src/config/configLoader.ts) before it ever reaches
// Firestore.

function computeChangedFields(
  before: Record<string, unknown> | null,
  after: Record<string, unknown>,
): string[] {
  if (!before) {
    return Object.keys(after);
  }

  return Object.keys(after).filter(
    (key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]),
  );
}

// Shared save path for the `config/{name}` documents: re-verify the caller,
// validate the payload against the backend contract, skip the write (but
// still report success) when Firebase is not configured, then merge-write
// with a full before/after audit trail.
//
// With `bumpVersion`, the stored `version` is derived server-side as
// (previous version ?? 0) + 1 and the client-supplied value is discarded — the
// client must never choose a version number. `version` is then excluded from
// changedFields so an automatic bump never reads as a user-visible rule change;
// the audit `after` snapshot still records the real stored version.
async function saveAdminConfig(
  name: string,
  payload: Record<string, unknown>,
  validate: (config: Record<string, unknown>) => { valid: boolean; errors: readonly string[] },
  auditAction: string,
  options?: { bumpVersion?: boolean },
): Promise<AdminActionResult> {
  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  const validation = validate(payload);

  if (!validation.valid) {
    return { ok: false, error: validation.errors.join("; ") };
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    const before = await getConfigDoc(name);

    const bumpVersion = options?.bumpVersion === true;
    const previousVersion = isFiniteNumber(before?.version) ? before.version : 0;
    const written = bumpVersion
      ? { ...payload, version: previousVersion + 1 }
      : payload;

    const changedFields = computeChangedFields(before, written).filter(
      (field) => !(bumpVersion && field === "version"),
    );

    await setConfigDoc(name, written, auth.admin.email, auditAction, changedFields, before);
    return { ok: true, live: true };
  } catch (error) {
    console.warn(`[admin-action] Config mutation failed for config/${name}.`, error);
    return {
      ok: false,
      error: "The backend rejected this configuration update. Try again.",
    };
  }
}

// The monthly aggregation re-reads config/leaderboard and every owner's
// subscription state on each run, but it only runs hourly — so an admin who
// changes eligibility sees nothing happen for up to an hour and reasonably
// concludes the change did not take. Enqueueing the same recalculation command
// the "Recalculate" button uses closes that gap in seconds.
//
// Best effort by design: the primary write has already been committed and
// audited at this point, so a failed refresh must not be reported as a failed
// save. The hourly job remains the backstop.
async function refreshLeaderboardAfter(trigger: string): Promise<void> {
  const result = await requestLeaderboardRecalculation();

  if (!result.ok) {
    console.warn(
      `[admin-action] ${trigger} saved, but the follow-up leaderboard recalculation was rejected: ${result.error}`,
    );
  }
}

export async function saveProgressionConfig(
  config: ProgressionConfig,
): Promise<AdminActionResult> {
  return saveAdminConfig(
    "progression",
    config as unknown as Record<string, unknown>,
    (candidate) => validateProgressionConfig(candidate as unknown as ProgressionConfig),
    "config.progression.update",
    { bumpVersion: true },
  );
}

// Re-applies an earlier `config/progression` snapshot recovered from the admin
// audit log.
//
// The client only sends an audit-entry id; the payload itself is always re-read
// server-side, so a tampered request can never inject a configuration. The
// snapshot is deep-merged over DEFAULT_PROGRESSION_CONFIG (so contract fields
// added after the snapshot was taken fall back to defaults instead of going
// missing) and re-validated before it is written.
//
// Restoring moves history FORWARD: it writes through the same audited save path
// as a normal edit and takes the next version number. It never rewinds the
// version counter and never rewrites an existing audit entry.
export async function restoreProgressionConfig(
  auditEntryId: string,
): Promise<AdminActionResult & { config?: ProgressionConfig }> {
  if (!auditEntryId) {
    return { ok: false, error: "Missing configuration history entry id." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return {
      ok: false,
      error:
        "Restoring a configuration requires a connected backend. Firebase is not configured, so there is no history to restore from.",
    };
  }

  let entry;
  try {
    entry = await getConfigHistoryEntry(auditEntryId);
  } catch (error) {
    console.warn(
      `[admin-action] Failed to read config history entry ${auditEntryId}.`,
      error,
    );
    return {
      ok: false,
      error: "Could not read that configuration history entry. Try again.",
    };
  }

  if (!entry) {
    return { ok: false, error: "That configuration history entry no longer exists." };
  }

  if (entry.targetId !== "progression") {
    return {
      ok: false,
      error: "That history entry does not belong to the progression configuration.",
    };
  }

  if (!entry.after) {
    return {
      ok: false,
      error: "That history entry has no stored configuration snapshot to restore.",
    };
  }

  const restored = deepMerge(DEFAULT_PROGRESSION_CONFIG, entry.after);
  const validation = validateProgressionConfig(restored);

  if (!validation.valid) {
    return { ok: false, error: validation.errors.join("; ") };
  }

  const result = await saveAdminConfig(
    "progression",
    restored as unknown as Record<string, unknown>,
    (candidate) => validateProgressionConfig(candidate as unknown as ProgressionConfig),
    "config.progression.restore",
    { bumpVersion: true },
  );

  if (!result.ok) {
    return result;
  }

  // Re-read so the client resyncs against exactly what was stored, including
  // the server-assigned version number.
  try {
    const stored = await getConfigDoc("progression");
    if (stored) {
      const merged = deepMerge(DEFAULT_PROGRESSION_CONFIG, stored);
      if (validateProgressionConfig(merged).valid) {
        return { ...result, config: merged };
      }
    }
  } catch (error) {
    console.warn("[admin-action] Restore succeeded but re-read failed.", error);
  }

  return { ...result, config: restored };
}

// `excludePremium` and `minRunsToQualify` decide who is on the board at all, so
// a saved change that is not aggregated is invisible to every runner.
export async function saveLeaderboardConfig(
  config: LeaderboardConfig,
): Promise<AdminActionResult> {
  const result = await saveAdminConfig(
    "leaderboard",
    config as unknown as Record<string, unknown>,
    (candidate) => validateLeaderboardConfig(candidate as unknown as LeaderboardConfig),
    "config.leaderboard.update",
  );

  if (result.ok && result.live) {
    await refreshLeaderboardAfter("config/leaderboard");
  }

  return result;
}

// config/paywall drives the mobile app's premium upsell sheet. Signed-in app
// clients read the document directly (the one client-readable config doc), so
// a save is user-visible on the next paywall open — no deploy involved.
export async function savePaywallConfig(
  config: PaywallConfig,
): Promise<AdminActionResult> {
  // Normalize through mergePaywallConfig before validating/writing: it
  // rebuilds a clean object containing only schema fields, so unknown keys a
  // compromised or buggy client attaches can never be persisted into the one
  // config document every signed-in app client reads — and validation then
  // runs against a shape whose nested objects are guaranteed to exist. This
  // matches the restore path, which already normalizes the same way.
  const normalized = mergePaywallConfig(config);
  return saveAdminConfig(
    "paywall",
    normalized as unknown as Record<string, unknown>,
    (candidate) => validatePaywallConfig(candidate as unknown as PaywallConfig),
    "config.paywall.update",
    { bumpVersion: true },
  );
}

// Re-applies an earlier `config/paywall` snapshot recovered from the admin
// audit log. Same shape as restoreProgressionConfig: the payload is always
// re-read server-side from the audit entry, merged over defaults, re-validated,
// and written forward as a NEW version through the audited save path.
export async function restorePaywallConfig(
  auditEntryId: string,
): Promise<AdminActionResult & { config?: PaywallConfig }> {
  if (!auditEntryId) {
    return { ok: false, error: "Missing configuration history entry id." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return {
      ok: false,
      error:
        "Restoring a configuration requires a connected backend. Firebase is not configured, so there is no history to restore from.",
    };
  }

  let entry;
  try {
    entry = await getConfigHistoryEntry(auditEntryId);
  } catch (error) {
    console.warn(
      `[admin-action] Failed to read config history entry ${auditEntryId}.`,
      error,
    );
    return {
      ok: false,
      error: "Could not read that configuration history entry. Try again.",
    };
  }

  if (!entry) {
    return { ok: false, error: "That configuration history entry no longer exists." };
  }

  if (entry.targetId !== "paywall") {
    return {
      ok: false,
      error: "That history entry does not belong to the paywall configuration.",
    };
  }

  if (!entry.after) {
    return {
      ok: false,
      error: "That history entry has no stored configuration snapshot to restore.",
    };
  }

  const restored = mergePaywallConfig(entry.after);
  const validation = validatePaywallConfig(restored);

  if (!validation.valid) {
    return { ok: false, error: validation.errors.join("; ") };
  }

  const result = await saveAdminConfig(
    "paywall",
    restored as unknown as Record<string, unknown>,
    (candidate) => validatePaywallConfig(candidate as unknown as PaywallConfig),
    "config.paywall.restore",
    { bumpVersion: true },
  );

  if (!result.ok) {
    return result;
  }

  // Re-read so the client resyncs against exactly what was stored, including
  // the server-assigned version number.
  try {
    const stored = await getConfigDoc("paywall");
    if (stored) {
      const merged = mergePaywallConfig(stored);
      if (validatePaywallConfig(merged).valid) {
        return { ...result, config: merged };
      }
    }
  } catch (error) {
    console.warn("[admin-action] Restore succeeded but re-read failed.", error);
  }

  return { ...result, config: restored };
}

export async function saveFeatureAccessConfig(
  config: FeatureAccessConfig,
): Promise<AdminActionResult> {
  return saveAdminConfig(
    "featureAccess",
    config as unknown as Record<string, unknown>,
    (candidate) => validateFeatureAccessConfig(candidate as unknown as FeatureAccessConfig),
    "config.featureAccess.update",
  );
}

export async function saveAutomationConfig(
  config: AutomationConfig,
): Promise<AdminActionResult> {
  return saveAdminConfig(
    "automation",
    config as unknown as Record<string, unknown>,
    (candidate) => validateAutomationConfig(candidate as unknown as AutomationConfig),
    "config.automation.update",
    { bumpVersion: true },
  );
}

export async function saveCharacterAccessConfig(
  config: CharacterAccessConfig,
): Promise<AdminActionResult> {
  return saveAdminConfig(
    "characterAccess",
    config as unknown as Record<string, unknown>,
    (candidate) => validateCharacterAccessConfig(candidate as unknown as CharacterAccessConfig),
    "config.characterAccess.update",
    { bumpVersion: true },
  );
}

export async function saveChallengeAccessConfig(
  config: ChallengeAccessConfig,
): Promise<AdminActionResult> {
  return saveAdminConfig(
    "challengeAccess",
    config as unknown as Record<string, unknown>,
    (candidate) => validateChallengeAccessConfig(candidate as unknown as ChallengeAccessConfig),
    "config.challengeAccess.update",
    { bumpVersion: true },
  );
}

export async function saveSiteContent(
  content: WebsiteContent,
): Promise<AdminActionResult> {
  return saveAdminConfig(
    "siteContent",
    content as unknown as Record<string, unknown>,
    // Most website copy (announcement, hero, features, FAQ) has no
    // backend-enforced shape beyond "is an object". The structured pricing and
    // testimonials blocks do: validate them so a malformed write is rejected
    // with a clear message instead of silently rendering the fallback on the
    // live page.
    (candidate) => {
      const record = candidate as {
        pricing?: unknown;
        testimonials?: unknown;
        problem?: unknown;
        solution?: unknown;
        personalizedPlan?: unknown;
        journeyMap?: unknown;
        xpProgression?: unknown;
        territorial?: unknown;
        postRunSummary?: unknown;
        team?: unknown;
        documents?: unknown;
        download?: unknown;
      };
      const errors = [
        ...validateSiteProblem(record.problem).errors,
        ...validateSiteSolution(record.solution).errors,
        ...validateSitePersonalizedPlan(record.personalizedPlan).errors,
        ...validateSiteJourneyMap(record.journeyMap).errors,
        ...validateSiteXpProgression(record.xpProgression).errors,
        ...validateSiteTerritorial(record.territorial).errors,
        ...validateSitePostRunSummary(record.postRunSummary).errors,
        ...validateSitePricing(record.pricing).errors,
        ...validateSiteTestimonials(record.testimonials).errors,
        ...validateSiteTeam(record.team).errors,
        ...validateSiteDocuments(record.documents).errors,
        ...validateSiteDownload(record.download).errors,
      ];
      return { valid: errors.length === 0, errors };
    },
    "config.siteContent.update",
  );
}

// --- per-user progression administration -------------------------------------
//
// Direct XP/level corrections are a privileged, audited override path for
// support scenarios (e.g. a miscalculated run award) — not a normal client
// capability. Every action below re-verifies the caller via requireAdmin(),
// requires a non-empty `reason`, reads the current userProfiles/{uid}
// progression fields as the audit "before" snapshot, applies the change, and
// writes the audit "after" snapshot through setUserProgression() in
// src/lib/firebase/firestore.ts. Clients can never reach these fields
// directly; Firestore rules already deny that.

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

// Shared save path for progression corrections: re-verify the caller, require
// a reason, skip the write (but still report success) when Firebase is not
// configured, otherwise read the before-snapshot, apply `computeAfter`, and
// merge-write with a full audit trail.
async function runProgressionMutation(
  uid: string,
  reason: string,
  auditAction: string,
  computeAfter: (
    before: UserProgressionFields,
    config: ProgressionConfig,
  ) => Partial<UserProgressionFields>,
): Promise<AdminActionResult> {
  if (!uid) {
    return { ok: false, error: "Missing user id." };
  }

  const trimmedReason = reason?.trim();
  if (!trimmedReason) {
    return { ok: false, error: "A reason is required for this action." };
  }

  const auth = await requireAdmin();

  if (!auth.ok) {
    return auth;
  }

  if (!hasFirebaseEnv()) {
    return { ok: true, live: false };
  }

  try {
    // The stored config/progression is what Cloud Functions will recompute
    // against on the user's next run. Deriving a correction from the hardcoded
    // DEFAULTS instead would write a level, level label and — through the
    // leaderboard contribution — a divisionKey that the backend then disagrees
    // with, which physically files the runner into the wrong league snapshot.
    const config = await getLiveProgressionConfig();
    const before = await getUserProgression(uid);
    const changes = computeAfter(before, config);
    await setUserProgression(
      uid,
      changes,
      auth.admin.email,
      auditAction,
      before,
      trimmedReason,
      config,
    );
  } catch (error) {
    console.warn(`[admin-action] Progression mutation failed for user ${uid}.`, error);
    return {
      ok: false,
      error: "The backend rejected this progression update. Try again.",
    };
  }

  // Deliberately OUTSIDE the try above. The correction is committed and audited
  // by this point, so a throw in here must not be reported as a failed save:
  // adjustUserXp() is a delta, and an admin who retries a "failed" adjustment
  // applies it twice.
  //
  // An XP correction rewrites this period's leaderboard contribution, which can
  // reorder the whole board — not just this runner's own row.
  await refreshLeaderboardAfter(`progression for ${uid}`);
  return { ok: true, live: true };
}

// Set/Adjust XP recompute level from the current progression curve; Set
// Level backfills the level's minimum totalXp on the same curve so the two
// fields stay consistent. This matters because Cloud Functions treats
// totalXp as the sole source of truth and recomputes both fields on every
// completed run — a level-only override would otherwise be silently
// discarded (and displayed as inconsistent) the next time the user runs.
export async function setUserXp(
  uid: string,
  xp: number,
  reason: string,
): Promise<AdminActionResult> {
  if (!isFiniteNumber(xp) || xp < 0) {
    return { ok: false, error: "XP must be a non-negative number." };
  }

  const nextXp = Math.floor(xp);
  return runProgressionMutation(uid, reason, "user.progression.xp.set", (_before, config) => ({
    totalXp: nextXp,
    level: levelForTotalXp(nextXp, config),
  }));
}

export async function adjustUserXp(
  uid: string,
  delta: number,
  reason: string,
): Promise<AdminActionResult> {
  if (!isFiniteNumber(delta)) {
    return { ok: false, error: "XP adjustment must be a finite number." };
  }

  return runProgressionMutation(
    uid,
    reason,
    "user.progression.xp.adjust",
    (before, config) => {
      const nextXp = Math.max(0, (before.totalXp ?? 0) + Math.floor(delta));
      return { totalXp: nextXp, level: levelForTotalXp(nextXp, config) };
    },
  );
}

export async function setUserLevel(
  uid: string,
  level: number,
  reason: string,
): Promise<AdminActionResult> {
  if (!isFiniteNumber(level) || level < 1) {
    return { ok: false, error: "Level must be a positive number." };
  }

  return runProgressionMutation(uid, reason, "user.progression.level.set", (_before, config) => {
    const nextLevel = Math.min(Math.floor(level), config.maxLevel);
    return { level: nextLevel, totalXp: xpForLevel(nextLevel, config) };
  });
}

export async function resetUserProgression(
  uid: string,
  reason: string,
): Promise<AdminActionResult> {
  return runProgressionMutation(uid, reason, "user.progression.reset", () => ({
    totalXp: 0,
    level: 1,
    monthlyXp: 0,
  }));
}
