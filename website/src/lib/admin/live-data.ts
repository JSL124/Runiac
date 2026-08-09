// Live Firestore-backed implementations for the admin data layer.
//
// Each function here adapts the narrow rows returned by
// src/lib/firebase/firestore.ts onto the admin UI view models in ./types.
// These functions are only called by ./data.ts when hasFirebaseEnv() is true;
// data.ts also owns the mock fallback when a live read throws.

import {
  countActivitiesSince,
  countLeaderboardCurrentViewsByStatus,
  countUsers,
  countUsersBySubscription,
  currentSingaporeMonthKey,
  getConfigDoc,
  getFeedPostAuthorUid,
  getLatestLeaderboardSnapshot,
  getLeaderboardAggregationLock,
  getLeaderboardCurrentPeriod,
  getModerationCommandRemovedAuthorUid,
  getSiteContent,
  listAccountDeletionCommands,
  listActivityOwnerUidsInWindow,
  listActivitySummaries,
  listAdminNotifications,
  listAuditLogs,
  listConfigHistory,
  listErrorGroups,
  listFeedback,
  listLeaderboardContributions,
  listLeaderboardSnapshotSummaries,
  listNewsletterCampaigns,
  listNewsletterSubscribers,
  listReports,
  listUsers,
} from "@/lib/firebase/firestore";
import type {
  ActivitySummaryRow,
  AdminNotificationRow,
  AdminUserRow,
  AuditLogRow,
  ErrorGroupRow,
  FeedbackRow,
  LeaderboardContributionRow,
  NewsletterCampaignRow,
  NewsletterSubscriberRow,
  ReportRow,
  SiteContentRow,
} from "@/lib/firebase/types";
import {
  DEFAULT_AUTOMATION_CONFIG,
  DEFAULT_CHALLENGE_ACCESS_CONFIG,
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  DEFAULT_FEATURE_ACCESS_CONFIG,
  DEFAULT_LEADERBOARD_CONFIG,
  DEFAULT_PROGRESSION_CONFIG,
  deepMerge,
  validateAutomationConfig,
  validateChallengeAccessConfig,
  validateCharacterAccessConfig,
  validateFeatureAccessConfig,
  validateLeaderboardConfig,
  validateProgressionConfig,
} from "./config-validation";
import type {
  AutomationConfig,
  ChallengeAccessConfig,
  CharacterAccessConfig,
  FeatureAccessConfig,
  LeaderboardConfig,
  ProgressionConfig,
} from "./config-validation";
import {
  DEFAULT_PAYWALL_CONFIG,
  mergePaywallConfig,
  validatePaywallConfig,
  type PaywallConfig,
} from "./paywall-config";
import { mergeSitePricing } from "@/lib/site-pricing";
import { mergeSiteTestimonials } from "@/lib/site-testimonials";
import { mergeSiteTeam } from "@/lib/site-team";
import { mergeSiteDocuments } from "@/lib/site-documents";
import { mergeSiteDownload } from "@/lib/site-download";
import { mergeSiteProblem } from "@/lib/site-problem";
import { mergeSiteSolution } from "@/lib/site-solution";
import { mergeSitePersonalizedPlan } from "@/lib/site-personalized-plan";
import {
  mergeSiteJourneyMap,
  mergeSiteXpProgression,
  mergeSiteTerritorial,
  mergeSitePostRunSummary,
} from "@/lib/site-highlight";
import {
  mergeSectionTitles,
  mergeSectionOrder,
} from "@/lib/site-section-titles";
import type {
  AccountStatus,
  ActiveUsersPoint,
  AdminActionLogEntry,
  AdminUser,
  AggregationJob,
  AttentionItem,
  AuditCategory,
  AuditEntry,
  ConfigVersionEntry,
  ErrorGroup,
  ErrorStatus,
  ExceptionCase,
  ExceptionType,
  FeedbackCategory,
  FeedbackItem,
  FeedbackStatus,
  LeaderboardCoverageSummary,
  LeaderboardCurrentPeriod,
  LeaderboardParticipationBreakdown,
  LeaderboardSettings,
  LevelThreshold,
  NewsletterCampaign,
  NewsletterCampaignStatus,
  NewsletterSubscriber,
  NewsletterSubscriberStatus,
  OverviewStat,
  ReportTargetType,
  Severity,
  SubscriptionStatus,
  SuspiciousScore,
  SystemHealthComponent,
  SystemStatus,
  UserRole,
  WebsiteContent,
  XpRule,
} from "./types";
import { SUSPICIOUS_SCORE_LIST_CAP } from "./types";
import { formatNumber } from "./format";
import { levelThresholds as computeLevelThresholds } from "./level-curve";

const EPOCH_ISO = "1970-01-01T00:00:00.000Z";

// --- shared overview/system-health constants ---------------------------------

const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;

// How many trailing months (inclusive of the current period) the active
// users trend chart shows.
const MAU_TREND_MONTHS = 6;

// Per-month distinct-owner scan cap for getLiveActiveUsersTrend() — see
// listActivityOwnerUidsInWindow() in src/lib/firebase/firestore.ts for what
// happens beyond this many activities in a single month.
const MAU_SCAN_CAP = 5000;

// True when `iso` parses to an instant at or before `now` that is within the
// last 24 hours of it. A null/empty/unparseable timestamp is never "recent"
// — it degrades to false rather than being treated as just-now.
function isWithinLast24h(iso: string | null, now: number): boolean {
  if (!iso) {
    return false;
  }

  const parsed = Date.parse(iso);
  if (Number.isNaN(parsed)) {
    return false;
  }

  return now - parsed <= TWENTY_FOUR_HOURS_MS && parsed <= now;
}

// --- coercion helpers --------------------------------------------------------

const USER_ROLES: UserRole[] = ["runner", "platformAdmin"];

function toUserRole(value: string | null): UserRole {
  return USER_ROLES.includes(value as UserRole) ? (value as UserRole) : "runner";
}

function toSubscription(value: string | null): SubscriptionStatus {
  return value === "premium" ? "premium" : "basic";
}

// `banned` is a real, distinct terminal state written by the moderation panel.
// Collapsing it into `active` made the Banned chip unreachable and offered a
// "Suspend account" button for an already-banned user, so map all three states
// explicitly and default only genuinely unknown values to `active`.
function toAccountStatus(value: string | null): AccountStatus {
  if (value === "suspended" || value === "banned") {
    return value;
  }

  return "active";
}

// --- users -------------------------------------------------------------------

// `users` is the search result and is therefore post-filter; the two flags
// describe the scan behind it, so the caller can tell "no more accounts" from
// "no more accounts *within the window we looked at*".
export type LiveUsersPage = {
  users: AdminUser[];
  windowFull: boolean;
  resolvedExactly: boolean;
};

function mapUser(row: AdminUserRow): AdminUser {
  return {
    id: row.uid,
    uid: row.uid,
    displayName: row.displayName ?? row.nickname ?? row.email ?? row.uid,
    nickname: row.nickname ?? row.uid,
    email: row.email ?? "",
    userRole: toUserRole(row.userRole),
    subscriptionStatus: toSubscription(row.subscriptionStatus),
    subscriptionExpiresAt: row.subscriptionExpiresAt,
    accountStatus: toAccountStatus(row.accountStatus),
    // Deliberately NOT defaulted to EPOCH_ISO like the rows below it. A missing
    // join date used to render as 1 Jan 1970 on every account in the console,
    // because no code has ever written users/{uid}.createdAt — a fabricated
    // date reads as data, where a blank reads as "unknown", which is the truth.
    joinedAt: row.createdAt,
    region: row.locationLabel ?? "Unknown",
    note: row.fitnessLevel
      ? `Fitness level: ${row.fitnessLevel}`
      : "No profile notes.",
    totalXp: row.totalXp,
    level: row.level,
    monthlyXp: row.monthlyXp,
    hasAvatar: row.hasAvatar,
  };
}

export async function getLiveUsers(
  query = "",
  limit?: number,
): Promise<LiveUsersPage> {
  const result = await listUsers({
    search: query.trim() || undefined,
    ...(limit === undefined ? {} : { limit }),
  });
  return {
    users: result.rows.map(mapUser),
    windowFull: result.windowFull,
    resolvedExactly: result.resolvedExactly,
  };
}

// --- reports -> exception cases ----------------------------------------------

const TARGET_TYPE_TO_CASE: Record<ReportTargetType, ExceptionType> = {
  user: "reported-user",
  activity: "suspicious-xp",
  feedPost: "reported-feed-post",
};

