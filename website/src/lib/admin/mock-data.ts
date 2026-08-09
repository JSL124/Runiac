// PLACEHOLDER DATA for the Platform Administrator console.
//
// Everything below is static mock data used to build and demonstrate the admin
// UI. In production these constants are replaced by Firebase / Cloud Functions
// backed APIs. Dates are recent relative to July 2026. Nothing here computes or
// stores real user XP, rank, streak, or leaderboard values — those are owned by
// the backend and only read here.

import { DEFAULT_SITE_PRICING } from "@/lib/site-pricing";
import { DEFAULT_SITE_TESTIMONIALS } from "@/lib/site-testimonials";
import { DEFAULT_SITE_TEAM } from "@/lib/site-team";
import { DEFAULT_SITE_DOCUMENTS } from "@/lib/site-documents";
import { DEFAULT_SITE_DOWNLOAD } from "@/lib/site-download";
import { DEFAULT_SITE_PROBLEM } from "@/lib/site-problem";
import { DEFAULT_SITE_SOLUTION } from "@/lib/site-solution";
import { DEFAULT_SITE_PERSONALIZED_PLAN } from "@/lib/site-personalized-plan";
import {
  DEFAULT_SITE_JOURNEY_MAP,
  DEFAULT_SITE_XP_PROGRESSION,
  DEFAULT_SITE_TERRITORIAL,
  DEFAULT_SITE_POST_RUN_SUMMARY,
} from "@/lib/site-highlight";
import {
  DEFAULT_SECTION_TITLES,
  DEFAULT_SECTION_ORDER,
} from "@/lib/site-section-titles";
import type {
  ActiveUsersPoint,
  AdminActionLogEntry,
  AdminUser,
  AggregationJob,
  AttentionItem,
  AuditEntry,
  ErrorGroup,
  ExceptionCase,
  FeedbackItem,
  LeaderboardCoverageSummary,
  LeaderboardCurrentPeriod,
  LeaderboardParticipationBreakdown,
  LeaderboardSettings,
  LevelThreshold,
  NewsletterCampaign,
  NewsletterSubscriber,
  OverviewStat,
  SuspiciousScore,
  SystemHealthComponent,
  WebsiteContent,
  XpRule,
} from "./types";

// --- Overview ---------------------------------------------------------------

export const OVERVIEW_STATS: OverviewStat[] = [
  {
    id: "unresolved-reports",
    label: "Unresolved reports",
    value: 12,
    hint: "Awaiting human review",
    tone: "accent",
    href: "/admin/exceptions",
  },
  {
    id: "critical-errors",
    label: "Critical app errors today",
    value: 3,
    hint: "New crash groups",
    tone: "critical",
    href: "/admin/errors",
  },
  {
    id: "failed-jobs",
    label: "Failed backend jobs",
    value: 1,
    hint: "Last 24 hours",
    tone: "critical",
    href: "/admin/audit",
  },
  {
    id: "active-users",
    label: "Active users this month",
    value: 18420,
    hint: "Backend-reported",
    tone: "neutral",
  },
];

export const SYSTEM_HEALTH: SystemHealthComponent[] = [
  {
    id: "firebase-auth",
    name: "Firebase Auth",
    description: "Sign-in and session issuance",
    status: "operational",
    lastCheckedAt: "2026-07-09T08:55:00Z",
  },
  {
    id: "firestore",
    name: "Firestore",
    description: "Primary application datastore",
    status: "operational",
    lastCheckedAt: "2026-07-09T08:55:00Z",
  },
  {
    id: "cloud-functions",
    name: "Cloud Functions",
    description: "Rule execution and background jobs",
    status: "degraded",
    lastCheckedAt: "2026-07-09T08:52:00Z",
  },
  {
    id: "leaderboard-aggregation",
    name: "Monthly leaderboard aggregation job",
    description: "Aggregates monthly and territory standings",
    status: "operational",
    lastCheckedAt: "2026-07-09T06:00:00Z",
  },
  {
    id: "xp-rules-engine",
    name: "XP rules engine",
    description: "Applies published XP rule versions",
    status: "operational",
    lastCheckedAt: "2026-07-09T08:50:00Z",
  },
];