// A `reports` document whose targetType is absent or unrecognized (e.g. an
// older document predating a target type, or a future value this console
// does not know about yet) must never be silently classified as a real
// moderation type — it renders as "unclassified" so it's still visible to
// the admin without misrepresenting what kind of case it is.
function toCaseType(targetType: string | null): ExceptionType {
  return TARGET_TYPE_TO_CASE[targetType as ReportTargetType] ?? "unclassified";
}

function toReportSeverity(reason: string | null): Severity {
  const lowered = (reason ?? "").toLowerCase();

  if (
    lowered.includes("harass") ||
    lowered.includes("abuse") ||
    lowered.includes("unsafe")
  ) {
    return "high";
  }

  return "medium";
}

// Only "anomaly-detection" is a distinct, backend-recorded value today
// (written by createLeaderboardReport() in src/lib/firebase/firestore.ts);
// every other value — including the common case of no `source` field at all,
// since the client app that creates ordinary user reports never sets one —
// keeps reading as "user-report" so existing client-created reports render
// exactly as they always have.
function toReportSource(value: string | null): "user-report" | "anomaly-detection" {
  return value === "anomaly-detection" ? "anomaly-detection" : "user-report";
}

function mapReport(row: ReportRow): ExceptionCase {
  const type = toCaseType(row.targetType);
  const targetType = (["user", "activity", "feedPost"] as const).includes(
    row.targetType as ReportTargetType,
  )
    ? (row.targetType as ReportTargetType)
    : undefined;

  // No "Reported <targetType>: <targetId>" entry: `subjectLabel` below is
  // built from the same two fields and is already shown in the collapsed row,
  // so it was the same string twice on the same card.
  const details = [`Reporter uid: ${row.reporterUid ?? "unknown"}`];

  if (row.description) {
    details.push(`Description: ${row.description}`);
  }

  if (row.resolutionNote) {
    details.push(`Resolution note: ${row.resolutionNote}`);
  }

  details.push(
    "Sanitized report — no location, credentials, or profile data included",
  );

  const statusValues = ["pending", "reviewing", "resolved", "dismissed"];
  const status = statusValues.includes(row.resolutionStatus)
    ? (row.resolutionStatus as ExceptionCase["status"])
    : "pending";

  return {
    id: row.id,
    type,
    severity: toReportSeverity(row.reason),
    summary: row.reason
      ? `Report: ${row.reason}`
      : "User report awaiting review",
    source: toReportSource(row.source),
    status,
    createdAt: row.createdAt ?? EPOCH_ISO,
    subjectLabel: `${row.targetType ?? "Target"} ${row.targetId ?? ""}`.trim(),
    details,
    sanitized: true,
    reporterUid: row.reporterUid ?? undefined,
    targetType,
    targetId: row.targetId ?? undefined,
    reason: row.reason ?? undefined,
  };
}

// Resolves a reported feed post's author uid for the Exception Queue's
// "Suspend user" action. `reports` never stores it (see mapReport() above),
// so this reads feedPosts/{postId}.authorUid directly, falling back to
// whatever a prior moderation removal recorded on its own command document
// once the post itself is gone. Returns null — never throws — when neither
// source resolves, so a single unresolvable case cannot fail the whole
// queue load.
async function resolveFeedPostAuthorUid(postId: string): Promise<string | null> {
  const fromPost = await getFeedPostAuthorUid(postId);
  if (fromPost) {
    return fromPost;
  }

  return getModerationCommandRemovedAuthorUid(postId);
}