export const ATTENTION_ITEMS: AttentionItem[] = [
  {
    id: "att-1",
    title: "Repeated crash affecting 214 users",
    detail: "Run summary screen, app version 3.4.1 on Android 14",
    severity: "critical",
    href: "/admin/exceptions",
  },
  {
    id: "att-2",
    title: "Suspicious XP activity flagged",
    detail: "Anomaly detection escalated an account with irregular XP gain",
    severity: "high",
    href: "/admin/exceptions",
  },
  {
    id: "att-3",
    title: "Low-confidence route moderation",
    detail: "Auto-moderation could not clear a submitted route description",
    severity: "medium",
    href: "/admin/exceptions",
  },
];

export const ACTIVE_USERS_TREND: ActiveUsersPoint[] = [
  { label: "Feb", activeUsers: 12980 },
  { label: "Mar", activeUsers: 13840 },
  { label: "Apr", activeUsers: 15110 },
  { label: "May", activeUsers: 16250 },
  { label: "Jun", activeUsers: 17390 },
  { label: "Jul", activeUsers: 18420 },
];

// --- Exception Queue --------------------------------------------------------

export const EXCEPTION_CASES: ExceptionCase[] = [
  {
    id: "exc-1043",
    type: "reported-feed-post",
    severity: "medium",
    summary: "Feed post reported as inappropriate by another user",
    source: "user-report",
    status: "pending",
    createdAt: "2026-07-09T09:00:00Z",
    subjectLabel: "Feed post fp_77c21",
    details: [
      "Reported post: fp_77c21",
      "Reporter uid: uid_2ac10",
      "Reason: feed_inappropriate",
      "Sanitized report — no location, credentials, or profile data included",
    ],
    sanitized: true,
    reporterUid: "uid_2ac10",
    targetType: "feedPost",
    targetId: "fp_77c21",
    reason: "feed_inappropriate",
  },
  {
    id: "exc-1041",
    type: "suspicious-xp",
    severity: "high",
    summary: "Irregular XP gain detected on a single account",
    source: "anomaly-detection",
    status: "pending",
    createdAt: "2026-07-09T05:40:00Z",
    subjectLabel: "User uid_8f21c",
    details: [
      "uid: uid_8f21c",
      "Signal: XP gain 9.4x the beginner cohort median in 24h",
      "Rule engine version at time of gain: v3",
      "Admin never edits XP directly — review and escalate to backend if fraud is confirmed",
    ],
    sanitized: true,
  },
  {
    id: "exc-1040",
    type: "reported-user",
    severity: "high",
    summary: "User reported for abusive messages in group challenge",
    source: "user-report",
    status: "reviewing",
    createdAt: "2026-07-08T21:05:00Z",
    subjectLabel: "User uid_3ab90",
    details: [
      "Reported uid: uid_3ab90",
      "Reports in group: 4 distinct reporters",
      "Category: harassment",
      "No profile details, location, or message contents beyond flagged snippets are shown",
    ],
    sanitized: true,
    reporterUid: "uid_a1f22",
    targetType: "user",
    targetId: "uid_3ab90",
    reason: "harassment",
  },
  {
    id: "exc-1035",
    type: "suspicious-xp",
    severity: "medium",
    summary: "Cluster of accounts with synchronized streak completions",
    source: "anomaly-detection",
    status: "dismissed",
    createdAt: "2026-07-06T11:02:00Z",
    subjectLabel: "Cluster #AX-88",
    details: [
      "Accounts: 6",
      "Signal: identical completion timestamps",
      "Outcome: determined to be a legitimate running group",
    ],
    sanitized: true,
  },
];

// --- Users ------------------------------------------------------------------