export async function getLiveExceptionCases(): Promise<ExceptionCase[]> {
  const rows = await listReports();

  // Repeat-offender / repeat-report signal: count OTHER reports sharing the
  // same targetId, computed in-memory from the report set this call already
  // fetched. Deliberately not a second Firestore query or composite index.
  const targetIdCounts = new Map<string, number>();
  for (const row of rows) {
    if (!row.targetId) {
      continue;
    }
    targetIdCounts.set(row.targetId, (targetIdCounts.get(row.targetId) ?? 0) + 1);
  }

  const cases = await Promise.all(
    rows.map(async (row) => {
      const exceptionCase = mapReport(row);
      const duplicateReportCount = row.targetId
        ? Math.max(0, (targetIdCounts.get(row.targetId) ?? 1) - 1)
        : undefined;

      if (exceptionCase.type !== "reported-feed-post" || !row.targetId) {
        return { ...exceptionCase, duplicateReportCount };
      }

      const authorUid = await resolveFeedPostAuthorUid(row.targetId);

      return {
        ...exceptionCase,
        duplicateReportCount,
        ...(authorUid ? { authorUid } : {}),
      };
    }),
  );

  return cases.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

// Unresolved is defined by exclusion, deliberately matching
// TERMINAL_RESOLUTION_STATUSES in functions/src/moderation/staleReportSweep.ts:
// only "resolved" and "dismissed" are terminal, so anything else — including
// "reviewing" and a missing field, which mapReportRow() already reads as
// "pending" — still needs a human.
//
// This used to count `resolutionStatus === "pending"` alone, which meant a
// case the console had moved to "reviewing" vanished from the Overview's
// unresolved figure while the backend sweep kept aging it toward escalation.
// The console reported handled, the backend reported outstanding, and the
// same report was both.
const TERMINAL_RESOLUTION_STATUSES: ReadonlySet<string> = new Set([
  "resolved",
  "dismissed",
]);

export async function getLiveUnresolvedReportCount(): Promise<number> {
  const rows = await listReports();
  return rows.filter(
    (row) => !TERMINAL_RESOLUTION_STATUSES.has(row.resolutionStatus),
  ).length;
}

// --- feedback ----------------------------------------------------------------

const FEEDBACK_CATEGORIES: FeedbackCategory[] = [
  "bug",
  "plan issue",
  "billing",
  "abuse",
  "other",
];

function toFeedbackCategory(value: string | null): FeedbackCategory {
  return FEEDBACK_CATEGORIES.includes(value as FeedbackCategory)
    ? (value as FeedbackCategory)
    : "other";
}

const FEEDBACK_STATUSES: FeedbackStatus[] = [
  "new",
  "responded",
  "resolved",
  "dismissed",
  "escalated",
];

function toFeedbackStatus(value: string | null): FeedbackStatus {
  return FEEDBACK_STATUSES.includes(value as FeedbackStatus)
    ? (value as FeedbackStatus)
    : "new";
}

const SEVERITIES: Severity[] = ["low", "medium", "high", "critical"];

function toFeedbackSeverity(value: string | null): Severity {
  return SEVERITIES.includes(value as Severity) ? (value as Severity) : "low";
}

// Server always writes a pre-truncated `summary` (120 chars), but this
// derives a fallback from the raw `message` so a row missing `summary` (e.g.
// an older or hand-seeded doc) still renders something readable.
function summarizeFeedbackMessage(message: string | null): string {
  if (!message) {
    return "";
  }

  const collapsed = message.replace(/\s+/g, " ").trim();
  if (collapsed.length <= 120) {
    return collapsed;
  }

  return `${collapsed.slice(0, 120)}…`;
}

function mapFeedback(row: FeedbackRow): FeedbackItem {
  return {
    id: row.id,
    category: toFeedbackCategory(row.category),
    summary: row.summary ?? summarizeFeedbackMessage(row.message),
    severity: toFeedbackSeverity(row.severity),
    duplicateCount: row.duplicateCount ?? 1,
    status: toFeedbackStatus(row.status),
    receivedAt: row.receivedAt ?? EPOCH_ISO,
    note: row.note ?? "",
    closed: row.closed,
  };
}

export async function getLiveFeedbackItems(): Promise<FeedbackItem[]> {
  const rows = await listFeedback();
  return rows.map(mapFeedback);
}

// --- error groups --------------------------------------------------------------

const ERROR_STATUSES: ErrorStatus[] = [
  "new",
  "investigating",
  "resolved",
  "ignored",
];

function toErrorStatus(value: string | null): ErrorStatus {
  return ERROR_STATUSES.includes(value as ErrorStatus)
    ? (value as ErrorStatus)
    : "new";
}

function toErrorSeverity(value: string | null): Severity {
  return SEVERITIES.includes(value as Severity) ? (value as Severity) : "low";
}

// Coerces the raw stored `source` value into the narrow "mobile" | "functions"
// union, the same way toErrorStatus()/toErrorSeverity() coerce their fields:
// an unrecognized stored value is not trusted, it falls back to the default.
// A missing field (every errorGroups document written before this feature
// shipped) and any unexpected value both default to "mobile" rather than
// "functions" — undefined is never returned, and mobile is the pre-existing,
// higher-volume source so it is the safer default to assume.
function toErrorSource(value: string | null): ErrorGroup["source"] {
  return value === "functions" ? "functions" : "mobile";
}

function mapErrorGroup(row: ErrorGroupRow): ErrorGroup {
  return {
    id: row.id,
    title: row.title ?? "Untitled error",
    screen: row.screen ?? "unknown",
    appVersion: row.appVersion ?? "unknown",
    os: row.os ?? "unknown",
    source: toErrorSource(row.source),
    occurrences: row.occurrences ?? 0,
    affectedUsers: row.affectedUsers ?? 0,
    severity: toErrorSeverity(row.severity),
    status: toErrorStatus(row.status),
    firstSeenAt: row.firstSeenAt ?? EPOCH_ISO,
    lastSeenAt: row.lastSeenAt ?? EPOCH_ISO,
    stackSummary: row.stackSummary ?? "",
    sanitized: row.sanitized,
    note: row.note ?? "",
  };
}

export async function getLiveErrorGroups(): Promise<ErrorGroup[]> {
  const rows = await listErrorGroups();
  return rows.map(mapErrorGroup);
}

// --- admin notifications (overview attention items) -------------------------

function toNotificationSeverity(value: string | null): Severity {
  return SEVERITIES.includes(value as Severity) ? (value as Severity) : "low";
}

function mapAttentionItem(row: AdminNotificationRow): AttentionItem {
  return {
    id: row.id,
    title: row.title ?? "Untitled notification",
    detail: row.detail ?? "",
    severity: toNotificationSeverity(row.severity),
    href: row.href ?? "/admin",
  };
}

export async function getLiveAttentionItems(): Promise<AttentionItem[]> {
  const rows = await listAdminNotifications();
  return rows.map(mapAttentionItem);
}

// --- audit logs ----------------------------------------------------------------

// Audit rows store an action name, not a category; the category is derived
// here so the filter can group them.
//
// This used to compare `action` against the category names themselves
// ("subscription-change", "rule-activation", "backend-job"). No writer has ever
// emitted those strings — they came from the mock dataset this console was
// first built against, and every real writer uses a dotted namespace instead.
// So four of the six filters could never match, and 144 of the 146 live rows
// fell into "admin-action", which made the filter close to useless. The events
// were being logged correctly the whole time; only the grouping was wrong.
//
// Matching is on prefix so a new action inside an existing namespace is
// classified without touching this function. Order matters: `user.backfill.`
// is a backend job even though it is under `user.`.
function toAuditCategory(action: string | null): AuditCategory {
  if (!action) {
    return "admin-action";
  }

  // Role grants, the one category whose writer already matched literally.
  if (action === "role-change") {
    return "role-change";
  }

  // Automated work with no admin behind it: the stale-report sweep, the
  // auto-hide trigger, and the one-off data backfills.
  if (
    action.startsWith("user.backfill.") ||
    action.startsWith("moderation.stale-reports.") ||
    action.startsWith("moderation.report-auto-hide.")
  ) {
    return "backend-job";
  }

  // Tier movement, whether an admin set it or the expiry job cleared it.
  // `user.subscription.expire` is written by a scheduled function, so it is
  // also arguably a backend job; it is classified by what changed rather than
  // by who ran it, which is what someone filtering this column is looking for.
  if (action.startsWith("user.subscription.")) {
    return "subscription-change";
  }

  // Every config/* document the console can publish: progression, leaderboard,
  // paywall, featureAccess, characterAccess, challengeAccess, automation and
  // site content. These are the rule sets the platform runs on.
  if (action.startsWith("config.")) {
    return "rule-activation";
  }

  // account-status-change, report-resolution, feedback-*, error-triage,
  // documents.*, newsletter.*, leaderboard.*, user.progression.*, user.avatar.*
  // and anything new.
  return "admin-action";
}

function mapAuditRow(row: AuditLogRow): AuditEntry {
  return {
    id: row.id,
    actor: row.actor ?? "system",
    action: row.detail ?? row.action ?? "Recorded action",
    target: `${row.targetType ?? ""} ${row.targetId ?? ""}`.trim() || "unknown",
    category: toAuditCategory(row.action),
    timestamp: row.createdAt ?? EPOCH_ISO,
  };
}

export async function getLiveAuditLog(): Promise<AuditEntry[]> {
  const rows = await listAuditLogs();
  return rows.map(mapAuditRow);
}

export async function getLiveUserActionHistory(): Promise<
  AdminActionLogEntry[]
> {
  const rows = await listAuditLogs();
  return rows
    .filter((row) => row.targetType === "user")
    .map((row) => ({
      id: row.id,
      actor: row.actor ?? "system",
      action: row.detail ?? row.action ?? "Recorded action",
      target: row.targetId ?? "unknown",
      timestamp: row.createdAt ?? EPOCH_ISO,
    }));
}

// --- overview ------------------------------------------------------------------

// Every stat below now reads a real backend source: the first four are
// unchanged, and critical-errors/failed-jobs (previously mock-only) are
// derived from errorGroups and the leaderboard aggregation job respectively.
export async function getLiveOverviewStats(): Promise<OverviewStat[]> {
  const now = Date.now();
  const since = new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString();

  const [
    unresolvedReports,
    userCount,
    subscriptions,
    recentRuns,
    errorGroups,
    job,
  ] =
    await Promise.all([
      getLiveUnresolvedReportCount(),
      countUsers(),
      countUsersBySubscription(),
      countActivitiesSince(since),
      // Scoped fallback: a flaky errorGroups read only zeroes the
      // critical-errors stat below, rather than rejecting the whole
      // Promise.all and degrading every unrelated stat to mock.
      listErrorGroups().catch(() => []),
      getLiveAggregationJob().catch(() => null),
    ]);

  const stats: OverviewStat[] = [
    {
      id: "unresolved-reports",
      label: "Unresolved reports",
      value: unresolvedReports,
      hint: "Awaiting human review",
      tone: unresolvedReports > 0 ? "accent" : "neutral",
      href: "/admin/exceptions",
    },
    // No second "Pending exception cases" card. It rendered the same
    // unresolved-report figure as the card above under a different label, and
    // its "Escalated by automation" hint described the stale-report sweep's
    // adminNotifications output — which the Overview's own "Attention needed"
    // panel already surfaces, with the actual items rather than a count.
    {
      id: "registered-users",
      label: "Registered users",
      value: userCount,
      hint: `${subscriptions.premium} premium · ${subscriptions.basic} basic`,
      tone: "neutral",
      href: "/admin/users",
    },
    {
      id: "recent-runs",
      label: "Runs recorded (30 days)",
      value: recentRuns,
      hint: "Backend-reported",
      tone: "neutral",
    },
  ];

  const criticalNew = errorGroups.filter(
    (group) =>
      group.severity === "critical" &&
      group.status === "new" &&
      isWithinLast24h(group.lastSeenAt, now),
  ).length;

  stats.push({
    id: "critical-errors",
    label: "Critical app errors today",
    value: criticalNew,
    hint: "New crash groups",
    tone: criticalNew > 0 ? "critical" : "neutral",
    href: "/admin/errors",
  });

  // getLiveAggregationJob() maps a failed lock or an expired running-lease
  // ("stuck run") to status "down" — see its own status derivation above.
  const failed = job?.status === "down" ? 1 : 0;

  stats.push({
    id: "failed-jobs",
    label: "Failed backend jobs",
    value: failed,
    hint: "Last 24 hours",
    tone: failed > 0 ? "critical" : "neutral",
    href: "/admin/audit",
  });

  return stats;
}

// Builds the System Status panel from four independent, real backend probes.
// Every component shares a single `lastCheckedAt` (the instant this function
// ran), since all four checks are read together in one call.
export async function getLiveSystemHealth(): Promise<SystemHealthComponent[]> {
  const now = Date.now();
  const nowIso = new Date(now).toISOString();

  // A null result means the errorGroups read itself failed (not that there
  // are no error groups). In that case the two error-derived components below
  // report `degraded` (health unknown) rather than optimistically
  // "operational" — we cannot judge error volume when we could not read it.
  const groups = await listErrorGroups().catch(() => null);
  const errorGroupsUnavailable = groups === null;
  const safeGroups = groups ?? [];

  // A trivial config/progression read as a Firestore reachability probe: if
  // Firestore itself is unreachable this throws, and any other read in this
  // module would too.
  let firestoreStatus: SystemStatus;
  try {
    await getConfigDoc("progression");
    firestoreStatus = "operational";
  } catch {
    firestoreStatus = "down";
  }

  // Reuses the same aggregation-job derivation the overview's failed-jobs
  // stat and the Leaderboard Oversight page rely on, so all three surfaces
  // agree on what "the aggregation job is unhealthy" means.
  const job = await getLiveAggregationJob().catch(() => null);
  const aggregationStatus: SystemStatus = job ? job.status : "degraded";

  // Account-deletion health is derived from STATE, not from a recent-error
  // window like the two components below. A failed erase means a runner who
  // asked to be deleted still has data in Firestore, and nothing retries it —
  // so the badge has to stay lit until an operator actually clears it, however
  // long that takes. Reading this off Cloud Functions error groups (which are
  // scoped to 24h) is what let two real deletions sit failed for a week.
  const deletionCommands = await listAccountDeletionCommands().catch(() => null);
  let accountDeletionStatus: SystemStatus;
  if (deletionCommands === null) {
    accountDeletionStatus = "degraded";
  } else if (deletionCommands.some((command) => command.status === "failed")) {
    accountDeletionStatus = "down";
  } else if (
    // "pending"/"erasing" past the stall window is a fan-out that started and
    // never finished. A healthy run completes in seconds, so an hour is
    // generous rather than borderline.
    deletionCommands.some(
      (command) =>
        command.status !== "completed" &&
        command.requestedAt !== null &&
        now - Date.parse(command.requestedAt) > 60 * 60 * 1000,
    )
  ) {
    accountDeletionStatus = "degraded";
  } else {
    accountDeletionStatus = "operational";
  }

  const recentFunctionsGroups = safeGroups.filter(
    (group) => group.source === "functions" && isWithinLast24h(group.lastSeenAt, now),
  );
  let cloudFunctionsStatus: SystemStatus;
  if (errorGroupsUnavailable) {
    cloudFunctionsStatus = "degraded";
  } else if (recentFunctionsGroups.some((group) => group.severity === "critical")) {
    cloudFunctionsStatus = "down";
  } else if (recentFunctionsGroups.some((group) => group.severity === "high")) {
    cloudFunctionsStatus = "degraded";
  } else {
    cloudFunctionsStatus = "operational";
  }

  const hasRecentCriticalError = safeGroups.some(
    (group) => group.severity === "critical" && isWithinLast24h(group.lastSeenAt, now),
  );
  const appErrorRateStatus: SystemStatus =
    errorGroupsUnavailable || hasRecentCriticalError ? "degraded" : "operational";

  return [
    {
      id: "firestore",
      name: "Firestore",
      description: "Primary application datastore",
      status: firestoreStatus,
      lastCheckedAt: nowIso,
    },
    {
      id: "leaderboard-aggregation",
      name: "Monthly leaderboard aggregation job",
      description: "Aggregates monthly and territory standings",
      status: aggregationStatus,
      lastCheckedAt: nowIso,
    },
    {
      id: "account-deletion",
      name: "Account deletion queue",
      description: "Erases the data of runners who asked to be deleted",
      status: accountDeletionStatus,
      lastCheckedAt: nowIso,
    },
    {
      id: "cloud-functions",
      name: "Cloud Functions",
      description: "Rule execution and background jobs",
      status: cloudFunctionsStatus,
      lastCheckedAt: nowIso,
    },
    {
      id: "app-error-rate",
      name: "App error rate",
      description: "Critical crash groups in the last 24 hours",
      status: appErrorRateStatus,
      lastCheckedAt: nowIso,
    },
  ];
}

// Decrements a "YYYY-MM" key by one month, rolling the year back at January.
function previousMonthKey(monthKey: string): string {
  const [yearStr, monthStr] = monthKey.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);

  return month === 1
    ? `${year - 1}-12`
    : `${year}-${String(month - 1).padStart(2, "0")}`;
}