export const ADMIN_USERS: AdminUser[] = [
  {
    id: "usr-1",
    uid: "uid_a1f22",
    displayName: "Amelia Turner",
    nickname: "amelia",
    email: "amelia.t@example.com",
    userRole: "runner",
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
    accountStatus: "active",
    joinedAt: "2026-01-14",
    region: "London",
    note: "Consistent beginner, no reports.",
    totalXp: 740,
    level: 8,
    monthlyXp: 220,
  },
  {
    id: "usr-2",
    uid: "uid_b2c31",
    displayName: "Marcus Bell",
    nickname: "marcusruns",
    email: "marcus.b@example.com",
    userRole: "runner",
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
    accountStatus: "active",
    joinedAt: "2025-11-02",
    region: "Manchester",
    note: "Consistent runner, no reports.",
    totalXp: 1200,
    level: 12,
    monthlyXp: 180,
  },
  {
    id: "usr-3",
    uid: "uid_c3d40",
    displayName: "Dr. Priya Nair",
    nickname: "priya",
    email: "priya.n@example.com",
    userRole: "runner",
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
    accountStatus: "active",
    joinedAt: "2025-09-19",
    region: "Bristol",
    note: "Consistent runner, no reports.",
    totalXp: 1650,
    level: 15,
    monthlyXp: 300,
  },
  {
    id: "usr-4",
    uid: "uid_3ab90",
    displayName: "Jordan Okafor",
    nickname: "jordano",
    email: "jordan.o@example.com",
    userRole: "runner",
    subscriptionStatus: "basic",
    subscriptionExpiresAt: null,
    accountStatus: "suspended",
    joinedAt: "2026-03-08",
    region: "Leeds",
    note: "Suspended pending abuse review (case exc-1040).",
    totalXp: 250,
    level: 3,
    monthlyXp: 40,
  },
  {
    id: "usr-5",
    uid: "uid_5ef01",
    displayName: "Sofia Marin",
    nickname: "sofiam",
    email: "sofia.m@example.com",
    userRole: "runner",
    subscriptionStatus: "basic",
    subscriptionExpiresAt: null,
    accountStatus: "active",
    joinedAt: "2026-05-27",
    region: "Glasgow",
    note: "New runner, first plan in progress.",
    totalXp: 50,
    level: 1,
    monthlyXp: 50,
  },
  {
    id: "usr-6",
    uid: "uid_admin1",
    displayName: "Elena Costa",
    nickname: "elena",
    email: "elena.c@example.com",
    userRole: "platformAdmin",
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
    accountStatus: "active",
    joinedAt: "2025-06-01",
    region: "London",
    note: "Platform administrator account.",
    totalXp: null,
    level: null,
    monthlyXp: null,
  },
  {
    id: "usr-7",
    uid: "uid_7ff12",
    displayName: "Tomasz Nowak",
    nickname: "tomrun",
    email: "tomasz.n@example.com",
    userRole: "runner",
    subscriptionStatus: "premium",
    subscriptionExpiresAt: null,
    accountStatus: "active",
    joinedAt: "2025-12-15",
    region: "Edinburgh",
    note: "Consistent runner, high engagement.",
    totalXp: 2400,
    level: 20,
    monthlyXp: 400,
  },
];

export const USER_ACTION_HISTORY: AdminActionLogEntry[] = [
  {
    id: "uah-1",
    actor: "elena.c@example.com",
    action: "Suspended account",
    target: "Jordan Okafor",
    timestamp: "2026-07-08T21:20:00Z",
  },
  {
    id: "uah-2",
    actor: "elena.c@example.com",
    action: "Restored account",
    target: "Tomasz Nowak",
    timestamp: "2026-07-05T10:12:00Z",
  },
  {
    id: "uah-3",
    actor: "elena.c@example.com",
    action: "Restored account",
    target: "Sofia Marin",
    timestamp: "2026-07-01T09:40:00Z",
  },
];

// --- Gamification -----------------------------------------------------------

export const XP_RULES: XpRule[] = [
  {
    id: "xp-run-complete",
    action: "Complete a scheduled run",
    description: "Awarded when a planned session is finished",
    xp: 50,
  },
  {
    id: "xp-run-early",
    action: "Complete a run before noon",
    description: "Small morning-habit bonus",
    xp: 10,
  },
  {
    id: "xp-streak-day",
    action: "Maintain a daily streak",
    description: "Per active streak day",
    xp: 15,
  },
  {
    id: "xp-first-plan",
    action: "Finish first plan week",
    description: "One-time onboarding reward",
    xp: 100,
  },
  {
    id: "xp-share-summary",
    action: "Share a run summary",
    description: "Encourages community participation",
    xp: 5,
  },
];

export const LEVEL_THRESHOLDS: LevelThreshold[] = [
  { level: 1, xpRequired: 0 },
  { level: 2, xpRequired: 250 },
  { level: 3, xpRequired: 600 },
  { level: 4, xpRequired: 1100 },
  { level: 5, xpRequired: 1800 },
  { level: 6, xpRequired: 2800 },
];

// --- Leaderboard ------------------------------------------------------------

export const AGGREGATION_JOB: AggregationJob = {
  name: "Monthly leaderboard aggregation",
  lastRunAt: "2026-07-09T06:00:00Z",
  durationSeconds: 214,
  status: "operational",
  nextRunAt: "2026-07-09T07:00:00Z",
  periodKey: "2026-07",
  buildId: "mock-build-0007",
  startedAt: "2026-07-09T05:56:26Z",
  staleLease: false,
};