// Short English month name for a "YYYY-MM" key, e.g. "2026-07" -> "Jul".
function monthKeyLabel(monthKey: string): string {
  const [yearStr, monthStr] = monthKey.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);

  return new Date(Date.UTC(year, month - 1, 1)).toLocaleString("en-GB", {
    month: "short",
    timeZone: "UTC",
  });
}

// Monthly active-user counts for the last MAU_TREND_MONTHS months (oldest to
// newest), ending at the current leaderboard period. Each point's
// `activeUsers` is the count of distinct activity owners within that
// Singapore-month window — see listActivityOwnerUidsInWindow() in
// src/lib/firebase/firestore.ts. A month whose window fails to parse (should
// not happen for a real "YYYY-MM" key) contributes 0 rather than throwing.
export async function getLiveActiveUsersTrend(): Promise<ActiveUsersPoint[]> {
  const period = await getLeaderboardCurrentPeriod().catch(() => null);
  const currentKey = period?.periodKey ?? currentSingaporeMonthKey(new Date());

  const monthKeys: string[] = [currentKey];
  for (let i = 1; i < MAU_TREND_MONTHS; i += 1) {
    monthKeys.unshift(previousMonthKey(monthKeys[0]));
  }

  const points: ActiveUsersPoint[] = [];
  for (const monthKey of monthKeys) {
    const window = singaporeMonthWindow(monthKey);
    const activeUsers = window
      ? (
          await listActivityOwnerUidsInWindow(
            window.startIso,
            window.endIso,
            MAU_SCAN_CAP,
          )
        ).length
      : 0;

    points.push({ label: monthKeyLabel(monthKey), activeUsers });
  }

  return points;
}

// --- leaderboard -----------------------------------------------------------------

// The monthly leaderboard aggregation Cloud Function runs on a fixed
// schedule, independent of the per-period `refreshesAt` (month-rollover)
// boundary stored on the snapshot. Source of truth:
// functions/src/leaderboard/monthlyLeaderboard.ts.
const LEADERBOARD_REFRESH_INTERVAL_MINUTES = 60;

// Builds the aggregation-job card from the current period document (a single
// small read) and its matching aggregation lock when one exists.
//
// Prefers leaderboardPeriods/monthly_current — a single document carrying
// generatedAt/periodKey/periodLabel/buildId — over the previous approach of
// fetching the ENTIRE leaderboardSnapshots collection and sorting in memory
// just to learn when the job last ran. With 37 regions x 10 tiers x 3
// retained months that scan could read up to ~1,100 documents, each carrying
// up to 10 entries. The old full-collection scan (getLatestLeaderboardSnapshot())
// is kept only as a fallback for a database that has never had a period
// document written (e.g. very old hand-seeded data predating
// leaderboardPeriods). Returns null when neither source has anything, so the
// caller can degrade to the mock card.
export async function getLiveAggregationJob(): Promise<AggregationJob | null> {
  const period = await getLeaderboardCurrentPeriod();

  let periodKey: string | null;
  let periodLabel: string | null;
  let buildId: string | null;
  let generatedAtIso: string;

  if (period && period.generatedAt) {
    periodKey = period.periodKey;
    periodLabel = period.periodLabel;
    buildId = period.buildId;
    generatedAtIso = period.generatedAt;
  } else {
    // Fallback path only: no leaderboardPeriods/monthly_current document
    // exists yet, so fall back to scanning leaderboardSnapshots.
    const snapshot = await getLatestLeaderboardSnapshot();

    if (!snapshot || !snapshot.generatedAt) {
      return null;
    }

    periodKey = snapshot.periodKey;
    periodLabel = snapshot.periodLabel;
    buildId = snapshot.buildId;
    generatedAtIso = snapshot.generatedAt;
  }

  const lastRun = new Date(generatedAtIso);
  const nextRun = new Date(
    lastRun.getTime() + LEADERBOARD_REFRESH_INTERVAL_MINUTES * 60 * 1000,
  );
  const name = `Monthly leaderboard aggregation (${periodLabel ?? periodKey ?? "current period"})`;

  const lock = periodKey ? await getLeaderboardAggregationLock(periodKey) : null;

  if (!lock) {
    // A period/snapshot exists but no lock document has ever been recorded
    // for this period (e.g. hand-seeded data). Do not invent a duration or a
    // healthy status.
    return {
      name,
      lastRunAt: lastRun.toISOString(),
      durationSeconds: 0,
      status: "degraded",
      nextRunAt: nextRun.toISOString(),
      periodKey,
      buildId,
      startedAt: null,
      staleLease: false,
    };
  }

  const leaseExpired =
    lock.status === "running" &&
    lock.leaseExpiresAt !== null &&
    new Date(lock.leaseExpiresAt).getTime() < Date.now();

  let status: SystemStatus;
  if (leaseExpired) {
    // Claimed a lease and never released it — a stuck run, not a merely
    // in-progress one.
    status = "down";
  } else if (lock.status === "completed") {
    status = "operational";
  } else if (lock.status === "failed") {
    status = "down";
  } else if (lock.status === "running") {
    status = "degraded";
  } else {
    status = "degraded";
  }

  const durationSeconds =
    lock.status === "completed" && lock.startedAt && lock.completedAt
      ? Math.round(
          (new Date(lock.completedAt).getTime() -
            new Date(lock.startedAt).getTime()) /
            1000,
        )
      : 0;

  return {
    name,
    lastRunAt: lastRun.toISOString(),
    durationSeconds,
    status,
    nextRunAt: nextRun.toISOString(),
    periodKey: lock.periodKey,
    buildId: lock.buildId ?? buildId,
    startedAt: lock.startedAt,
    staleLease: leaseExpired,
  };
}

// Reads leaderboardPeriods/monthly_current — the entry point the mobile app
// reads first. Returns null when the document does not exist so the caller
// can degrade rather than invent a period.
export async function getLiveLeaderboardCurrentPeriod(): Promise<LeaderboardCurrentPeriod | null> {
  const row = await getLeaderboardCurrentPeriod();

  if (!row) {
    return null;
  }

  return {
    periodKey: row.periodKey,
    periodLabel: row.periodLabel,
    timezone: row.timezone,
    refreshesAt: row.refreshesAt,
    buildId: row.buildId,
    generatedAt: row.generatedAt,
    aggregationStatus: row.aggregationStatus,
  } satisfies LeaderboardCurrentPeriod;
}

// Per-status counts over leaderboardCurrentViews, via
// countLeaderboardCurrentViewsByStatus()'s .count() aggregate queries rather
// than reading every document (one per user).
// The user count rides along as a second .count() aggregate rather than a
// second page fetch because the breakdown is meaningless on its own: every
// status here is conditional on already having run, so "2 ranked" reads as
// either total success or total failure depending on whether the app has 2
// accounts or 2000.
export async function getLiveLeaderboardParticipation(): Promise<LeaderboardParticipationBreakdown> {
  const [counts, registeredUsers] = await Promise.all([
    countLeaderboardCurrentViewsByStatus(),
    countUsers(),
  ]);

  return {
    ranked: counts.ranked,
    unranked: counts.unranked,
    regionRequired: counts.region_required,
    ineligiblePremium: counts.ineligible_premium,
    ineligibleMinRuns: counts.ineligible_min_runs,
    total:
      counts.ranked +
      counts.unranked +
      counts.region_required +
      counts.ineligible_premium +
      counts.ineligible_min_runs,
    registeredUsers,
  } satisfies LeaderboardParticipationBreakdown;
}

// Aggregate coverage over every leaderboardSnapshots document (index
// metadata only, via listLeaderboardSnapshotSummaries() — no topEntries):
// how many snapshots exist, how much of the region x division grid they
// cover, total ranked entries, and which period keys still have data.
export async function getLiveLeaderboardCoverage(): Promise<LeaderboardCoverageSummary> {
  const rows = await listLeaderboardSnapshotSummaries();

  const regions = new Set<string>();
  const divisions = new Set<string>();
  const periodKeys = new Set<string>();
  let totalEntries = 0;
  let snapshotCount = 0;

  for (const row of rows) {
    // Count only documents the aggregation job actually produced. A stray or
    // legacy doc in this collection (no periodKey) would otherwise inflate
    // the headline number, which is the opposite of what this panel is for:
    // an admin reads it to notice that regions are MISSING, so padding it
    // hides exactly the gap they are looking for.
    if (row.periodKey === null) {
      continue;
    }
    snapshotCount += 1;
    periodKeys.add(row.periodKey);
    if (row.regionId !== null) {
      regions.add(row.regionId);
    }
    if (row.divisionKey !== null) {
      divisions.add(row.divisionKey);
    }
    totalEntries += row.entryCount ?? 0;
  }

  return {
    snapshotCount,
    regionsCovered: regions.size,
    divisionsCovered: divisions.size,
    totalEntries,
    periodKeys: [...periodKeys].sort((left, right) => right.localeCompare(left)),
  } satisfies LeaderboardCoverageSummary;
}

// --- backend config (config/progression, config/leaderboard, config/featureAccess) --
//
// These read the same `config/{name}` documents the Cloud Functions runtime
// loads (functions/src/config/configLoader.ts) via the shared
// deepMerge/validate helpers in ./config-validation.ts, so an admin previewing
// this data sees exactly what the backend will actually apply: stored partial
// overrides merged over the defaults, falling back to defaults entirely when
// the doc is absent or fails validation.

export async function getLiveProgressionConfig(): Promise<ProgressionConfig> {
  const stored = await getConfigDoc("progression");

  if (stored === null) {
    return DEFAULT_PROGRESSION_CONFIG;
  }

  const merged = deepMerge(DEFAULT_PROGRESSION_CONFIG, stored);
  const result = validateProgressionConfig(merged);
  return result.valid ? merged : DEFAULT_PROGRESSION_CONFIG;
}

// Real change history for config/progression, derived from the admin audit log
// (newest first). The console never fabricates history: with no recorded saves
// this returns an empty list. Only the newest entry is the applied one.
export async function getLiveProgressionHistory(): Promise<ConfigVersionEntry[]> {
  const rows = await listConfigHistory("progression");

  return rows.map((row, index) => {
    const version = row.after?.version;

    return {
      id: row.id,
      version: typeof version === "number" ? version : null,
      actor: row.actor ?? "system",
      savedAt: row.createdAt ?? EPOCH_ISO,
      changedFields: row.changedFields,
      restored: (row.action ?? "").endsWith(".restore"),
      active: index === 0,
    } satisfies ConfigVersionEntry;
  });
}

// config/paywall — the mobile app's premium upsell sheet copy. Unlike the
// other config docs this one is read directly by signed-in app clients
// (firestore.rules carves out read access for exactly this doc); merge is the
// shared paywall-config module, mirroring the mobile reader's coercion.
export async function getLivePaywallConfig(): Promise<PaywallConfig> {
  const stored = await getConfigDoc("paywall");

  if (stored === null) {
    return DEFAULT_PAYWALL_CONFIG;
  }

  const merged = mergePaywallConfig(stored);
  const result = validatePaywallConfig(merged);
  return result.valid ? merged : DEFAULT_PAYWALL_CONFIG;
}

export async function getLivePaywallHistory(): Promise<ConfigVersionEntry[]> {
  const rows = await listConfigHistory("paywall");

  return rows.map((row, index) => {
    const version = row.after?.version;

    return {
      id: row.id,
      version: typeof version === "number" ? version : null,
      actor: row.actor ?? "system",
      savedAt: row.createdAt ?? EPOCH_ISO,
      changedFields: row.changedFields,
      restored: (row.action ?? "").endsWith(".restore"),
      active: index === 0,
    } satisfies ConfigVersionEntry;
  });
}

export async function getLiveLeaderboardConfig(): Promise<LeaderboardConfig> {
  const stored = await getConfigDoc("leaderboard");

  if (stored === null) {
    return DEFAULT_LEADERBOARD_CONFIG;
  }

  const merged = deepMerge(DEFAULT_LEADERBOARD_CONFIG, stored);
  const result = validateLeaderboardConfig(merged);
  return result.valid ? merged : DEFAULT_LEADERBOARD_CONFIG;
}

export async function getLiveFeatureAccessConfig(): Promise<FeatureAccessConfig> {
  const stored = await getConfigDoc("featureAccess");

  if (stored === null) {
    return DEFAULT_FEATURE_ACCESS_CONFIG;
  }

  const merged = deepMerge(DEFAULT_FEATURE_ACCESS_CONFIG, stored);
  const result = validateFeatureAccessConfig(merged);
  return result.valid ? merged : DEFAULT_FEATURE_ACCESS_CONFIG;
}

export async function getLiveAutomationConfig(): Promise<AutomationConfig> {
  const stored = await getConfigDoc("automation");

  if (stored === null) {
    return DEFAULT_AUTOMATION_CONFIG;
  }

  const merged = deepMerge(DEFAULT_AUTOMATION_CONFIG, stored);
  const result = validateAutomationConfig(merged);
  return result.valid ? merged : DEFAULT_AUTOMATION_CONFIG;
}