export const LEADERBOARD_SETTINGS: LeaderboardSettings = {
  seasonLengthDays: 30,
  regionalGrouping: true,
  minRunsToQualify: 4,
};

export const LEADERBOARD_CURRENT_PERIOD: LeaderboardCurrentPeriod = {
  periodKey: "2026-07",
  periodLabel: "July 2026",
  timezone: "Asia/Singapore",
  refreshesAt: "2026-08-01T00:00:00.000Z",
  buildId: "mock-build-0007",
  generatedAt: "2026-07-09T06:00:00Z",
  aggregationStatus: "ready",
};

export const LEADERBOARD_PARTICIPATION: LeaderboardParticipationBreakdown = {
  ranked: 640,
  unranked: 120,
  regionRequired: 85,
  ineligiblePremium: 40,
  ineligibleMinRuns: 95,
  total: 980,
  // Deliberately larger than `total`: the gap is the never-ran cohort, and a
  // mock where the two matched would hide the one row the panel exists to show.
  registeredUsers: 1420,
};

export const LEADERBOARD_COVERAGE: LeaderboardCoverageSummary = {
  snapshotCount: 96,
  regionsCovered: 22,
  divisionsCovered: 6,
  totalEntries: 640,
  periodKeys: ["2026-07", "2026-06", "2026-05"],
};

export const SUSPICIOUS_SCORES: SuspiciousScore[] = [
  {
    id: "sus-1",
    user: "uid_8f21c",
    region: "London",
    flaggedScore: 4820,
    reason: "Score 9.4x territory median with sparse run history",
    detectedAt: "2026-07-09T05:40:00Z",
    ownerUid: "uid_8f21c",
    contributionId: "uid_8f21c_monthly_2026-07",
  },
  {
    id: "sus-2",
    user: "uid_47b0e",
    region: "Manchester",
    flaggedScore: 3110,
    reason: "Sudden jump inconsistent with prior monthly activity",
    detectedAt: "2026-07-08T22:15:00Z",
    ownerUid: "uid_47b0e",
    contributionId: "uid_47b0e_monthly_2026-07",
  },
];

// --- Website Content --------------------------------------------------------

export const WEBSITE_CONTENT: WebsiteContent = {
  announcementText: "New beginner plans just landed — start your first run today.",
  announcementEnabled: true,
  heroHeadline: "Keep your running habit going.",
  heroSubtext:
    "Runiac guides beginners run by run, turning small wins into a lasting habit.",
  problem: DEFAULT_SITE_PROBLEM,
  solution: DEFAULT_SITE_SOLUTION,
  personalizedPlan: DEFAULT_SITE_PERSONALIZED_PLAN,
  journeyMap: DEFAULT_SITE_JOURNEY_MAP,
  xpProgression: DEFAULT_SITE_XP_PROGRESSION,
  territorial: DEFAULT_SITE_TERRITORIAL,
  postRunSummary: DEFAULT_SITE_POST_RUN_SUMMARY,
  sectionTitles: DEFAULT_SECTION_TITLES,
  sectionOrder: DEFAULT_SECTION_ORDER,
  pricing: DEFAULT_SITE_PRICING,
  testimonials: DEFAULT_SITE_TESTIMONIALS,
  team: DEFAULT_SITE_TEAM,
  documents: DEFAULT_SITE_DOCUMENTS,
  download: DEFAULT_SITE_DOWNLOAD,
  faqs: [
    {
      id: "faq-1",
      question: "Is Runiac good for absolute beginners?",
      answer: "Yes. Every plan starts gentle and adapts to your pace.",
    },
    {
      id: "faq-2",
      question: "Do I need a subscription to start?",
      answer:
        "No. Core plans and tracking are free; Premium adds advanced run analysis and AI coaching.",
    },
    {
      id: "faq-3",
      question: "How does Runiac keep me motivated?",
      answer:
        "Small XP rewards, streaks, and supportive feedback focus on consistency.",
    },
  ],
};

// --- Feedback ---------------------------------------------------------------