export async function getLiveChallengeAccessConfig(): Promise<ChallengeAccessConfig> {
  const stored = await getConfigDoc("challengeAccess");

  if (stored === null) {
    return DEFAULT_CHALLENGE_ACCESS_CONFIG;
  }

  const merged = deepMerge(DEFAULT_CHALLENGE_ACCESS_CONFIG, stored);
  const result = validateChallengeAccessConfig(merged);
  return result.valid ? merged : DEFAULT_CHALLENGE_ACCESS_CONFIG;
}

export async function getLiveCharacterAccessConfig(): Promise<CharacterAccessConfig> {
  const stored = await getConfigDoc("characterAccess");

  if (stored === null) {
    return DEFAULT_CHARACTER_ACCESS_CONFIG;
  }

  const merged = deepMerge(DEFAULT_CHARACTER_ACCESS_CONFIG, stored);
  const result = validateCharacterAccessConfig(merged);
  return result.valid ? merged : DEFAULT_CHARACTER_ACCESS_CONFIG;
}

// Derives the admin console's flat XpRule rows from the structured
// progression config. Kept separate from getLiveProgressionConfig so callers
// that only need the config object (e.g. a future progression-config editor)
// are not forced through the XpRule view shape.
export function mapProgressionConfigToXpRules(config: ProgressionConfig): XpRule[] {
  return [
    {
      id: "xp-base-completion",
      action: "Complete an activity",
      description: "Base XP awarded when an activity is completed",
      xp: config.baseCompletionXp,
    },
    {
      id: "xp-per-kilometer",
      action: "Distance covered",
      description: "XP awarded per kilometer of distance",
      xp: config.xpPerKilometer,
    },
    {
      id: "xp-per-ten-active-minutes",
      action: "Active minutes",
      description: "XP awarded per ten minutes of active running time",
      xp: config.xpPerTenActiveMinutes,
    },
    {
      id: "xp-plan-completion-bonus",
      action: "Complete an assigned plan",
      description: "Bonus XP awarded when a plan is completed",
      xp: config.planCompletionBonusXp,
    },
  ];
}

// Derives cumulative level thresholds from the progression config's
// level-up XP increments. Delegates to the shared level-curve module
// (src/lib/admin/level-curve.ts), which mirrors levelThresholds() in
// functions/src/progression/progressionCalculator.ts: each increment governs
// a 10-level band (not a single level-up), and the last increment is reused
// for every level beyond the last band once levelIncrements runs out.
export function mapProgressionConfigToLevelThresholds(
  config: ProgressionConfig,
): LevelThreshold[] {
  const thresholds = computeLevelThresholds(config.levelIncrements, config.maxLevel);

  return thresholds.map((xpRequired, index) => ({
    level: index + 1,
    xpRequired,
  }));
}

export async function getLiveXpRules(): Promise<XpRule[]> {
  return mapProgressionConfigToXpRules(await getLiveProgressionConfig());
}

export async function getLiveLevelThresholds(): Promise<LevelThreshold[]> {
  return mapProgressionConfigToLevelThresholds(await getLiveProgressionConfig());
}

export async function getLiveLeaderboardSettings(): Promise<LeaderboardSettings> {
  const config = await getLiveLeaderboardConfig();

  return {
    seasonLengthDays: config.seasonLengthDays,
    // No backend field for regional grouping yet; default to off rather than
    // invent a value the backend does not actually enforce.
    regionalGrouping: false,
    minRunsToQualify: config.minRunsToQualify,
  };
}

// --- suspicious-activity detection (leaderboardContributions, activities) --
//
// Every rule below is a deterministic transform of real Firestore documents
// — no score, count, or timestamp is invented. The admin console never
// computes or writes real XP/leaderboard state; this only
// *reads* it and flags statistically or physically implausible patterns for
// a human to review via the Exception Queue (createLeaderboardReport() in
// src/lib/firebase/firestore.ts, wired up by flagLeaderboardScore() in
// src/lib/actions/admin.ts).

// A cohort (same regionId x divisionKey) needs at least this many peers
// before "outlier" is statistically meaningful. Flagging inside a cohort of
// 1-2 runners would just be flagging whoever happens to run the most.
const MIN_COHORT_SIZE = 5;

// Modified z-score threshold, in the spirit of Iglewicz & Hoya's robust
// outlier rule: z = (x - median) / (a normal-consistent scale derived from
// the median absolute deviation). The commonly cited cutoff is 3.5; this
// uses a more conservative 5 because Runiac cohorts are small (tens of
// runners, not thousands) and noisier than a typical statistical sample, and
// a false anomaly flag routes a real runner into a fraud-review queue.
const OUTLIER_Z_THRESHOLD = 5;

// Sustained pace faster than this is treated as physically implausible for
// any real GPS-tracked run. The men's marathon world record (Kelvin Kiptum,
// Chicago 2023) is 2:00:35 for 42.195 km, ~171 seconds/km (2:51/km). 120
// seconds/km (2:00/km) sustained is well below even elite pace, so a run
// this "fast" is far more likely to be a GPS/data error or synthetic data
// than a genuine athlete.
const IMPLAUSIBLE_PACE_SECONDS_PER_KM = 120;

// How many activities to scan for the implausible-pace signal — large enough
// to cover realistic per-period volumes without an unbounded collection read.
// The scan is bounded to the leaderboard period's own window and ordered
// newest-first (see singaporeMonthWindow() below and listActivitySummaries()
// in src/lib/firebase/firestore.ts), so this caps the newest 500 activities
// *within the period* rather than an arbitrary 500 documents.
const ACTIVITY_SCAN_LIMIT = 500;

// UTC instants bounding a Singapore-month period key ("2026-07"), matching
// nextSingaporeMonthStart() in
// functions/src/leaderboard/monthlyLeaderboardPeriod.ts: a period starts at
// 00:00 SGT on the 1st (16:00 UTC the previous day) and ends at the same
// instant the following month. `activities.startedAt` is stored as a
// validated ISO-8601 string (functions/src/run/validateRunPayload.ts), so
// these bounds are string-comparable in a Firestore range query.
function singaporeMonthWindow(
  periodKey: string,
): { startIso: string; endIso: string } | null {
  const match = /^(\d{4})-(\d{2})$/.exec(periodKey);

  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);

  if (month < 1 || month > 12) {
    return null;
  }

  return {
    startIso: new Date(Date.UTC(year, month - 1, 0, 16, 0, 0, 0)).toISOString(),
    endIso: new Date(Date.UTC(year, month, 0, 16, 0, 0, 0)).toISOString(),
  };
}

function median(values: readonly number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[mid - 1] + sorted[mid]) / 2
    : sorted[mid];
}

// Robust, normal-consistent scale estimate for `values` around `med`, used
// as the denominator of a modified z-score. Prefers the median absolute
// deviation (MAD), scaled by 1.4826 for consistency with a normal
// distribution's standard deviation; falls back to the mean absolute
// deviation (scaled by 1.2533, the equivalent normal-consistency constant)
// only when the MAD itself is exactly 0 (more than half the cohort shares
// the exact median value). Returns null when both measures of spread are 0
// — a cohort with no variance at all has no meaningful "outlier".
function robustScale(values: readonly number[], med: number): number | null {
  const deviations = values.map((value) => Math.abs(value - med));
  const mad = median(deviations);

  if (mad > 0) {
    return mad * 1.4826;
  }

  const meanDeviation =
    deviations.reduce((sum, value) => sum + value, 0) / deviations.length;

  return meanDeviation > 0 ? meanDeviation * 1.2533 : null;
}

function formatMultipleOfMedian(value: number, med: number): string {
  if (med <= 0) {
    return `${formatNumber(Math.round(value))} against a cohort median of 0`;
  }
  return `${(value / med).toFixed(1)}×`;
}