export const FEEDBACK_ITEMS: FeedbackItem[] = [
  {
    id: "fb-1",
    category: "bug",
    summary: "Run summary occasionally fails to save after a session",
    severity: "high",
    duplicateCount: 14,
    status: "escalated",
    receivedAt: "2026-07-09T07:30:00Z",
    note: "",
    closed: false,
  },
  {
    id: "fb-2",
    category: "plan issue",
    summary: "Week 1 volume feels too high for absolute beginners",
    severity: "medium",
    duplicateCount: 9,
    status: "new",
    receivedAt: "2026-07-08T19:12:00Z",
    note: "",
    closed: false,
  },
  {
    id: "fb-3",
    category: "billing",
    summary: "Premium upgrade not reflected immediately after payment",
    severity: "medium",
    duplicateCount: 6,
    status: "resolved",
    receivedAt: "2026-07-08T13:05:00Z",
    note: "Billing system reconciles within an hour; templated response sent.",
    closed: true,
  },
  {
    id: "fb-4",
    category: "abuse",
    summary: "Inappropriate display name reported in a group challenge",
    severity: "high",
    duplicateCount: 3,
    status: "escalated",
    receivedAt: "2026-07-07T22:40:00Z",
    note: "",
    closed: false,
  },
  {
    id: "fb-5",
    category: "other",
    summary: "Request for dark mode in the mobile app",
    severity: "low",
    duplicateCount: 21,
    status: "new",
    receivedAt: "2026-07-07T10:20:00Z",
    note: "",
    closed: false,
  },
];

// --- Errors -----------------------------------------------------------------

export const ERROR_GROUPS: ErrorGroup[] = [
  {
    id: "err-3341",
    title: "NullReference in RunSummaryController.save()",
    screen: "Run summary",
    appVersion: "3.4.1",
    os: "Android 14",
    source: "mobile",
    occurrences: 1284,
    affectedUsers: 214,
    severity: "critical",
    status: "new",
    firstSeenAt: "2026-07-09T02:10:00Z",
    lastSeenAt: "2026-07-09T08:44:00Z",
    stackSummary:
      "RunSummaryController.save -> SessionRepository.persist -> null session id",
    sanitized: true,
  },
  {
    id: "err-3320",
    title: "Timeout syncing plan progress",
    screen: "Today plan",
    appVersion: "3.4.1",
    os: "iOS 18.2",
    source: "mobile",
    occurrences: 642,
    affectedUsers: 133,
    severity: "high",
    status: "investigating",
    firstSeenAt: "2026-07-08T11:00:00Z",
    lastSeenAt: "2026-07-09T07:55:00Z",
    stackSummary: "PlanSyncService.fetch -> network timeout after 30s",
    sanitized: true,
  },
  {
    id: "err-3299",
    title: "Rendering error on badge unlock animation",
    screen: "Rewards",
    appVersion: "3.4.0",
    os: "Android 13",
    source: "mobile",
    occurrences: 288,
    affectedUsers: 71,
    severity: "medium",
    status: "new",
    firstSeenAt: "2026-07-07T14:22:00Z",
    lastSeenAt: "2026-07-09T05:31:00Z",
    stackSummary: "BadgeUnlockView.render -> missing asset variant",
    sanitized: true,
  },
  {
    id: "err-3270",
    title: "Crash opening territory standings",
    screen: "Leaderboard",
    appVersion: "3.3.9",
    os: "iOS 17.6",
    source: "mobile",
    occurrences: 96,
    affectedUsers: 40,
    severity: "medium",
    status: "resolved",
    firstSeenAt: "2026-07-04T09:15:00Z",
    lastSeenAt: "2026-07-06T20:02:00Z",
    stackSummary: "TerritoryBoardView.init -> index out of range",
    sanitized: true,
  },
  {
    id: "err-3255",
    title: "Non-fatal: deprecated API warning on startup",
    screen: "App start",
    appVersion: "3.4.1",
    os: "Android 12",
    source: "mobile",
    occurrences: 5120,
    affectedUsers: 1890,
    severity: "low",
    status: "ignored",
    firstSeenAt: "2026-07-02T00:05:00Z",
    lastSeenAt: "2026-07-09T08:10:00Z",
    stackSummary: "Startup.checkCompat -> deprecated scheduler API",
    sanitized: true,
  },
];

// --- Audit ------------------------------------------------------------------