function formatPace(secondsPerKm: number): string {
  const totalSeconds = Math.round(secondsPerKm);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}/km`;
}

function cohortKey(regionId: string | null, divisionKey: string | null): string {
  return `${regionId ?? "unknown-region"}::${divisionKey ?? "unknown-division"}`;
}

function cohortLabel(row: LeaderboardContributionRow): string {
  const region = row.regionLabel ?? row.regionId ?? "Unknown region";
  const division = row.divisionLabel ?? row.divisionKey ?? "Unknown division";
  return `${region} · ${division}`;
}

function contributionOwnerLabel(row: LeaderboardContributionRow): {
  user: string;
  region: string;
} {
  return {
    user: row.publicAlias ?? row.ownerUid ?? "Unknown runner",
    region: row.regionLabel ?? row.regionId ?? "Unknown region",
  };
}

// Sort key kept alongside each SuspiciousScore so the caller can rank
// findings most-severe-first across rules that are not otherwise
// comparable (a certain governance fact vs. a statistical guess).
// Not part of the public SuspiciousScore shape.
type ScoredFlag = { severity: number; score: SuspiciousScore };

// Shared cohort-relative robust-outlier shape for rule 1 (peer score
// outlier) and rule 2 (XP-per-run outlier): group by regionId x divisionKey,
// require MIN_COHORT_SIZE peers, then flag anything more than
// OUTLIER_Z_THRESHOLD modified-z-scores above the cohort median. Only the
// upper tail is checked — a suspiciously *low* score is not a fraud signal.
function detectCohortOutliers(
  contributions: readonly LeaderboardContributionRow[],
  kind: "score" | "xp-per-run",
  valueOf: (row: LeaderboardContributionRow) => number | null,
  describe: (
    row: LeaderboardContributionRow,
    value: number,
    med: number,
    cohortSize: number,
  ) => string,
): ScoredFlag[] {
  const cohorts = new Map<string, LeaderboardContributionRow[]>();

  for (const row of contributions) {
    if (valueOf(row) === null) {
      continue;
    }

    const key = cohortKey(row.regionId, row.divisionKey);
    const bucket = cohorts.get(key);
    if (bucket) {
      bucket.push(row);
    } else {
      cohorts.set(key, [row]);
    }
  }

  const flags: ScoredFlag[] = [];

  for (const cohort of cohorts.values()) {
    if (cohort.length < MIN_COHORT_SIZE) {
      continue;
    }

    const values = cohort.map((row) => valueOf(row) as number);
    const med = median(values);
    const scale = robustScale(values, med);

    if (scale === null) {
      continue;
    }

    for (const row of cohort) {
      const value = valueOf(row) as number;
      if (value <= med) {
        continue;
      }

      const z = (value - med) / scale;
      if (z <= OUTLIER_Z_THRESHOLD) {
        continue;
      }

      const { user, region } = contributionOwnerLabel(row);

      flags.push({
        severity: z,
        score: {
          id: `outlier-${kind}-${row.id}`,
          user,
          region,
          flaggedScore: row.scoreXp ?? 0,
          reason: describe(row, value, med, cohort.length),
          detectedAt: row.lastProgressionAt ?? EPOCH_ISO,
          ownerUid: row.ownerUid ?? "unknown",
          contributionId: row.id,
        },
      });
    }
  }

  return flags;
}

// Rule 1: a contribution's raw scoreXp is an extreme outlier within its
// region x division cohort.
function detectPeerScoreOutliers(
  contributions: readonly LeaderboardContributionRow[],
): ScoredFlag[] {
  return detectCohortOutliers(
    contributions,
    "score",
    (row) => row.scoreXp,
    (row, value, med, cohortSize) =>
      `Score ${formatNumber(Math.round(value))} XP is ${formatMultipleOfMedian(value, med)} the cohort median (${cohortSize} runners in ${cohortLabel(row)}).`,
  );
}

// Rule 2: scoreXp / qualifyingRunCount is an extreme outlier within its
// cohort. Contributions with a missing or zero qualifyingRunCount are
// excluded entirely (valueOf returns null) rather than divided by zero or
// treated as 1 run.
function detectXpPerRunOutliers(
  contributions: readonly LeaderboardContributionRow[],
): ScoredFlag[] {
  return detectCohortOutliers(
    contributions,
    "xp-per-run",
    (row) =>
      row.scoreXp !== null && row.qualifyingRunCount !== null && row.qualifyingRunCount > 0
        ? row.scoreXp / row.qualifyingRunCount
        : null,
    (row, value, med, cohortSize) =>
      `XP-per-run of ${value.toFixed(1)} (${row.qualifyingRunCount} qualifying runs) is ${formatMultipleOfMedian(value, med)} the cohort median XP-per-run (${cohortSize} runners in ${cohortLabel(row)}).`,
  );
}

// Rule 3: an activity whose distance/duration imply a physically impossible
// pace, or a zero/negative duration against a positive distance. Runs
// against `activities` directly (not leaderboardContributions), since a
// fabricated run can be implausible on its own terms regardless of how it
// later rolls up into a score. `detectedAt` is the activity's own
// startedAt (falling back to createdAt) — never "now" — and an activity with
// neither is skipped rather than reported with an invented time.
function detectImplausibleActivities(
  activities: readonly ActivitySummaryRow[],
  contributionByOwner: ReadonlyMap<string, LeaderboardContributionRow>,
): ScoredFlag[] {
  const flags: ScoredFlag[] = [];

  for (const activity of activities) {
    if (activity.ownerUid === null) {
      continue;
    }

    const distanceMeters = activity.distanceMeters;
    if (distanceMeters === null || distanceMeters <= 0) {
      continue;
    }

    const detectedAt = activity.startedAt ?? activity.createdAt;
    if (detectedAt === null) {
      continue;
    }

    const durationSeconds = activity.durationSeconds;
    const contribution = contributionByOwner.get(activity.ownerUid);
    const user = contribution?.publicAlias ?? activity.ownerUid;
    const region = contribution?.regionLabel ?? contribution?.regionId ?? "Unknown region";
    const flaggedScore = contribution?.scoreXp ?? 0;
    const distanceKm = distanceMeters / 1000;

    if (durationSeconds === null || durationSeconds <= 0) {
      flags.push({
        severity: 6000,
        score: {
          id: `implausible-duration-${activity.id}`,
          user,
          region,
          flaggedScore,
          reason: `Activity records ${distanceKm.toFixed(2)} km with a zero or negative duration (${durationSeconds ?? "missing"}s) — physically impossible.`,
          detectedAt,
          ownerUid: activity.ownerUid,
          contributionId: activity.id,
        },
      });
      continue;
    }

    const paceSecondsPerKm = durationSeconds / distanceKm;
    if (paceSecondsPerKm >= IMPLAUSIBLE_PACE_SECONDS_PER_KM) {
      continue;
    }

    flags.push({
      severity: 5000 + (IMPLAUSIBLE_PACE_SECONDS_PER_KM - paceSecondsPerKm),
      score: {
        id: `implausible-pace-${activity.id}`,
        user,
        region,
        flaggedScore,
        reason: `Activity implies a sustained pace of ${formatPace(paceSecondsPerKm)} over ${distanceKm.toFixed(2)} km — faster than the marathon world record pace (~2:51/km) and physically implausible.`,
        detectedAt,
        ownerUid: activity.ownerUid,
        contributionId: activity.id,
      },
    });
  }

  return flags;
}

// Rule 4: a contribution carries `mockSeedRunId`, meaning synthetic seed
// data (functions/src/leaderboard/seedLeaderboardMockData.ts, whose
// production path is command-gated and gitignore/CI-restricted) is present
// in a real leaderboard period. Always flagged, independent of cohort size —
// this is a certain governance fact, not a statistical guess.
function detectMockSeedContamination(
  contributions: readonly LeaderboardContributionRow[],
): ScoredFlag[] {
  return contributions
    .filter((row) => row.mockSeedRunId !== null && row.mockSeedRunId !== "")
    .map((row): ScoredFlag => {
      const { user, region } = contributionOwnerLabel(row);
      return {
        severity: 10000 + (row.scoreXp ?? 0),
        score: {
          id: `mock-seed-${row.id}`,
          user,
          region,
          flaggedScore: row.scoreXp ?? 0,
          reason: `Contribution carries mockSeedRunId "${row.mockSeedRunId}" — synthetic seed data present in a real leaderboard period (${cohortLabel(row)}).`,
          detectedAt: row.lastProgressionAt ?? EPOCH_ISO,
          ownerUid: row.ownerUid ?? "unknown",
          contributionId: row.id,
        },
      };
    });
}

// Runs all four rules against the leaderboard period the app is actually
// serving and that same period's real activities, then returns the combined
// findings sorted most-severe-first and capped at SUSPICIOUS_SCORE_LIST_CAP
// (see ./types — the cap is a client-visible constant so
// LeaderboardOversight.tsx can tell the admin when the list was truncated).
//
// The period comes from leaderboardPeriods/monthly_current, not from the
// wall-clock Singapore month: when a month rollover fails or the aggregation
// job stalls — exactly the states this page exists to surface — the two
// disagree, and reading the calendar month would empty this list (or show a
// different month) while the Current period card still points at the previous
// period. The calendar key is only a fallback for a database with no period
// document at all.
export async function getLiveSuspiciousScores(): Promise<SuspiciousScore[]> {
  const period = await getLeaderboardCurrentPeriod();
  const periodKey = period?.periodKey ?? currentSingaporeMonthKey(new Date());
  const window = singaporeMonthWindow(periodKey);

  const [contributions, activities] = await Promise.all([
    listLeaderboardContributions(periodKey),
    // Bounded to the period's own window and ordered newest-first, so an
    // impossible run from a previous month cannot surface as a current-period
    // anomaly (it belongs to that month's review, and would be shown against
    // the owner's *current* contribution score). A period key that does not
    // parse leaves the window null; the scan then degrades to the previous
    // unordered behaviour rather than dropping the rule entirely.
    listActivitySummaries({
      limit: ACTIVITY_SCAN_LIMIT,
      startedAtFrom: window?.startIso,
      startedAtBefore: window?.endIso,
    }),
  ]);

  const contributionByOwner = new Map<string, LeaderboardContributionRow>();
  for (const row of contributions) {
    if (row.ownerUid !== null && !contributionByOwner.has(row.ownerUid)) {
      contributionByOwner.set(row.ownerUid, row);
    }
  }

  const flags = [
    ...detectMockSeedContamination(contributions),
    ...detectImplausibleActivities(activities, contributionByOwner),
    ...detectPeerScoreOutliers(contributions),
    ...detectXpPerRunOutliers(contributions),
  ];

  flags.sort((a, b) => b.severity - a.severity);

  return flags.slice(0, SUSPICIOUS_SCORE_LIST_CAP).map((flag) => flag.score);
}

// --- website content (config/siteContent) -------------------------------------

function mapSiteContentRow(row: SiteContentRow): WebsiteContent {
  return {
    announcementText: row.announcementText ?? "",
    announcementEnabled: row.announcementEnabled ?? false,
    heroHeadline: row.heroHeadline ?? "",
    heroSubtext: row.heroSubtext ?? "",
    // Normalize the stored pricing into a fully-populated SitePricing so the
    // admin form always opens on a complete, editable set of fields even when
    // config/siteContent.pricing is absent or partial.
    pricing: mergeSitePricing(row.pricing),
    // Same normalization for testimonials and the problem section.
    testimonials: mergeSiteTestimonials(row.testimonials),
    team: mergeSiteTeam(row.team),
    documents: mergeSiteDocuments(row.documents),
    download: mergeSiteDownload(row.download),
    problem: mergeSiteProblem(row.problem),
    solution: mergeSiteSolution(row.solution),
    personalizedPlan: mergeSitePersonalizedPlan(row.personalizedPlan),
    journeyMap: mergeSiteJourneyMap(row.journeyMap),
    xpProgression: mergeSiteXpProgression(row.xpProgression),
    territorial: mergeSiteTerritorial(row.territorial),
    postRunSummary: mergeSitePostRunSummary(row.postRunSummary),
    sectionTitles: mergeSectionTitles(row.sectionTitles),
    sectionOrder: mergeSectionOrder(row.sectionOrder),
    faqs: row.faqs ?? [],
  };
}

export async function getLiveWebsiteContent(): Promise<WebsiteContent> {
  const row = await getSiteContent();

  if (!row) {
    throw new Error("config/siteContent document does not exist");
  }

  return mapSiteContentRow(row);
}

// --- config summaries (config/progression, config/leaderboard, --------------
//     config/featureAccess, config/siteContent) --------------------------------
//
// A lightweight, read-only view of each backend config document's version and
// last-write metadata for the admin overview's "System Configuration" panel.
// Reads the same raw `config/{name}` docs as the getLive*Config() readers
// above via getConfigDoc(), but only surfaces the small bit of metadata the
// overview needs — it never merges in defaults or validates the full shape.

export type ConfigSummary = {
  id: string;
  label: string;
  href: string;
  version: number | null;
  updatedAt: string | null;
  updatedBy: string | null;
  configured: boolean;
};

const CONFIG_SUMMARY_SOURCES: ReadonlyArray<{
  id: string;
  label: string;
  href: string;
}> = [
  { id: "progression", label: "Progression (XP & levels)", href: "/admin/gamification" },
  { id: "leaderboard", label: "Leaderboard", href: "/admin/leaderboard" },
  { id: "featureAccess", label: "Feature access", href: "/admin/policies" },
  { id: "automation", label: "Automation & policies", href: "/admin/policies" },
  { id: "challengeAccess", label: "Challenge tier access", href: "/admin/policies" },
  { id: "characterAccess", label: "Character access", href: "/admin/policies" },
  { id: "siteContent", label: "Website content", href: "/admin/content" },
];

// Firestore Timestamp instances (and FieldValue sentinels resolved on read)
// expose `.toDate()`; this repo's live-data mappers otherwise rely on
// firestore.ts's own toIso() for row-shaped reads, but getConfigDoc() returns
// raw document data, so the conversion happens here instead.
function timestampToIso(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === "string") {
    return value;
  }

  if (
    typeof value === "object" &&
    "toDate" in value &&
    typeof (value as { toDate: unknown }).toDate === "function"
  ) {
    try {
      return (value as { toDate: () => Date }).toDate().toISOString();
    } catch {
      return null;
    }
  }

  return null;
}

export async function getLiveConfigSummaries(): Promise<ConfigSummary[]> {
  const docs = await Promise.all(
    CONFIG_SUMMARY_SOURCES.map((source) => getConfigDoc(source.id)),
  );

  return CONFIG_SUMMARY_SOURCES.map((source, index) => {
    const doc = docs[index];

    return {
      id: source.id,
      label: source.label,
      href: source.href,
      version:
        doc && typeof doc["version"] === "number"
          ? (doc["version"] as number)
          : null,
      updatedAt: doc ? timestampToIso(doc["updatedAt"]) : null,
      updatedBy:
        doc && typeof doc["updatedBy"] === "string"
          ? (doc["updatedBy"] as string)
          : null,
      configured: doc !== null,
    } satisfies ConfigSummary;
  });
}

// --- newsletter --------------------------------------------------------------

const NEWSLETTER_SUBSCRIBER_STATUSES: NewsletterSubscriberStatus[] = [
  "pending",
  "confirmed",
  "unsubscribed",
  "bounced",
];

function toNewsletterSubscriberStatus(
  value: string | null,
): NewsletterSubscriberStatus {
  return NEWSLETTER_SUBSCRIBER_STATUSES.includes(
    value as NewsletterSubscriberStatus,
  )
    ? (value as NewsletterSubscriberStatus)
    : "pending";
}

function mapNewsletterSubscriber(
  row: NewsletterSubscriberRow,
): NewsletterSubscriber {
  return {
    id: row.id,
    emailLower: row.emailLower ?? "",
    status: toNewsletterSubscriberStatus(row.status),
    source: row.source ?? "unknown",
    consentAt: row.consentAt,
    confirmedAt: row.confirmedAt,
    unsubscribedAt: row.unsubscribedAt,
    sendFailureCount: row.sendFailureCount ?? 0,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export async function getLiveNewsletterSubscribers(): Promise<
  NewsletterSubscriber[]
> {
  const rows = await listNewsletterSubscribers();
  return rows.map(mapNewsletterSubscriber);
}

const NEWSLETTER_CAMPAIGN_STATUSES: NewsletterCampaignStatus[] = [
  "draft",
  "testQueued",
  "queued",
  "sending",
  "sent",
  "failed",
];

function toNewsletterCampaignStatus(
  value: string | null,
): NewsletterCampaignStatus {
  return NEWSLETTER_CAMPAIGN_STATUSES.includes(
    value as NewsletterCampaignStatus,
  )
    ? (value as NewsletterCampaignStatus)
    : "draft";
}

function mapNewsletterCampaign(row: NewsletterCampaignRow): NewsletterCampaign {
  return {
    id: row.id,
    subject: row.subject ?? "",
    bodyMarkdown: row.bodyMarkdown ?? "",
    status: toNewsletterCampaignStatus(row.status),
    createdBy: row.createdBy ?? "",
    createdAt: row.createdAt,
    queuedAt: row.queuedAt,
    sentAt: row.sentAt,
    recipientCount: row.recipientCount ?? 0,
    deliveredCount: row.deliveredCount ?? 0,
    failedCount: row.failedCount ?? 0,
    testRecipients: row.testRecipients,
    lastTestSentAt: row.lastTestSentAt,
    error: row.error,
  };
}

export async function getLiveNewsletterCampaigns(): Promise<
  NewsletterCampaign[]
> {
  const rows = await listNewsletterCampaigns();
  return rows.map(mapNewsletterCampaign);
}