export const AUDIT_ENTRIES: AuditEntry[] = [
  {
    id: "aud-1",
    actor: "elena.c@example.com",
    action: "Updated progression config",
    target: "config progression",
    category: "rule-activation",
    timestamp: "2026-07-09T08:05:00Z",
  },
  {
    id: "aud-2",
    actor: "system",
    action: "Backend job failed",
    target: "nightly-badge-recalculation",
    category: "backend-job",
    timestamp: "2026-07-09T03:14:00Z",
  },
  {
    id: "aud-3",
    actor: "elena.c@example.com",
    action: "Suspended account",
    target: "Jordan Okafor (usr-4)",
    category: "admin-action",
    timestamp: "2026-07-08T21:20:00Z",
  },
  {
    id: "aud-4",
    actor: "system",
    action: "Subscription changed to Premium",
    target: "Sofia Marin (usr-5)",
    category: "subscription-change",
    timestamp: "2026-07-08T16:02:00Z",
  },
  {
    id: "aud-5",
    actor: "elena.c@example.com",
    action: "Activated rule set v3",
    target: "XP rules engine",
    category: "rule-activation",
    timestamp: "2026-06-20T12:00:00Z",
  },
  {
    id: "aud-6",
    actor: "elena.c@example.com",
    action: "Changed role to Platform Admin",
    target: "Tomasz Nowak (usr-7)",
    category: "role-change",
    timestamp: "2026-07-05T10:12:00Z",
  },
  {
    id: "aud-7",
    actor: "elena.c@example.com",
    action: "Restored account",
    target: "Dr. Priya Nair (usr-3)",
    category: "admin-action",
    timestamp: "2026-07-03T09:30:00Z",
  },
];

// --- Newsletter --------------------------------------------------------------

export const NEWSLETTER_SUBSCRIBERS: NewsletterSubscriber[] = [
  {
    id: "sub-1",
    emailLower: "priya.nair@example.com",
    status: "confirmed",
    source: "hero-signup",
    consentAt: "2026-07-01T09:12:00Z",
    confirmedAt: "2026-07-01T09:14:00Z",
    unsubscribedAt: null,
    sendFailureCount: 0,
    createdAt: "2026-07-01T09:12:00Z",
    updatedAt: "2026-07-01T09:14:00Z",
  },
  {
    id: "sub-2",
    emailLower: "jordan.okafor@example.com",
    status: "pending",
    source: "hero-signup",
    consentAt: "2026-07-08T14:40:00Z",
    confirmedAt: null,
    unsubscribedAt: null,
    sendFailureCount: 0,
    createdAt: "2026-07-08T14:40:00Z",
    updatedAt: "2026-07-08T14:40:00Z",
  },
  {
    id: "sub-3",
    emailLower: "tomasz.nowak@example.com",
    status: "unsubscribed",
    source: "hero-signup",
    consentAt: "2026-06-14T11:02:00Z",
    confirmedAt: "2026-06-14T11:05:00Z",
    unsubscribedAt: "2026-07-02T08:00:00Z",
    sendFailureCount: 0,
    createdAt: "2026-06-14T11:02:00Z",
    updatedAt: "2026-07-02T08:00:00Z",
  },
  // No "bounced" fixture: the backend never produces that status, so a mock
  // row carrying it would show credential-less renders a state production
  // cannot reach. The three rows above cover every reachable status.
];

export const NEWSLETTER_CAMPAIGNS: NewsletterCampaign[] = [
  {
    id: "camp-1",
    subject: "Runiac launch update: beta signups are open",
    bodyMarkdown:
      "# We're getting close\n\nThanks for signing up — the Runiac beta opens soon. Here's what's new this month.",
    status: "sent",
    createdBy: "elena.c@example.com",
    createdAt: "2026-06-20T10:00:00Z",
    queuedAt: "2026-06-20T10:05:00Z",
    sentAt: "2026-06-20T10:12:00Z",
    recipientCount: 128,
    deliveredCount: 125,
    failedCount: 3,
    testRecipients: ["elena.c@example.com"],
    lastTestSentAt: "2026-06-20T09:40:00Z",
    error: null,
  },
  {
    id: "camp-2",
    subject: "Draft: training-plan preview walkthrough",
    bodyMarkdown:
      "# Coming soon\n\nA first look at the personalized training-plan flow.",
    status: "draft",
    createdBy: "elena.c@example.com",
    createdAt: "2026-07-09T08:00:00Z",
    queuedAt: null,
    sentAt: null,
    recipientCount: 0,
    deliveredCount: 0,
    failedCount: 0,
    testRecipients: [],
    lastTestSentAt: null,
    error: null,
  },
];
