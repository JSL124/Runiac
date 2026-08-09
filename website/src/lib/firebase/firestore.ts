// Typed Admin-SDK Firestore accessors for the Runiac admin console.
//
// Every function here converts Firestore Timestamps to ISO strings at this
// boundary and returns the narrow row types from ./types. Mutations that change
// backend-owned state also append an entry to the `adminAuditLogs` collection.
// Queries are kept deliberately simple (single-field filters + in-memory
// filtering) so they do not require composite indexes on the emulator.

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type {
  DocumentData,
  Firestore,
  Query,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";

import { getAdminAuth, getAdminDb } from "./admin";
import type {
  AdminNotificationRow,
  AdminUserRow,
  AuditLogRow,
  ActivitySummaryRow,
  ConfigHistoryRow,
  ErrorGroupRow,
  ErrorGroupTriageStatus,
  FeedbackRow,
  FeedbackTriageStatus,
  LeaderboardAggregationLockRow,
  LeaderboardCommandRow,
  LeaderboardContributionRow,
  LeaderboardCurrentPeriodRow,
  LeaderboardCurrentViewStatus,
  LeaderboardCurrentViewStatusCounts,
  LeaderboardEntry,
  LeaderboardSnapshotRow,
  LeaderboardSnapshotSummaryRow,
  ModerationCommandRow,
  NewsletterCampaignRow,
  NewsletterCampaignStatus,
  NewsletterDeliveryRow,
  NewsletterSubscriberRow,
  NewsletterSubscriberStatus,
  ReportResolutionStatus,
  ReportRow,
  SiteContentRow,
  SubscriptionCounts,
} from "./types";
import {
  deriveProgressionDisplayFields,
  type UserProgressionFields,
} from "@/lib/admin/progression-curve";
import type { ProgressionConfig } from "@/lib/admin/config-validation";
import type {
  ProjectDocumentCategory,
  ProjectDocumentRecord,
} from "@/lib/project-documents";
import { deleteAvatarObject } from "./storage";
import { isAvatarObjectPath } from "@/lib/avatarPaths";

const USERS = "users";
const USER_PROFILES = "userProfiles";
const REPORTS = "reports";
const FEED_POSTS = "feedPosts";
const MODERATION_COMMANDS = "moderationCommands";
const FEEDBACK = "feedback";
const ERROR_GROUPS = "errorGroups";
const ACTIVITIES = "activities";
const LEADERBOARD_SNAPSHOTS = "leaderboardSnapshots";
const LEADERBOARD_CONTRIBUTIONS = "leaderboardContributions";
const LEADERBOARD_AGGREGATION_LOCKS = "leaderboardAggregationLocks";
const LEADERBOARD_ADMIN_COMMANDS = "leaderboardAdminCommands";
const LEADERBOARD_PERIODS = "leaderboardPeriods";
const LEADERBOARD_CURRENT_VIEWS = "leaderboardCurrentViews";
const CURRENT_PERIOD_DOC_ID = "monthly_current";
const PROGRESSION_EVENTS = "progressionEvents";
const ADMIN_AUDIT_LOGS = "adminAuditLogs";
const ADMIN_NOTIFICATIONS = "adminNotifications";
const ACCOUNT_DELETION_COMMANDS = "accountDeletionCommands";
const CONFIG = "config";
const SITE_CONTENT_DOC_ID = "siteContent";
const PROJECT_DOCUMENTS = "projectDocuments";
const NEWSLETTER_SUBSCRIBERS = "newsletterSubscribers";
const NEWSLETTER_CAMPAIGNS = "newsletterCampaigns";
const NEWSLETTER_DELIVERIES = "deliveries";

// --- value coercion helpers -------------------------------------------------

function toIso(value: unknown): string | null {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "string") {
    return value;
  }

  if (typeof value === "number") {
    return new Date(value).toISOString();
  }

  return null;
}

// Recursively converts a raw Firestore document value into something safe to
// hand to a Client Component: Timestamps/Dates become ISO strings, nested maps
// and arrays are rebuilt as plain objects/arrays. Server Components can only
// serialize plain values, so a Timestamp leaking through (e.g. the `updatedAt`
// serverTimestamp written by setConfigDoc) crashes the render.
function toPlainValue(value: unknown): unknown {
  if (value instanceof Timestamp || value instanceof Date) {
    return toIso(value);
  }

  if (Array.isArray(value)) {
    return value.map(toPlainValue);
  }

  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, entry]) => [
        key,
        toPlainValue(entry),
      ]),
    );
  }

  return value;
}

function readString(data: DocumentData, key: string): string | null {
  const value = data[key];
  return typeof value === "string" ? value : null;
}

function readNumber(data: DocumentData, key: string): number | null {
  const value = data[key];
  return typeof value === "number" ? value : null;
}

function readBoolean(data: DocumentData, key: string): boolean | null {
  const value = data[key];
  return typeof value === "boolean" ? value : null;
}

// --- audit log --------------------------------------------------------------

type AuditLogEntry = {
  actor: string;
  action: string;
  targetType: string;
  targetId: string;
  detail: string;
  changedFields?: string[];
  before?: unknown;
  after?: unknown;
};

// Pure record builder, split out of appendAuditLog() below so a caller that
// needs the audit write to commit ATOMICALLY with another write (inside a
// db.runTransaction()/db.batch()) can build the same record shape and hand it
// to transaction.set()/batch.set() on a pre-allocated doc ref, instead of
// going through a separate, non-atomic add() after the fact. See
// queueNewsletterCampaignSend() below for why that distinction matters.
function buildAuditLogRecord(entry: AuditLogEntry): Record<string, unknown> {
  const record: Record<string, unknown> = {
    actor: entry.actor,
    action: entry.action,
    targetType: entry.targetType,
    targetId: entry.targetId,
    detail: entry.detail,
    createdAt: FieldValue.serverTimestamp(),
  };

  if (entry.changedFields !== undefined) {
    record.changedFields = entry.changedFields;
  }

  if (entry.before !== undefined) {
    record.before = entry.before;
  }

  if (entry.after !== undefined) {
    record.after = entry.after;
  }

  return record;
}

async function appendAuditLog(
  db: Firestore,
  entry: AuditLogEntry,
): Promise<void> {
  await db.collection(ADMIN_AUDIT_LOGS).add(buildAuditLogRecord(entry));
}

// --- users ------------------------------------------------------------------

function mapUserRow(
  uid: string,
  userData: DocumentData,
  profileData: DocumentData | undefined,
  auth: AuthFacts | undefined,
): AdminUserRow {
  return {
    uid,
    displayName: profileData ? readString(profileData, "displayName") : null,
    nickname: profileData ? readString(profileData, "nickname") : null,
    email: auth?.email ?? null,
    userRole: readString(userData, "userRole") ?? "runner",
    subscriptionStatus: readString(userData, "subscriptionStatus") ?? "basic",
    subscriptionExpiresAt: toIso(userData["subscriptionExpiresAt"]),
    accountStatus: readString(userData, "accountStatus"),
    locationLabel: profileData ? readString(profileData, "locationLabel") : null,
    fitnessLevel: profileData ? readString(profileData, "fitnessLevel") : null,
    // Neither collection has ever carried `createdAt` — the app's profile
    // write (user_profile_persistence_repository.dart) stores updatedAt only,
    // and nothing else provisions the field — so in practice this resolves to
    // the Auth record's creationTime, which Firebase stamps on every account
    // for free. Reading the documents first still matters: it lets a backfill
    // or an imported account carry its own date, and it keeps a uid with no
    // Auth record (a seeded directory row) from claiming one it never had.
    createdAt:
      toIso(userData["createdAt"]) ??
      (profileData ? toIso(profileData["createdAt"]) : null) ??
      auth?.createdAt ??
      null,
    totalXp: profileData ? readNumber(profileData, "totalXp") : null,
    level: profileData ? readNumber(profileData, "level") : null,
    monthlyXp: profileData ? readNumber(profileData, "monthlyXp") : null,
    hasAvatar: profileData
      ? Boolean(readString(profileData, "avatarObjectPath"))
      : false,
  };
}

// Batch-reads a set of documents from one collection, tolerating an empty
// input (db.getAll() rejects when called with no refs).
async function readDocsById(
  db: Firestore,
  collection: string,
  uids: string[],
): Promise<Map<string, DocumentData>> {
  const byId = new Map<string, DocumentData>();

  if (uids.length === 0) {
    return byId;
  }

  const refs = uids.map((uid) => db.collection(collection).doc(uid));
  const snapshots = await db.getAll(...refs);

  for (const snapshot of snapshots) {
    const data = snapshot.data();
    if (data) {
      byId.set(snapshot.id, data);
    }
  }

  return byId;
}

// Joins users + userProfiles + Auth emails.
//
// The directory is the UNION of both collections, not just `users`. The mobile
// app only ever writes `userProfiles/{uid}` (plus `users/{uid}` subcollections
// such as friends/hiddenFeedPosts, which do not materialise the parent
// document), while the admin-owned fields — userRole, subscriptionStatus,
// accountStatus — live on `users/{uid}`. Paging `users` alone therefore hides
// every real account that an admin has never acted on. Any uid discovered
// through `userProfiles` is backfilled with its `users` document when one
// exists, and otherwise falls back to the mapUserRow() defaults (runner /
// basic / no account status), so it is still listable and actionable.
//
// Search has two tiers, and the difference matters. An email or a uid resolves
// the account directly, so it is found no matter how large the collection is.
// Anything else — a partial name or nickname — is a substring filter applied
// IN MEMORY over the scanned window only. Firestore cannot answer a substring
// query, and neither collection stores a normalised searchable name field, so
// a partial-name search genuinely cannot see past `limit`. `windowFull` reports
// exactly that, and callers are expected to surface it rather than present a
// truncated result as the whole directory.
export type ListUsersResult = {
  rows: AdminUserRow[];
  // Accounts materialised from the scan window, counted BEFORE the search
  // filter. `rows.length` is post-filter and must never be used to decide
  // whether more accounts exist server-side.
  scanned: number;
  // The scan filled its limit, so accounts almost certainly exist beyond the
  // window and a search cannot have covered them.
  windowFull: boolean;
  // The query was answered by a direct uid/email lookup rather than by
  // filtering the window, so the window size is irrelevant to this result.
  resolvedExactly: boolean;
};

// Firebase Auth uids are opaque 28-char tokens in practice; accept a slightly
// wider band rather than hard-coding 28. A human name never reaches 20
// characters with no separator, so this cannot swallow a real name search.
const UID_PATTERN = /^[A-Za-z0-9_-]{20,128}$/;

// Resolves a search term straight to a uid when it identifies exactly one
// account, so "find this person" works regardless of how large the collection
// has grown. Everything else falls through to the scan-and-filter path below.
async function resolveExactUid(search: string): Promise<string | null> {
  if (search.includes("@")) {
    try {
      return (await getAdminAuth().getUserByEmail(search)).uid;
    } catch {
      // Unknown or malformed address: fall through to the substring scan.
      return null;
    }
  }

  return UID_PATTERN.test(search) ? search : null;
}

export async function listUsers(options?: {
  search?: string;
  limit?: number;
}): Promise<ListUsersResult> {
  const db = getAdminDb();
  const limit = options?.limit ?? 100;
  const search = options?.search?.trim().toLowerCase();

  if (search) {
    const exactUid = await resolveExactUid(search);

    if (exactUid) {
      const [userSnapshot, profileSnapshot] = await Promise.all([
        db.collection(USERS).doc(exactUid).get(),
        db.collection(USER_PROFILES).doc(exactUid).get(),
      ]);
      const userData = userSnapshot.data();
      const profileData = profileSnapshot.data();

      // A uid that exists in neither collection is not an account we can show;
      // fall through so a substring match still gets its chance.
      if (userData || profileData) {
        const authByUid = await resolveAuthFacts([exactUid]);
        return {
          rows: [
            mapUserRow(
              exactUid,
              userData ?? {},
              profileData,
              authByUid.get(exactUid),
            ),
          ],
          scanned: 1,
          windowFull: false,
          resolvedExactly: true,
        };
      }
    }
  }

  const [usersSnapshot, profilesSnapshot] = await Promise.all([
    db.collection(USERS).limit(limit).get(),
    db.collection(USER_PROFILES).limit(limit).get(),
  ]);

  const userDataById = new Map<string, DocumentData>();
  for (const doc of usersSnapshot.docs) {
    userDataById.set(doc.id, doc.data());
  }

  const profileById = new Map<string, DocumentData>();
  for (const doc of profilesSnapshot.docs) {
    profileById.set(doc.id, doc.data());
  }

  // Each collection was capped at `limit`, so their union can exceed it. Report
  // the scan as full whenever either side hit its cap OR the union had to be
  // trimmed, because in all of those cases accounts exist beyond the window.
  const union = [...new Set([...userDataById.keys(), ...profileById.keys()])];
  const windowFull =
    usersSnapshot.size >= limit ||
    profilesSnapshot.size >= limit ||
    union.length > limit;
  const uids = union.slice(0, limit);

  if (uids.length === 0) {
    return { rows: [], scanned: 0, windowFull, resolvedExactly: false };
  }

  // Fill the cross-collection gaps: a uid seen in one page may sit beyond the
  // other collection's page boundary.
  const [missingUsers, missingProfiles] = await Promise.all([
    readDocsById(
      db,
      USERS,
      uids.filter((uid) => !userDataById.has(uid)),
    ),
    readDocsById(
      db,
      USER_PROFILES,
      uids.filter((uid) => !profileById.has(uid)),
    ),
  ]);

  for (const [uid, data] of missingUsers) {
    userDataById.set(uid, data);
  }
  for (const [uid, data] of missingProfiles) {
    profileById.set(uid, data);
  }

  const authByUid = await resolveAuthFacts(uids);

  const rows = uids.map((uid) =>
    mapUserRow(
      uid,
      userDataById.get(uid) ?? {},
      profileById.get(uid),
      authByUid.get(uid),
    ),
  );

  if (!search) {
    return { rows, scanned: rows.length, windowFull, resolvedExactly: false };
  }

  const matched = rows.filter((row) => {
    const haystack = [row.uid, row.displayName, row.nickname, row.email]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.toLowerCase());
    return haystack.some((value) => value.includes(search));
  });

  return {
    rows: matched,
    scanned: rows.length,
    windowFull,
    resolvedExactly: false,
  };
}

// Auth reports account timestamps as a UTC date string ("Tue, 10 Aug 2026
// 07:00:00 GMT"), not as ISO — and toIso() passes strings through untouched, so
// it cannot do this job. Re-emitting through Date keeps every date this module
// hands out in one format, and rejects an unparseable value instead of letting
// an Invalid Date reach a formatter.
function toIsoFromUtcString(value: string | undefined): string | null {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

type AuthFacts = {
  email: string | null;
  createdAt: string | null;
};

// getUsers() rejects outright above 100 identifiers, and every caller here
// wraps it in a catch — so a single oversized call does not degrade one row, it
// silently blanks the email and join date of the entire page. Chunking keeps
// that failure mode unreachable no matter what limit a caller passes.
const AUTH_LOOKUP_CHUNK = 100;

// The Auth record is the only place an account's creation time exists (see
// mapUserRow), so this is not merely an email lookup any more.
async function resolveAuthFacts(
  uids: string[],
): Promise<Map<string, AuthFacts>> {
  const factsByUid = new Map<string, AuthFacts>();

  for (let index = 0; index < uids.length; index += AUTH_LOOKUP_CHUNK) {
    const chunk = uids.slice(index, index + AUTH_LOOKUP_CHUNK);

    try {
      const result = await getAdminAuth().getUsers(
        chunk.map((uid) => ({ uid })),
      );
      for (const user of result.users) {
        factsByUid.set(user.uid, {
          email: user.email ?? null,
          createdAt: toIsoFromUtcString(user.metadata.creationTime),
        });
      }
    } catch {
      // Auth lookup is best-effort per chunk; rows in a failed chunk simply
      // omit the email and join date rather than taking down the listing.
    }
  }

  return factsByUid;
}

// Mirrors the role onto Firebase Auth custom claims so the grant is carried by
// the identity token itself, not only by a Firestore document. Without this the
// role is invisible to anything that authenticates a caller before reading
// Firestore. Refresh tokens are revoked on every change so a demotion takes
// effect immediately instead of lingering for the life of an issued token.
//
// A uid with no Auth record (seeded/synthetic directory rows) is not an error;
// the Firestore write still proceeds. Returns whether claims were applied so
// the audit entry can say which happened.
async function syncAuthRoleClaims(
  uid: string,
  role: string,
): Promise<boolean> {
  const auth = getAdminAuth();
  const isPlatformAdmin = role === "platformAdmin";

  try {
    const existing = (await auth.getUser(uid)).customClaims ?? {};
    await auth.setCustomUserClaims(uid, {
      ...existing,
      userRole: role,
      platformAdmin: isPlatformAdmin,
    });
    await auth.revokeRefreshTokens(uid);
    return true;
  } catch (error) {
    if ((error as { code?: string }).code === "auth/user-not-found") {
      return false;
    }

    throw error;
  }
}

export async function setUserRole(
  uid: string,
  role: string,
  actorEmail: string,
  reason: string,
  before: { userRole: string | null },
): Promise<void> {
  const db = getAdminDb();

  // Claims first: a failure must abort before the role is recorded, so the
  // document never claims an authority the token does not carry.
  const claimsApplied = await syncAuthRoleClaims(uid, role);

  await db
    .collection(USERS)
    .doc(uid)
    .set({ userRole: role, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  await appendAuditLog(db, {
    actor: actorEmail,
    action: "role-change",
    targetType: "user",
    targetId: uid,
    detail:
      `Set userRole to ${role} for user ${uid}: ${reason}` +
      (claimsApplied
        ? " (Auth custom claims updated, sessions revoked)"
        : " (no Firebase Auth account; claims unchanged)"),
    changedFields: ["userRole"],
    before,
    after: { userRole: role, claimsApplied },
  });
}

// Account status is only a label until identity enforces it, so every
// accountStatus transition is mirrored onto the Firebase Auth account:
// `suspended` / `banned` disable the account and revoke outstanding refresh
// tokens, `active` re-enables it. Disabling is what actually locks the user out
// — Firestore rules and the callables both reject a disabled identity, and the
// revoke invalidates sessions that are already signed in rather than waiting
// for a natural token expiry.
//
// Auth is updated BEFORE the Firestore write so a failure aborts the whole
// operation instead of leaving a "suspended" row over a live account. A uid
// with no Auth record (seeded/synthetic directory rows) is not an error: the
// Firestore write still proceeds. The resolved lockout state is returned so the
// caller can record it in the audit trail.
// The single definition of "this accountStatus locks the user out", shared by
// the Auth sync below and the avatar takedown wiring further down this file
// (setUserAccountStatus/setUserModeration), so the two never disagree about
// which transitions are a suspension/ban.
export function isBlockingAccountStatus(status: string): boolean {
  return status === "suspended" || status === "banned";
}

async function syncAuthAccountState(
  uid: string,
  status: string,
): Promise<boolean | null> {
  const disabled = isBlockingAccountStatus(status);
  const auth = getAdminAuth();

  try {
    await auth.updateUser(uid, { disabled });

    if (disabled) {
      await auth.revokeRefreshTokens(uid);
    }

    return disabled;
  } catch (error) {
    if ((error as { code?: string }).code === "auth/user-not-found") {
      return null;
    }

    throw error;
  }
}

export async function setUserAccountStatus(
  uid: string,
  status: string,
  actorEmail: string,
): Promise<void> {
  const db = getAdminDb();

  const authDisabled = await syncAuthAccountState(uid, status);

  await db
    .collection(USERS)
    .doc(uid)
    .set(
      { accountStatus: status, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

  await appendAuditLog(db, {
    actor: actorEmail,
    action: "account-status-change",
    targetType: "user",
    targetId: uid,
    detail: `Set accountStatus to ${status}${describeAuthEffect(authDisabled)}`,
  });

  // A suspended/banned runner's face must not keep serving indefinitely from
  // the avatar's Storage download token just because this path only touches
  // Auth + accountStatus. Best-effort: the lockout above is already
  // committed and is the more important control, so a takedown failure here
  // must never surface as a failed suspension.
  if (isBlockingAccountStatus(status)) {
    await clearAvatarOnAccountLockoutBestEffort(
      db,
      uid,
      actorEmail,
      `Account status set to ${status}`,
    );
  }
}

// Human-readable suffix describing what happened to the Auth account, so the
// audit entry distinguishes "locked out" from "status recorded only".
function describeAuthEffect(authDisabled: boolean | null): string {
  if (authDisabled === null) {
    return " (no Firebase Auth account; sign-in state unchanged)";
  }

  return authDisabled
    ? " (Firebase Auth account disabled, sessions revoked)"
    : " (Firebase Auth account enabled)";
}

// --- user subscription + moderation (users/{uid}) --------------------------
//
// Two privileged, audited per-user operational domains, both merge-written to
// the same `users/{uid}` document that setUserRole()/setUserAccountStatus()
// target above. Every call requires a non-empty reason and records a full
// before/after audit entry so the effect and its justification are always
// traceable. Reached only through requireAdmin()-gated server actions in
// src/lib/actions/admin.ts — the client app never writes these fields
// directly.

export type UserSubscriptionStatus = "basic" | "premium";

export type UserModerationAction = "warn" | "suspend" | "ban" | "restore";

// Merge-writes `subscriptionStatus` on users/{uid}. Subscription status gates
// Basic/Premium feature access only; it never affects XP, rank, or
// leaderboard score.
//
// Premium is a term, not a permanent flag. `expiresAt` records when an
// admin-granted Premium lapses; the scheduled `expireSubscriptions` backend job
// materialises the downgrade back to `basic` when that instant passes. The
// downgrade has to be materialised rather than evaluated on read because
// firestore.rules `isPremiumUser()` can only compare the stored status — it
// cannot compute an expiry. A null `expiresAt` means "no expiry", which is the
// pre-existing behaviour for every already-stored document.
//
// Basic never carries an expiry, so switching to basic always clears it.
export async function setUserSubscription(
  uid: string,
  status: UserSubscriptionStatus,
  adminEmail: string,
  reason: string,
  before: { subscriptionStatus: string | null; subscriptionExpiresAt: string | null },
  expiresAt: Date | null,
): Promise<void> {
  const db = getAdminDb();

  const nextExpiresAt = status === "premium" ? expiresAt : null;

  await db
    .collection(USERS)
    .doc(uid)
    .set(
      {
        subscriptionStatus: status,
        subscriptionExpiresAt:
          nextExpiresAt === null ? null : Timestamp.fromDate(nextExpiresAt),
        subscriptionSource: "admin-override",
        subscriptionUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  const after = {
    subscriptionStatus: status,
    subscriptionExpiresAt: nextExpiresAt?.toISOString() ?? null,
  };

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "user.subscription.update",
    targetType: "user",
    targetId: uid,
    detail:
      `Set subscriptionStatus to ${status} for user ${uid}: ${reason}` +
      (after.subscriptionExpiresAt === null
        ? status === "premium"
          ? " (no expiry)"
          : ""
        : ` (expires ${after.subscriptionExpiresAt})`),
    changedFields:
      before.subscriptionExpiresAt === after.subscriptionExpiresAt
        ? ["subscriptionStatus"]
        : ["subscriptionStatus", "subscriptionExpiresAt"],
    before,
    after,
  });
}

// Maps a moderation action to the resulting accountStatus, merge-writes it
// (except for "warn", which records the event without changing state), and
// appends an audit entry scoped to `user.moderation.<action>`.
export async function setUserModeration(
  uid: string,
  action: UserModerationAction,
  adminEmail: string,
  reason: string,
  before: { accountStatus: string | null },
): Promise<void> {
  const db = getAdminDb();

  const nextStatus: string | null =
    action === "suspend"
      ? "suspended"
      : action === "ban"
        ? "banned"
        : action === "restore"
          ? "active"
          : before.accountStatus ?? "active";

  let authDisabled: boolean | null = null;

  if (action !== "warn") {
    // Same identity-layer enforcement as setUserAccountStatus(): Auth first, so
    // a failure aborts before the status is recorded.
    authDisabled = await syncAuthAccountState(uid, nextStatus ?? "active");

    await db
      .collection(USERS)
      .doc(uid)
      .set(
        { accountStatus: nextStatus, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
  }

  await appendAuditLog(db, {
    actor: adminEmail,
    action: `user.moderation.${action}`,
    targetType: "user",
    targetId: uid,
    detail:
      `Applied moderation action "${action}" to user ${uid}: ${reason}` +
      (action === "warn" ? "" : describeAuthEffect(authDisabled)),
    changedFields: action === "warn" ? [] : ["accountStatus"],
    before,
    after:
      action === "warn"
        ? before
        : { accountStatus: nextStatus, authDisabled },
  });

  // Same avatar takedown wiring as setUserAccountStatus() above, so a
  // "suspend"/"ban" moderation action locks out the runner's photo exactly
  // like the direct account-status toggle does. "warn" and "restore" are not
  // blocking transitions and must not trigger this.
  if (nextStatus !== null && isBlockingAccountStatus(nextStatus)) {
    await clearAvatarOnAccountLockoutBestEffort(
      db,
      uid,
      adminEmail,
      `Moderation action "${action}": ${reason}`,
    );
  }
}

// --- avatar takedown (userProfiles/{uid} avatarXxx fields) ------------------
//
// The avatar object is served through a Firebase Storage download token,
// which bypasses Storage security rules entirely, so deleting the Cloud
// Storage object is the ONLY real enforcement a takedown has — clearing the
// Firestore field alone leaves the photo fetchable by anyone still holding
// the URL. A profile carries two live object paths: avatarObjectPath (the
// current generation) and avatarPreviousObjectPath (the previous generation,
// deliberately kept servable so hourly leaderboard snapshots referencing it
// do not 404 after a replace) — a takedown must delete BOTH.
//
// clearUserAvatarFields() below is the ONE shared routine both the explicit
// admin "clear avatar" action (clearUserAvatar()) and the suspend/ban wiring
// in setUserAccountStatus()/setUserModeration() above call, so the two paths
// can never drift out of sync with each other.

export type AvatarPathOutcome = "deleted" | "missing" | "skipped-invalid";

export type ClearUserAvatarResult = {
  hadAvatar: boolean;
  currentPathOutcome: AvatarPathOutcome | null;
  previousPathOutcome: AvatarPathOutcome | null;
};

type StoredAvatarFields = {
  avatarUrl: string | null;
  avatarObjectPath: string | null;
  avatarPreviousObjectPath: string | null;
};

// Deletes a single avatar Storage object, or reports why it did not. Also
// validates with isAvatarObjectPath() here, in addition to
// deleteAvatarObject()'s own internal check: an invalid path must never even
// reach the Storage delete call, so that fact is directly assertable against
// the storage helper in tests, not merely inferred from its return value. A
// genuine Storage error is not swallowed into a "skipped" outcome — it is
// thrown, because callers must not clear a Firestore field pointing at an
// object whose deletion outcome is unknown.
async function deleteAvatarPathIfPresent(
  path: string | null,
): Promise<AvatarPathOutcome | null> {
  if (path === null) {
    return null;
  }

  if (!isAvatarObjectPath(path)) {
    return "skipped-invalid";
  }

  const result = await deleteAvatarObject(path);

  if (result.ok) {
    return result.existed ? "deleted" : "missing";
  }

  if (result.reason === "invalid-path") {
    return "skipped-invalid";
  }

  throw new Error(`Failed to delete avatar object ${path}: ${result.error}`);
}

// Deletes both Storage objects, then clears all four avatarXxx fields on
// userProfiles/{uid} in a single merge write.
//
// Order matters: the Storage objects are deleted FIRST, and the Firestore
// fields are cleared only afterwards. If the field clear below throws after
// the deletes already succeeded, the app simply degrades to the initials
// fallback on the next 404 read — the safe direction. Doing this in the
// opposite order and having a delete fail afterwards would instead leave a
// live, still-served object with no path recorded anywhere on the profile —
// unreachable by any future takedown attempt.
async function clearUserAvatarFields(
  db: Firestore,
  uid: string,
): Promise<
  ClearUserAvatarResult & { before: StoredAvatarFields; avatarUpdatedAtBefore: string | null }
> {
  const ref = db.collection(USER_PROFILES).doc(uid);
  const snapshot = await ref.get();
  const data = snapshot.data();

  const avatarUrl = data ? readString(data, "avatarUrl") : null;
  const avatarObjectPath = data ? readString(data, "avatarObjectPath") : null;
  const avatarPreviousObjectPath = data
    ? readString(data, "avatarPreviousObjectPath")
    : null;
  const avatarUpdatedAtBefore = data ? toIso(data["avatarUpdatedAt"]) : null;

  const before: StoredAvatarFields = {
    avatarUrl,
    avatarObjectPath,
    avatarPreviousObjectPath,
  };
  const hadAvatar = Boolean(
    avatarUrl || avatarObjectPath || avatarPreviousObjectPath,
  );

  const currentPathOutcome = await deleteAvatarPathIfPresent(avatarObjectPath);
  const previousPathOutcome = await deleteAvatarPathIfPresent(
    avatarPreviousObjectPath,
  );

  await ref.set(
    {
      avatarUrl: FieldValue.delete(),
      avatarObjectPath: FieldValue.delete(),
      avatarPreviousObjectPath: FieldValue.delete(),
      avatarUpdatedAt: FieldValue.delete(),
    },
    { merge: true },
  );

  return {
    before,
    avatarUpdatedAtBefore,
    hadAvatar,
    currentPathOutcome,
    previousPathOutcome,
  };
}

function describeAvatarPathOutcome(
  path: string | null,
  outcome: AvatarPathOutcome | null,
): string {
  if (path === null) {
    return "none stored";
  }

  switch (outcome) {
    case "deleted":
      return `deleted ${path}`;
    case "missing":
      return `already missing: ${path}`;
    case "skipped-invalid":
      return `SKIPPED (not a valid avatar object path): ${path}`;
    default:
      return path;
  }
}

// Explicit admin takedown: clears a user's avatar and appends a full
// before/after audited log entry. `auditAction` lets callers (the standalone
// admin action vs. the suspend/ban wiring below) record distinct action
// names while sharing this one implementation.
export async function clearUserAvatar(
  uid: string,
  adminEmail: string,
  reason: string,
  auditAction: string,
): Promise<ClearUserAvatarResult> {
  const db = getAdminDb();
  const { before, avatarUpdatedAtBefore, hadAvatar, currentPathOutcome, previousPathOutcome } =
    await clearUserAvatarFields(db, uid);

  await appendAuditLog(db, {
    actor: adminEmail,
    action: auditAction,
    targetType: "user",
    targetId: uid,
    detail:
      `Cleared avatar for user ${uid}: ${reason} ` +
      `(current: ${describeAvatarPathOutcome(before.avatarObjectPath, currentPathOutcome)}; ` +
      `previous: ${describeAvatarPathOutcome(before.avatarPreviousObjectPath, previousPathOutcome)})`,
    changedFields: [
      "avatarUrl",
      "avatarObjectPath",
      "avatarPreviousObjectPath",
      "avatarUpdatedAt",
    ],
    before: { ...before, avatarUpdatedAt: avatarUpdatedAtBefore },
    after: {
      avatarUrl: null,
      avatarObjectPath: null,
      avatarPreviousObjectPath: null,
      avatarUpdatedAt: null,
    },
  });

  return { hadAvatar, currentPathOutcome, previousPathOutcome };
}

// Runs the shared avatar takedown when a moderation transition locks an
// account out, without ever letting a Storage/Firestore failure abort the
// suspension/ban itself — the identity lockout is already committed by the
// time this runs and is the more important control. A failure here is still
// recorded as its own audit entry (and a console warning), so it stays
// visible without hiding the fact that the account lockout succeeded.
async function clearAvatarOnAccountLockoutBestEffort(
  db: Firestore,
  uid: string,
  actorEmail: string,
  reason: string,
): Promise<void> {
  try {
    await clearUserAvatar(uid, actorEmail, reason, "user.avatar.clearOnLockout");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(
      `[firestore] Avatar takedown failed while locking out user ${uid}.`,
      error,
    );
    await appendAuditLog(db, {
      actor: actorEmail,
      action: "user.avatar.clearOnLockout.failed",
      targetType: "user",
      targetId: uid,
      detail: `Avatar takedown failed while applying "${reason}" to user ${uid}: ${message}`,
    });
  }
}

// --- user progression (userProfiles/{uid} totalXp/level/monthlyXp) ---------
//
// Direct per-user progression administration is a privileged, audited
// override path (e.g. correcting a miscalculated XP award) — not a normal
// client capability. Firestore rules already deny client writes to these
// fields; only this Admin-SDK path, reached exclusively through
// requireAdmin()-gated server actions in src/lib/actions/admin.ts, can change
// them, and every write is fully audited with an explicit action, the
// changed fields, and a before/after snapshot. The field names mirror what
// Cloud Functions itself persists in
// functions/src/progression/progressionAudit.ts (profileProgressionData).

export async function getUserProgression(
  uid: string,
): Promise<UserProgressionFields> {
  const db = getAdminDb();
  const snapshot = await db.collection(USER_PROFILES).doc(uid).get();
  const data = snapshot.data();

  return {
    totalXp: data ? readNumber(data, "totalXp") : null,
    level: data ? readNumber(data, "level") : null,
    monthlyXp: data ? readNumber(data, "monthlyXp") : null,
  };
}

// The Singapore month key (`YYYY-MM`) the backend buckets monthly progression
// and leaderboard contributions into. Mirrors currentSingaporeMonthKey() in
// functions/src/leaderboard/monthlyLeaderboardPeriod.ts. Exported so
// src/lib/actions/admin.ts can reuse it as the default recalculation period
// key instead of duplicating the calculation.
export function currentSingaporeMonthKey(now: Date): string {
  return new Date(now.getTime() + 8 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 7);
}

// Mirrors leaderboardContributionId() in
// functions/src/leaderboard/monthlyLeaderboard.ts.
function leaderboardContributionId(uid: string, periodKey: string): string {
  return `${uid}_monthly_${periodKey}`;
}

// Applies an admin XP correction to the user's monthly leaderboard
// contribution.
//
// Leaderboard standings are NOT derived from userProfiles.totalXp — the hourly
// refreshLeaderboardSnapshots job ranks users by
// `leaderboardContributions/{uid}_monthly_{periodKey}.scoreXp`, which
// completeRun increments per validated run. A correction that only rewrote the
// profile therefore never reached the leaderboard at all.
//
// The adjustment runs in a transaction because the score must be clamped at
// zero, which FieldValue.increment() cannot express. When no contribution
// document exists for the current period the adjustment is skipped rather than
// synthesised: building one requires the backend's versioned region/league
// derivation, and a user with no contribution this period is not ranked anyway
// — their next validated run creates it from the already-corrected totals.
// Returns what happened so the audit entry records it.
async function adjustLeaderboardContribution(input: {
  db: Firestore;
  uid: string;
  periodKey: string;
  xpDelta: number;
  progressionEventId: string;
  // The contribution carries its own copy of the runner's level/division, taken
  // from the profile at run time and rendered directly on the leaderboard row.
  // A correction that moves the user across a level (or league) boundary would
  // otherwise leave the board showing the pre-correction badge until their next
  // run rewrites it.
  display: {
    readonly levelLabel: string;
    readonly divisionKey: string;
    readonly divisionLabel: string;
  };
}): Promise<{ applied: boolean; scoreXp: number | null }> {
  const ref = input.db
    .collection(LEADERBOARD_CONTRIBUTIONS)
    .doc(leaderboardContributionId(input.uid, input.periodKey));

  return input.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);

    if (!snapshot.exists) {
      return { applied: false, scoreXp: null };
    }

    const currentScore = readNumber(snapshot.data() ?? {}, "scoreXp") ?? 0;
    const nextScore = Math.max(0, currentScore + input.xpDelta);

    transaction.set(
      ref,
      {
        scoreXp: nextScore,
        levelLabel: input.display.levelLabel,
        divisionKey: input.display.divisionKey,
        divisionLabel: input.display.divisionLabel,
        sourceProgressionEventIds: FieldValue.arrayUnion(
          input.progressionEventId,
        ),
      },
      { merge: true },
    );

    return { applied: true, scoreXp: nextScore };
  });
}

export async function setUserProgression(
  uid: string,
  fields: Partial<UserProgressionFields>,
  adminEmail: string,
  auditAction: string,
  before: UserProgressionFields,
  reason: string,
  // The stored config/progression, so the derived labels and division match
  // what Cloud Functions will recompute on the user's next run. Callers must
  // pass the live document, not the hardcoded defaults.
  config: ProgressionConfig,
): Promise<void> {
  const db = getAdminDb();
  const now = new Date();
  const periodKey = currentSingaporeMonthKey(now);

  const xpDelta =
    fields.totalXp === undefined || fields.totalXp === null
      ? 0
      : fields.totalXp - (before.totalXp ?? 0);

  // `monthlyXp` on the profile is derived, not owned: the backend recomputes it
  // as sumMonthlyXp() over that month's progressionEvents on the next run, so a
  // value written here in isolation is silently discarded. Deriving it the same
  // way the backend will keeps the displayed value and the eventual recomputed
  // value identical. sumMonthlyXp() counts positive xpDelta only, so a negative
  // correction leaves monthlyXp untouched — matching the backend rather than
  // drifting from it.
  const derivedMonthlyXp =
    fields.monthlyXp !== undefined
      ? fields.monthlyXp
      : xpDelta > 0
        ? (before.monthlyXp ?? 0) + xpDelta
        : undefined;

  const writtenFields: Partial<UserProgressionFields> = {
    ...fields,
    ...(derivedMonthlyXp === undefined ? {} : { monthlyXp: derivedMonthlyXp }),
  };

  const after: UserProgressionFields = { ...before, ...writtenFields };

  // The app renders the derived labels, not the raw numbers, and Cloud
  // Functions rewrites all of them on every completed run. Writing only
  // totalXp/level/monthlyXp would leave a corrected profile showing the old
  // "Level 4" / "350 XP" until the user's next run, so derive the same fields
  // here from the same curve.
  const displayFields = deriveProgressionDisplayFields(
    {
      totalXp: after.totalXp ?? 0,
      level: after.level ?? 1,
      monthlyXp: after.monthlyXp ?? 0,
    },
    config,
  );

  let leaderboard: { applied: boolean; scoreXp: number | null } = {
    applied: false,
    scoreXp: null,
  };
  let progressionEventId: string | null = null;

  // A compensating progression event makes the correction part of the same
  // append-only history the backend already reconciles against, so it survives
  // recomputation instead of being overwritten by the next completed run.
  if (xpDelta !== 0) {
    const eventRef = db.collection(PROGRESSION_EVENTS).doc();
    progressionEventId = eventRef.id;

    await eventRef.set({
      ownerUid: uid,
      eventType: "admin_xp_correction",
      status: "awarded",
      createdAt: now.toISOString(),
      xpDelta,
      monthlyPeriod: periodKey,
      previousTotalXp: before.totalXp ?? 0,
      nextTotalXp: after.totalXp ?? 0,
      previousLevel: before.level ?? null,
      nextLevel: after.level ?? null,
      countsTowardLeaderboard: true,
      reason,
      auditAction,
      actor: adminEmail,
    });

    leaderboard = await adjustLeaderboardContribution({
      db,
      uid,
      periodKey,
      xpDelta,
      progressionEventId,
      display: {
        levelLabel: displayFields.levelLabel,
        divisionKey: displayFields.divisionKey,
        divisionLabel: displayFields.divisionLabel,
      },
    });
  }

  await db
    .collection(USER_PROFILES)
    .doc(uid)
    .set(
      {
        ...writtenFields,
        ...displayFields,
        progressionUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  await appendAuditLog(db, {
    actor: adminEmail,
    action: auditAction,
    targetType: "user",
    targetId: uid,
    detail:
      `${auditAction} for user ${uid}: ${reason}` +
      (xpDelta === 0
        ? ""
        : leaderboard.applied
          ? ` (leaderboard contribution for ${periodKey} adjusted to ${leaderboard.scoreXp} XP)`
          : ` (no ${periodKey} leaderboard contribution to adjust)`),
    changedFields: Object.keys(writtenFields),
    before,
    after: { ...after, progressionEventId, leaderboardScoreXp: leaderboard.scoreXp },
  });
}

// --- account deletion commands ------------------------------------------------
//
// Read-only health probe over the queue that erases a runner's data
// (functions/src/account/accountDeletionCommand.ts). The console never writes
// here: re-driving a command is a deliberate operator action, not something a
// dashboard should do on its own.
//
// This exists because a failed erase used to be invisible. The trigger is
// `onDocumentCreated` and "failed" is a terminal status, so nothing retries;
// the only signal was a generic Cloud Functions error group, and the System
// health component reading those is scoped to the last 24 hours. The failure
// state, however, is permanent — it means a runner who asked to be deleted
// still has data in Firestore. Two production deletions sat failed for 7 and 5
// days behind exactly that gap.

export type AccountDeletionCommandRow = {
  uid: string;
  status: string;
  requestedAt: string | null;
  completedSteps: number;
  error: string | null;
};

export async function listAccountDeletionCommands(): Promise<
  AccountDeletionCommandRow[]
> {
  const db = getAdminDb();
  const snapshot = await db.collection(ACCOUNT_DELETION_COMMANDS).get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    const steps = data["completedSteps"];
    return {
      // The document id IS the uid — the trigger treats it as the single
      // instruction it trusts — so it is the reliable source even if the
      // mirrored field is somehow absent.
      uid: doc.id,
      status: readString(data, "status") ?? "pending",
      requestedAt: toIso(data["requestedAt"]),
      completedSteps: Array.isArray(steps) ? steps.length : 0,
      error: readString(data, "error"),
    };
  });
}

// --- reports ----------------------------------------------------------------

function mapReportRow(
  snapshot: QueryDocumentSnapshot<DocumentData>,
): ReportRow {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    reporterUid: readString(data, "reporterUid"),
    targetType: readString(data, "targetType"),
    targetId: readString(data, "targetId"),
    reason: readString(data, "reason"),
    description: readString(data, "description"),
    resolutionStatus: readString(data, "resolutionStatus") ?? "pending",
    resolutionNote: readString(data, "resolutionNote"),
    createdAt: toIso(data["createdAt"]),
    source: readString(data, "source"),
  };
}

export async function listReports(
  resolutionStatus?: ReportResolutionStatus,
): Promise<ReportRow[]> {
  const db = getAdminDb();
  const snapshot = await db.collection(REPORTS).get();
  const rows = snapshot.docs.map(mapReportRow);

  if (!resolutionStatus) {
    return rows;
  }

  // Filter in-memory: reports created by the app carry no resolutionStatus
  // until an admin sets one, so treat a missing value as "pending".
  return rows.filter((row) => row.resolutionStatus === resolutionStatus);
}

export async function setReportResolution(
  reportId: string,
  resolutionStatus: ReportResolutionStatus,
  adminEmail: string,
  note?: string,
): Promise<void> {
  const db = getAdminDb();

  await db
    .collection(REPORTS)
    .doc(reportId)
    .set(
      {
        resolutionStatus,
        resolutionNote: note ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "report-resolution",
    targetType: "report",
    targetId: reportId,
    detail: `Set resolutionStatus to ${resolutionStatus}`,
  });
}

// Creates a `reports` document from an anomaly-detection finding (see
// getLiveSuspiciousScores() in src/lib/admin/live-data.ts) so the "Send to
// Exception Queue" action on the Leaderboard Oversight page produces a real,
// reviewable case instead of only removing a row from local UI state.
//
// `targetType: "activity"` is deliberate: TARGET_TYPE_TO_CASE in
// src/lib/admin/live-data.ts maps it to the "suspicious-xp" ExceptionType,
// which is exactly what this finding is. `reporterUid` records the admin who
// triggered the flag (not a runner) so the audit trail is honest about who
// actually filed it. Returns the new report id so the caller can log it.
export async function createLeaderboardReport(input: {
  ownerUid: string;
  contributionId: string;
  reason: string;
  description: string;
  adminEmail: string;
  adminUid: string;
}): Promise<string> {
  const db = getAdminDb();

  const ref = await db.collection(REPORTS).add({
    reporterUid: input.adminUid,
    targetType: "activity",
    targetId: input.contributionId,
    reason: input.reason,
    description: input.description,
    resolutionStatus: "pending",
    source: "anomaly-detection",
    createdAt: FieldValue.serverTimestamp(),
  });

  await appendAuditLog(db, {
    actor: input.adminEmail,
    action: "leaderboard.anomaly.flag",
    targetType: "report",
    targetId: ref.id,
    detail: `Flagged owner ${input.ownerUid} (evidence ${input.contributionId}) to the Exception Queue: ${input.reason}`,
  });

  return ref.id;
}

// --- feed-post moderation (feedPosts/{postId}, moderationCommands/{commandId}) --
//
// The Exception Queue's "Remove post" action for reported-feed-post cases.
// The admin console holds Admin SDK access only and cannot invoke Cloud
// Functions callables directly, so removal is a Firestore command-document
// handoff exactly like requestLeaderboardRecalculation() above: this write
// creates a `moderationCommands` document, the moderationCommandCreated
// Cloud Function trigger (functions/src/moderation/moderationCommand.ts)
// consumes it and performs the real removal, then merge-writes the outcome
// back onto the same document. getModerationCommand() below polls that
// outcome back for the console. The console never writes to `feedPosts`
// directly — content actions go only through this command collection.

// A `reports` document for a feed post never stores the post's author uid
// (only reporterUid/targetType/targetId — see the reports schema and
// functions/src/moderation/moderationCommand.ts), so the Exception Queue has
// to resolve it separately when loading cases. Returns null when the post no
// longer exists; the caller falls back to
// getModerationCommandRemovedAuthorUid() in that case.
export async function getFeedPostAuthorUid(
  postId: string,
): Promise<string | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(FEED_POSTS).doc(postId).get();

  if (!snapshot.exists) {
    return null;
  }

  return readString(snapshot.data() ?? {}, "authorUid");
}

// Fallback source for a feed post's author once the post itself is gone:
// functions/src/moderation/moderationCommand.ts deliberately writes
// `removedAuthorUid` onto ITS OWN command document when it removes a post,
// specifically so a later read like this one is not left with an
// unrecoverable author. Filters on a single field (`postId`) only, so no
// composite index is required. Multiple commands can exist for the same
// postId (e.g. a retried removal); the most recently completed one with a
// recorded author wins.
export async function getModerationCommandRemovedAuthorUid(
  postId: string,
): Promise<string | null> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(MODERATION_COMMANDS)
    .where("postId", "==", postId)
    .get();

  let latestAuthorUid: string | null = null;
  let latestCompletedAt = "";

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const authorUid = readString(data, "removedAuthorUid");

    if (!authorUid) {
      continue;
    }

    const completedAt = toIso(data["completedAt"]) ?? "";

    if (completedAt >= latestCompletedAt) {
      latestCompletedAt = completedAt;
      latestAuthorUid = authorUid;
    }
  }

  return latestAuthorUid;
}

// Only "removeFeedPost" is supported today — "restoreFeedPost" is explicitly
// out of scope for this capsule (see the trigger's own header comment).
export async function requestModerationCommand(
  kind: "removeFeedPost",
  postId: string,
  adminEmail: string,
): Promise<string> {
  const db = getAdminDb();

  const ref = await db.collection(MODERATION_COMMANDS).add({
    kind,
    postId,
    requestedBy: adminEmail,
    requestedAt: FieldValue.serverTimestamp(),
    status: "pending",
  });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "moderation.command.request",
    targetType: "moderation-command",
    targetId: ref.id,
    detail: `Requested feed post removal for post ${postId}`,
  });

  return ref.id;
}

// Reads back the outcome the moderationCommandCreated trigger wrote onto the
// command document. Returns null when the document does not exist (a
// stale/unknown commandId) so the caller can degrade instead of inventing a
// status.
export async function getModerationCommand(
  commandId: string,
): Promise<ModerationCommandRow | null> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(MODERATION_COMMANDS)
    .doc(commandId)
    .get();

  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data() ?? {};

  return {
    status: readString(data, "status") ?? "pending",
    error: readString(data, "error"),
    removedAuthorUid: readString(data, "removedAuthorUid"),
    completedAt: toIso(data["completedAt"]),
  } satisfies ModerationCommandRow;
}

// --- feedback -----------------------------------------------------------------
//
// New feedback documents are written only by the submitFeedback Cloud Function
// (Admin SDK). Status/note triage is written here by the admin console, also
// via the Admin SDK, mirroring setReportResolution(): a merge-write plus an
// audit-log entry. Firestore rules deny all client (non-Admin-SDK) read/write
// on this collection either way.

function mapFeedbackRow(
  snapshot: QueryDocumentSnapshot<DocumentData>,
): FeedbackRow {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    uid: readString(data, "uid"),
    category: readString(data, "category"),
    message: readString(data, "message"),
    summary: readString(data, "summary"),
    severity: readString(data, "severity") ?? "low",
    status: readString(data, "status") ?? "new",
    duplicateCount: readNumber(data, "duplicateCount"),
    note: readString(data, "note"),
    closed: data["closed"] === true,
    receivedAt: toIso(data["receivedAt"]),
  };
}

export async function listFeedback(): Promise<FeedbackRow[]> {
  const db = getAdminDb();
  const snapshot = await db.collection(FEEDBACK).get();
  const rows = snapshot.docs.map(mapFeedbackRow);

  // Sort in-memory (newest first) rather than orderBy("receivedAt") so this
  // does not require a composite index on the emulator — mirrors listReports().
  rows.sort((left, right) =>
    (right.receivedAt ?? "").localeCompare(left.receivedAt ?? ""),
  );

  return rows;
}

export async function setFeedbackTriage(
  feedbackId: string,
  status: FeedbackTriageStatus,
  adminEmail: string,
  note?: string,
): Promise<void> {
  const db = getAdminDb();

  const update: Record<string, unknown> = {
    status,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (note !== undefined) {
    update.note = note;
  }

  await db.collection(FEEDBACK).doc(feedbackId).set(update, { merge: true });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "feedback-triage",
    targetType: "feedback",
    targetId: feedbackId,
    detail:
      note !== undefined
        ? `Set status to ${status} and updated note`
        : `Set status to ${status}`,
  });
}

// Closing hides an item from the default admin inbox view without deleting
// it or touching its triage status; reopening un-hides it. Independent of
// setFeedbackTriage() above, which owns the status/note workflow fields.
export async function setFeedbackClosed(
  feedbackId: string,
  closed: boolean,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();

  await db
    .collection(FEEDBACK)
    .doc(feedbackId)
    .set(
      { closed, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

  await appendAuditLog(db, {
    actor: adminEmail,
    action: closed ? "feedback-close" : "feedback-reopen",
    targetType: "feedback",
    targetId: feedbackId,
    detail: closed ? "Closed feedback item" : "Reopened closed feedback item",
  });
}

// --- error groups --------------------------------------------------------------
//
// errorGroups/{fingerprint} documents are written by the reportAppError
// Cloud Function for mobile-originated errors and by the backend
// reportBackendError reporter for Cloud Functions faults (Admin SDK in both
// cases) — see ErrorGroupDocument in functions/src/errors/errorGroupStore.ts
// for the authoritative shape shared by both writers, distinguished by the
// `source` field ("mobile" | "functions"). Status/note triage is written
// here by the admin console, also via the Admin SDK, mirroring
// setFeedbackTriage() above: a merge-write plus an audit-log entry. Firestore
// rules deny all client (non-Admin-SDK) read/write on this collection either
// way (see the explicit-deny stanza in firestore.rules).

function mapErrorGroupRow(
  snapshot: QueryDocumentSnapshot<DocumentData>,
): ErrorGroupRow {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    title: readString(data, "title"),
    errorType: readString(data, "errorType"),
    screen: readString(data, "screen"),
    appVersion: readString(data, "appVersion"),
    os: readString(data, "os"),
    platform: readString(data, "platform"),
    // Read raw here; documents written before this field existed have no
    // `source` at all. The narrow "mobile" | "functions" coercion (defaulting
    // absent/unrecognized values to "mobile") happens one layer up in
    // src/lib/admin/live-data.ts#toErrorSource, mirroring how `severity` and
    // `status` are coerced there too.
    source: readString(data, "source"),
    occurrences: readNumber(data, "occurrences"),
    // Doc field is `affectedUserCount`; the console type calls this `affectedUsers`.
    affectedUsers: readNumber(data, "affectedUserCount"),
    severity: readString(data, "severity"),
    status: readString(data, "status") ?? "new",
    firstSeenAt: toIso(data["firstSeenAt"]),
    lastSeenAt: toIso(data["lastSeenAt"]),
    stackSummary: readString(data, "stackSummary"),
    sanitized: data["sanitized"] === true,
    note: readString(data, "note"),
  };
}

// errorGroups is one document per distinct fingerprint (see the collection
// comment above), not one per occurrence, so its size is bounded by how many
// *distinct* errors the app and Cloud Functions have ever produced — not by
// error volume. Even a busy environment realistically stays in the dozens-
// to-low-hundreds of distinct groups. ERROR_GROUPS_READ_LIMIT is a defensive
// ceiling with large headroom over that, not a pagination page size: it
// exists to bound the read, not to routinely apply. Because
// getErrorGroups()/getLiveErrorGroups() feed both the /admin/errors
// StatCards (presented as totals across all groups) and every table filter,
// silently hitting this cap would quietly change what those totals mean —
// so callers must treat `rows.length === ERROR_GROUPS_READ_LIMIT` as a
// signal to surface a truncation notice rather than ignore it (see
// src/app/admin/errors/page.tsx).
export const ERROR_GROUPS_READ_LIMIT = 2000;

export async function listErrorGroups(): Promise<ErrorGroupRow[]> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(ERROR_GROUPS)
    .orderBy("lastSeenAt", "desc")
    .limit(ERROR_GROUPS_READ_LIMIT)
    .get();
  return snapshot.docs.map(mapErrorGroupRow);
}

export async function setErrorGroupTriage(
  groupId: string,
  status: ErrorGroupTriageStatus,
  adminEmail: string,
  note?: string,
): Promise<void> {
  const db = getAdminDb();

  const update: Record<string, unknown> = {
    status,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (note !== undefined) {
    update.note = note;
  }

  await db.collection(ERROR_GROUPS).doc(groupId).set(update, { merge: true });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "error-triage",
    targetType: "error",
    targetId: groupId,
    detail:
      note !== undefined
        ? `Set status to ${status} and updated note`
        : `Set status to ${status}`,
  });
}

// --- admin notifications ----------------------------------------------------
//
// adminNotifications/{id} documents are backend-written attention items for
// the admin overview page (e.g. a new critical error group, a stale-report
// escalation). Dismissal is written here by the admin console via the Admin
// SDK, mirroring setReportResolution(): a merge-write plus an audit-log entry.

function mapAdminNotificationRow(
  snapshot: QueryDocumentSnapshot<DocumentData>,
): AdminNotificationRow {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    kind: readString(data, "kind"),
    severity: readString(data, "severity"),
    title: readString(data, "title"),
    detail: readString(data, "detail"),
    href: readString(data, "href"),
    createdAt: toIso(data["createdAt"]),
    status: readString(data, "status") ?? "active",
  };
}

// Filters "dismissed" rows out in memory (rather than a Firestore
// `.where("status", "!=", "dismissed")`) so this read needs no composite
// index alongside the `.orderBy("createdAt", "desc")` — mirrors
// listConfigHistory()'s in-memory filter above.
export async function listAdminNotifications(
  limit = 20,
): Promise<AdminNotificationRow[]> {
  const db = getAdminDb();
  // Over-fetch before the in-memory dismissed-filter: notifications are never
  // deleted, so the `limit` newest docs can be entirely dismissed ones, which
  // would hide older still-active items. 5x is a pragmatic window, not a
  // guarantee — a TTL/cleanup pass is recorded as future work in the capsule.
  const snapshot = await db
    .collection(ADMIN_NOTIFICATIONS)
    .orderBy("createdAt", "desc")
    .limit(limit * 5)
    .get();

  return snapshot.docs
    .map(mapAdminNotificationRow)
    .filter((row) => row.status !== "dismissed")
    .slice(0, limit);
}

export async function dismissAdminNotification(
  id: string,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();

  await db
    .collection(ADMIN_NOTIFICATIONS)
    .doc(id)
    .set({ status: "dismissed", updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "admin-notification.dismiss",
    targetType: "adminNotification",
    targetId: id,
    detail: "Dismissed attention item",
  });
}

// --- leaderboard ------------------------------------------------------------

// Reads `topEntries`, the field the backend actually writes (see
// functions/src/leaderboard/monthlyLeaderboardPlanner.ts). There is no `uid`
// or numeric `rank` on the backend shape — only pre-formatted public labels.
function readEntries(data: DocumentData): LeaderboardEntry[] {
  const raw = data["topEntries"];
  if (!Array.isArray(raw)) {
    return [];
  }

  return raw.map((item): LeaderboardEntry => {
    const record: DocumentData =
      typeof item === "object" && item !== null
        ? (item as DocumentData)
        : {};
    return {
      publicAlias: readString(record, "publicAlias"),
      rankLabel: readString(record, "rankLabel"),
      scoreLabel: readString(record, "scoreLabel"),
      levelLabel: readString(record, "levelLabel"),
      divisionLabel: readString(record, "divisionLabel"),
      regionLabel: readString(record, "regionLabel"),
      score: readNumber(record, "score"),
    };
  });
}

// Shared index-metadata mapping for a `leaderboardSnapshots` document — the
// fields every reader of this collection needs, without the `topEntries`
// array. getLatestLeaderboardSnapshot(), listLeaderboardSnapshotSummaries(),
// and getLeaderboardSnapshotById() below all build on this single mapping so
// the field list only lives in one place.
function mapLeaderboardSnapshotSummary(
  id: string,
  data: DocumentData,
): LeaderboardSnapshotSummaryRow {
  return {
    id,
    periodKey: readString(data, "periodKey"),
    regionId: readString(data, "regionId"),
    divisionKey: readString(data, "divisionKey"),
    regionLabel: readString(data, "regionLabel"),
    divisionLabel: readString(data, "divisionLabel"),
    entryCount: readNumber(data, "entryCount"),
    generatedAt: toIso(data["generatedAt"]),
  } satisfies LeaderboardSnapshotSummaryRow;
}

// Full row (summary fields + topEntries + the remaining metadata) for a
// single `leaderboardSnapshots` document.
function mapLeaderboardSnapshotRow(
  id: string,
  data: DocumentData,
): LeaderboardSnapshotRow {
  return {
    ...mapLeaderboardSnapshotSummary(id, data),
    periodLabel: readString(data, "periodLabel"),
    buildId: readString(data, "buildId"),
    refreshesAt: toIso(data["refreshesAt"]),
    aggregationStatus: readString(data, "aggregationStatus"),
    entries: readEntries(data),
  } satisfies LeaderboardSnapshotRow;
}

export async function getLatestLeaderboardSnapshot(): Promise<LeaderboardSnapshotRow | null> {
  const db = getAdminDb();

  // Fetch snapshots and pick the newest in-memory to avoid needing an index on
  // the emulator; the collection is expected to be small.
  const snapshot = await db.collection(LEADERBOARD_SNAPSHOTS).get();

  if (snapshot.empty) {
    return null;
  }

  const rows = snapshot.docs.map((doc) =>
    mapLeaderboardSnapshotRow(doc.id, doc.data()),
  );

  rows.sort((left, right) => {
    const leftKey = right.generatedAt ?? right.periodKey ?? "";
    const rightKey = left.generatedAt ?? left.periodKey ?? "";
    return leftKey.localeCompare(rightKey);
  });

  return rows[0];
}

// Field projection for listLeaderboardSnapshotSummaries() below — exactly
// the fields mapLeaderboardSnapshotSummary() reads, so `.select()` avoids
// transferring `topEntries` (up to 10 entries per document) for every
// document in the collection.
const LEADERBOARD_SNAPSHOT_SUMMARY_FIELDS = [
  "periodKey",
  "regionId",
  "divisionKey",
  "regionLabel",
  "divisionLabel",
  "entryCount",
  "generatedAt",
] as const;

// Index metadata (no `topEntries`) for every `leaderboardSnapshots` document
// — backs the admin console's coverage view, which needs to know how much of
// the region x division grid has data without paying for ~1,100 documents x
// 10 entries each of `topEntries`. Uses `.select()` to project only the
// fields the summary needs off the wire.
export async function listLeaderboardSnapshotSummaries(): Promise<
  LeaderboardSnapshotSummaryRow[]
> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(LEADERBOARD_SNAPSHOTS)
    .select(...LEADERBOARD_SNAPSHOT_SUMMARY_FIELDS)
    .get();
  return snapshot.docs.map((doc) =>
    mapLeaderboardSnapshotSummary(doc.id, doc.data()),
  );
}

// Single `leaderboardSnapshots/{snapshotId}` document, including
// `topEntries`, for the read-only standings viewer. Returns null when no
// snapshot exists for that id — the normal case for most region x division
// combinations, which legitimately have no runners yet.
export async function getLeaderboardSnapshotById(
  snapshotId: string,
): Promise<LeaderboardSnapshotRow | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(LEADERBOARD_SNAPSHOTS).doc(snapshotId).get();

  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data();
  return data ? mapLeaderboardSnapshotRow(snapshot.id, data) : null;
}

// Single-document read of `leaderboardPeriods/monthly_current` — the entry
// point the mobile app reads first. Returns null when the document does not
// exist (an unseeded DB, or a database whose aggregation job has never
// completed a run) so the caller can degrade rather than invent a period.
export async function getLeaderboardCurrentPeriod(): Promise<LeaderboardCurrentPeriodRow | null> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(LEADERBOARD_PERIODS)
    .doc(CURRENT_PERIOD_DOC_ID)
    .get();

  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data() ?? {};

  return {
    periodType: readString(data, "periodType"),
    periodKey: readString(data, "periodKey"),
    periodLabel: readString(data, "periodLabel"),
    timezone: readString(data, "timezone"),
    refreshesAt: toIso(data["refreshesAt"]),
    buildId: readString(data, "buildId"),
    generatedAt: toIso(data["generatedAt"]),
    aggregationStatus: readString(data, "aggregationStatus"),
    updatedAt: toIso(data["updatedAt"]),
  } satisfies LeaderboardCurrentPeriodRow;
}

const LEADERBOARD_CURRENT_VIEW_STATUSES: readonly LeaderboardCurrentViewStatus[] = [
  "ranked",
  "unranked",
  "region_required",
  "ineligible_premium",
  "ineligible_min_runs",
];

// Per-status document counts over `leaderboardCurrentViews`, one document per
// user. Prefers a `.count()` aggregate query per status over reading every
// document (mirrors countUsers()/countActivitiesSince() below and
// recomputeFeedEngagementCount() in functions/), since this collection can
// have one document for every user in the app.
export async function countLeaderboardCurrentViewsByStatus(): Promise<LeaderboardCurrentViewStatusCounts> {
  const db = getAdminDb();

  const results = await Promise.all(
    LEADERBOARD_CURRENT_VIEW_STATUSES.map((status) =>
      db
        .collection(LEADERBOARD_CURRENT_VIEWS)
        .where("status", "==", status)
        .count()
        .get(),
    ),
  );

  const counts = {} as LeaderboardCurrentViewStatusCounts;
  LEADERBOARD_CURRENT_VIEW_STATUSES.forEach((status, index) => {
    counts[status] = results[index].data().count;
  });

  return counts;
}

// Reads the monthly aggregation lock document (see
// functions/src/leaderboard/monthlyLeaderboardWriter.ts) for the given
// period key. Returns null when no lock has ever been taken for that period
// — e.g. a freshly-seeded database, or a period whose first run has not
// started yet — so the caller can degrade rather than invent job status.
export async function getLeaderboardAggregationLock(
  periodKey: string,
): Promise<LeaderboardAggregationLockRow | null> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(LEADERBOARD_AGGREGATION_LOCKS)
    .doc(`monthly_${periodKey}`)
    .get();

  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data() ?? {};

  return {
    periodKey,
    buildId: readString(data, "buildId"),
    status: readString(data, "status") ?? "",
    startedAt: toIso(data["startedAt"]),
    completedAt: toIso(data["completedAt"]),
    failedAt: toIso(data["failedAt"]),
    leaseExpiresAt: toIso(data["leaseExpiresAt"]),
    updatedAt: toIso(data["updatedAt"]),
  } satisfies LeaderboardAggregationLockRow;
}

// The admin console holds Admin SDK access only and cannot invoke Cloud
// Functions callables, so "request a recalculation" is a Firestore
// command-document handoff instead of a callable call: this write creates the
// command, the leaderboardAdminCommandCreated Cloud Function trigger
// (functions/src/leaderboard/leaderboardAdminCommand.ts) consumes it and runs
// refreshMonthlyLeaderboardSnapshots() for real, then merge-writes the actual
// outcome back onto this same document. getLeaderboardCommand() below reads
// that outcome back so the console can render what really happened.
export async function requestLeaderboardRecalculation(
  periodKey: string,
  adminEmail: string,
): Promise<string> {
  const db = getAdminDb();

  const ref = await db.collection(LEADERBOARD_ADMIN_COMMANDS).add({
    command: "refresh",
    periodKey,
    requestedBy: adminEmail,
    requestedAt: FieldValue.serverTimestamp(),
    status: "pending",
  });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "leaderboard.recalculation.request",
    targetType: "leaderboard-command",
    targetId: ref.id,
    detail: `Requested a monthly leaderboard recalculation for ${periodKey}`,
  });

  return ref.id;
}

// Reads back the outcome the leaderboardAdminCommandCreated trigger wrote
// onto the command document. Returns null when the document does not exist
// (a stale/unknown commandId) so the caller can degrade instead of inventing
// a status.
export async function getLeaderboardCommand(
  commandId: string,
): Promise<LeaderboardCommandRow | null> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(LEADERBOARD_ADMIN_COMMANDS)
    .doc(commandId)
    .get();

  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data() ?? {};

  return {
    status: readString(data, "status") ?? "pending",
    error: readString(data, "error"),
    buildId: readString(data, "buildId"),
    snapshotCount: readNumber(data, "snapshotCount"),
    rankCount: readNumber(data, "rankCount"),
    currentViewCount: readNumber(data, "currentViewCount"),
    completedAt: toIso(data["completedAt"]),
  } satisfies LeaderboardCommandRow;
}

// Reads `leaderboardContributions` for a single monthly period. Mirrors the
// backend's own `.where("periodKey", "==", periodKey)` query in
// functions/src/leaderboard/monthlyLeaderboardWriter.ts, so it is
// index-served rather than requiring a new composite index. Read-only: the
// admin console never writes this collection, only flags entries from it for
// human review (see src/lib/admin/live-data.ts#getLiveSuspiciousScores).
export async function listLeaderboardContributions(
  periodKey: string,
): Promise<LeaderboardContributionRow[]> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(LEADERBOARD_CONTRIBUTIONS)
    .where("periodKey", "==", periodKey)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      ownerUid: readString(data, "ownerUid"),
      publicAlias: readString(data, "publicAlias"),
      regionId: readString(data, "regionId"),
      regionLabel: readString(data, "regionLabel"),
      planningAreaName: readString(data, "planningAreaName"),
      divisionKey: readString(data, "divisionKey"),
      divisionLabel: readString(data, "divisionLabel"),
      levelLabel: readString(data, "levelLabel"),
      periodKey: readString(data, "periodKey"),
      scoreXp: readNumber(data, "scoreXp"),
      eligible: readBoolean(data, "eligible"),
      eligibilityReason: readString(data, "eligibilityReason"),
      // Stored as a plain ISO string by the backend writer (not a Firestore
      // Timestamp) — readString(), not toIso(), mirrors that.
      lastProgressionAt: readString(data, "lastProgressionAt"),
      sourceProgressionEventIds: readStringArray(data, "sourceProgressionEventIds"),
      qualifyingRunCount: readNumber(data, "qualifyingRunCount"),
      mockSeedRunId: readString(data, "mockSeedRunId"),
    } satisfies LeaderboardContributionRow;
  });
}

// --- aggregate counts -------------------------------------------------------

export async function countUsers(): Promise<number> {
  const db = getAdminDb();
  const result = await db.collection(USERS).count().get();
  return result.data().count;
}

export async function countActivitiesSince(dateIso: string): Promise<number> {
  const db = getAdminDb();
  // startedAt is stored as an ISO string, so a lexicographic range filter works
  // and needs no composite index.
  const result = await db
    .collection(ACTIVITIES)
    .where("startedAt", ">=", dateIso)
    .count()
    .get();
  return result.data().count;
}

export async function countUsersBySubscription(): Promise<SubscriptionCounts> {
  const db = getAdminDb();
  const snapshot = await db.collection(USERS).get();

  const counts: SubscriptionCounts = {
    basic: 0,
    premium: 0,
    other: 0,
    total: 0,
  };

  for (const doc of snapshot.docs) {
    counts.total += 1;
    const status = readString(doc.data(), "subscriptionStatus");
    if (status === "basic") {
      counts.basic += 1;
    } else if (status === "premium") {
      counts.premium += 1;
    } else {
      counts.other += 1;
    }
  }

  return counts;
}

// `startedAtFrom`/`startedAtBefore` bound the scan to a half-open window of
// `activities.startedAt`, which the backend stores as a validated ISO-8601
// string (functions/src/run/validateRunPayload.ts) — so the range is a plain
// string comparison, served by the automatic single-field index. Supplying a
// window also switches the query to newest-first; without one the call keeps
// its original unordered `limit()` behaviour, which returns documents in
// document-id order rather than by recency.
export async function listActivitySummaries(options?: {
  limit?: number;
  startedAtFrom?: string;
  startedAtBefore?: string;
}): Promise<ActivitySummaryRow[]> {
  const db = getAdminDb();
  const limit = options?.limit ?? 50;

  let query: Query<DocumentData> = db.collection(ACTIVITIES);

  if (options?.startedAtFrom !== undefined) {
    query = query.where("startedAt", ">=", options.startedAtFrom);
  }

  if (options?.startedAtBefore !== undefined) {
    query = query.where("startedAt", "<", options.startedAtBefore);
  }

  if (options?.startedAtFrom !== undefined || options?.startedAtBefore !== undefined) {
    query = query.orderBy("startedAt", "desc");
  }

  const snapshot = await query.limit(limit).get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      ownerUid: readString(data, "ownerUid"),
      validationStatus: readString(data, "validationStatus"),
      distanceMeters: readNumber(data, "distanceMeters"),
      durationSeconds: readNumber(data, "durationSeconds"),
      startedAt: toIso(data["startedAt"]),
      createdAt: toIso(data["createdAt"]),
    } satisfies ActivitySummaryRow;
  });
}

// Distinct owner uids of activities whose startedAt falls in the half-open
// window [startIso, endIso) — used by the admin overview's monthly active
// users trend (see src/lib/admin/live-data.ts#getLiveActiveUsersTrend). A
// single-field range on startedAt (same ISO-string comparison as
// countActivitiesSince()/listActivitySummaries() above) plus
// .select("ownerUid") reads only the one field per document rather than the
// full activity. `cap` bounds the scan; a month with more than `cap`
// activities can therefore undercount its distinct-owner total, trading
// perfect accuracy for a bounded read.
export async function listActivityOwnerUidsInWindow(
  startIso: string,
  endIso: string,
  cap: number,
): Promise<string[]> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(ACTIVITIES)
    .where("startedAt", ">=", startIso)
    .where("startedAt", "<", endIso)
    .select("ownerUid")
    .limit(cap)
    .get();

  const ownerUids = new Set<string>();
  for (const doc of snapshot.docs) {
    const ownerUid = readString(doc.data(), "ownerUid");
    if (ownerUid) {
      ownerUids.add(ownerUid);
    }
  }

  return [...ownerUids];
}

// --- audit logs -------------------------------------------------------------

export async function listAuditLogs(options?: {
  limit?: number;
}): Promise<AuditLogRow[]> {
  const db = getAdminDb();
  const limit = options?.limit ?? 100;

  const snapshot = await db
    .collection(ADMIN_AUDIT_LOGS)
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      actor: readString(data, "actor"),
      action: readString(data, "action"),
      targetType: readString(data, "targetType"),
      targetId: readString(data, "targetId"),
      detail: readString(data, "detail"),
      createdAt: toIso(data["createdAt"]),
    } satisfies AuditLogRow;
  });
}

// --- config history (adminAuditLogs where targetType == "config") ------------
//
// Configuration history is not a separate collection: every config write made
// through setConfigDoc() already appends an audit entry carrying the full
// before/after payload. These readers recover that payload so the admin console
// can show a real change history and re-apply an earlier snapshot.

function readStringArray(data: DocumentData, key: string): string[] {
  const value = data[key];
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter((item): item is string => typeof item === "string");
}

function readPlainObject(
  data: DocumentData,
  key: string,
): Record<string, unknown> | null {
  const value = data[key];
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function mapConfigHistoryRow(
  id: string,
  data: DocumentData,
): ConfigHistoryRow {
  return {
    id,
    actor: readString(data, "actor"),
    action: readString(data, "action"),
    targetId: readString(data, "targetId"),
    changedFields: readStringArray(data, "changedFields"),
    after: readPlainObject(data, "after"),
    createdAt: toIso(data["createdAt"]),
  } satisfies ConfigHistoryRow;
}

// Newest-first history for a single `config/{configName}` document.
//
// The audit collection is scanned with a plain orderBy("createdAt") + limit and
// the config filter is applied IN MEMORY — exactly like
// getLiveUserActionHistory() — because combining .where("targetType"/"targetId")
// with .orderBy("createdAt") would need a composite index this project does not
// define. Consequence: only config changes that fall within the most recent
// `scanLimit` audit entries are shown; older ones drop off the list.
export async function listConfigHistory(
  configName: string,
  options?: { limit?: number },
): Promise<ConfigHistoryRow[]> {
  const db = getAdminDb();
  const scanLimit = options?.limit ?? 200;

  const snapshot = await db
    .collection(ADMIN_AUDIT_LOGS)
    .orderBy("createdAt", "desc")
    .limit(scanLimit)
    .get();

  return snapshot.docs
    .filter((doc) => {
      const data = doc.data();
      return (
        readString(data, "targetType") === "config" &&
        readString(data, "targetId") === configName
      );
    })
    .map((doc) => mapConfigHistoryRow(doc.id, doc.data()));
}

// Single audit entry by document id, mapped the same way. Returns null when the
// document does not exist, so a restore against a stale id fails cleanly.
export async function getConfigHistoryEntry(
  id: string,
): Promise<ConfigHistoryRow | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(ADMIN_AUDIT_LOGS).doc(id).get();
  const data = snapshot.data();

  if (!snapshot.exists || !data) {
    return null;
  }

  return mapConfigHistoryRow(snapshot.id, data);
}

// --- generic config docs (config/{name}) -------------------------------------
//
// Backs the admin console's editable backend configuration: progression
// (XP/level rules), leaderboard settings, and feature-access gating. These
// mirror the `config/progression`, `config/leaderboard`, and
// `config/featureAccess` documents read by functions/src/config/configLoader.ts
// — the admin console only ever merge-writes here, it never computes XP,
// level, rank, streak, or leaderboard score itself.

// Reads `config/{name}` and returns its stored fields as plain, serializable
// values (Timestamps coerced to ISO strings), or null when the document does
// not exist yet (an unseeded DB — the caller falls back to defaults/mocks).
export async function getConfigDoc(
  name: string,
): Promise<Record<string, unknown> | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(CONFIG).doc(name).get();

  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data();

  return data ? (toPlainValue(data) as Record<string, unknown>) : null;
}

// Merge-writes `config/{name}` with `data`, then appends an audit log entry
// carrying the explicit action name plus the changed-field list and
// before/after snapshots so config edits are fully traceable.
export async function setConfigDoc(
  name: string,
  data: Record<string, unknown>,
  adminEmail: string,
  auditAction: string,
  changedFields: string[],
  before: Record<string, unknown> | null,
): Promise<void> {
  const db = getAdminDb();

  await db
    .collection(CONFIG)
    .doc(name)
    .set({ ...data, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: auditAction,
    targetType: "config",
    targetId: name,
    detail: `Updated config/${name}`,
    changedFields,
    before,
    after: data,
  });
}

// --- website content (config/siteContent) ------------------------------------

// Single-document read; returns null when the document is absent so the
// caller can degrade to the mock website copy.
export async function getSiteContent(): Promise<SiteContentRow | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(CONFIG).doc(SITE_CONTENT_DOC_ID).get();

  if (!snapshot.exists) {
    return null;
  }

  return (snapshot.data() as SiteContentRow | undefined) ?? null;
}

// --- project documents (projectDocuments/{id}) -------------------------------
//
// Metadata for the admin console's "Project Documents" PDF library; the file
// bytes themselves live in Cloud Storage at each record's `storagePath` (see
// ./storage.ts). Filtering (category, date range, search text — see
// filterProjectDocuments() in @/lib/project-documents) is applied in memory
// by the caller, exactly like listConfigHistory() above, to avoid needing a
// composite index. listProjectDocuments() therefore only ever returns the
// newest 200 records; if the library grows past that, this ceiling (and the
// in-memory filtering it enables) needs revisiting — e.g. a real Firestore
// query per filter, or pagination.

function mapProjectDocumentRow(
  id: string,
  data: DocumentData,
): ProjectDocumentRecord {
  return {
    id,
    title: readString(data, "title") ?? "",
    category:
      (readString(data, "category") as ProjectDocumentCategory | null) ??
      "proposal",
    documentDate: readString(data, "documentDate") ?? "",
    fileName: readString(data, "fileName") ?? "",
    fileSize: readNumber(data, "fileSize") ?? 0,
    storagePath: readString(data, "storagePath") ?? "",
    createdAt: toIso(data["createdAt"]) ?? "",
    createdBy: readString(data, "createdBy") ?? "",
  };
}

// Newest-first (by documentDate) page of at most 200 project documents. See
// the section comment above for why filtering happens in memory instead of
// in this query.
export async function listProjectDocuments(): Promise<
  ProjectDocumentRecord[]
> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(PROJECT_DOCUMENTS)
    .orderBy("documentDate", "desc")
    .limit(200)
    .get();

  return snapshot.docs.map((doc) => mapProjectDocumentRow(doc.id, doc.data()));
}

// Single-document read; returns null when the id does not exist so a stale
// link (or a delete that already happened) fails cleanly.
export async function getProjectDocumentById(
  id: string,
): Promise<ProjectDocumentRecord | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(PROJECT_DOCUMENTS).doc(id).get();
  const data = snapshot.data();

  if (!snapshot.exists || !data) {
    return null;
  }

  return mapProjectDocumentRow(snapshot.id, data);
}

export type NewProjectDocumentData = {
  title: string;
  category: ProjectDocumentCategory;
  documentDate: string;
  fileName: string;
  fileSize: number;
};

// Mints a projectDocuments document id without writing anything. The caller
// (uploadProjectDocument() in @/lib/actions/documents) needs the id BEFORE
// the file upload, because the Cloud Storage path is
// `project-documents/{id}/{sanitizedFileName}` — unlike every other write in
// this file, the id can't be assigned by the write itself. Kept as a function
// (rather than exporting PROJECT_DOCUMENTS) so the collection name stays a
// module-private detail.
export function newProjectDocumentId(): string {
  return getAdminDb().collection(PROJECT_DOCUMENTS).doc().id;
}

// Creates a projectDocuments record at a caller-supplied id (see
// newProjectDocumentId() above) pointing at a PDF already uploaded to Cloud
// Storage at `storagePath` (see uploadProjectDocumentFile() in ./storage.ts —
// the caller uploads the bytes first, then calls this to record the
// metadata), then appends an audit log entry.
export async function createProjectDocument(
  id: string,
  storagePath: string,
  data: NewProjectDocumentData,
  adminEmail: string,
): Promise<string> {
  const db = getAdminDb();

  await db
    .collection(PROJECT_DOCUMENTS)
    .doc(id)
    .set({
      title: data.title,
      category: data.category,
      documentDate: data.documentDate,
      fileName: data.fileName,
      fileSize: data.fileSize,
      storagePath,
      createdBy: adminEmail,
      createdAt: FieldValue.serverTimestamp(),
    });

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "documents.upload",
    targetType: "projectDocument",
    targetId: id,
    detail: `Uploaded project document "${data.title}"`,
    after: { ...data, storagePath },
  });

  return id;
}

// Deletes a projectDocuments record and appends an audit log entry. Does not
// delete the underlying Cloud Storage object itself — callers that also want
// the file bytes removed call deleteProjectDocumentFile() from ./storage.ts
// separately, so a storage failure never leaves the Firestore record stuck.
export async function removeProjectDocument(
  id: string,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();

  await db.collection(PROJECT_DOCUMENTS).doc(id).delete();

  await appendAuditLog(db, {
    actor: adminEmail,
    action: "documents.delete",
    targetType: "projectDocument",
    targetId: id,
    detail: `Deleted project document ${id}`,
  });
}

// --- newsletter (newsletterSubscribers/{sha256(emailLower)},
//     newsletterCampaigns/{id}) ------------------------------------------------
//
// Subscriber documents are written by the `subscribeNewsletter` Cloud
// Function callable (Admin SDK there too); the console here only reads them
// and can delete one (a privacy/GDPR request) — it never writes emailLower,
// status, or any token-hash field. `ipHash` and token hashes are never read
// into NewsletterSubscriberRow at all (see ./types), so this file cannot leak
// them even by accident.
//
// Campaign documents follow the same command-document pattern as
// leaderboardAdminCommands/moderationCommands above: the console composes a
// draft and flips `status` forward (draft -> testQueued for a self-test,
// draft -> queued for a real send); a Firestore trigger outside this file
// does the actual sending and writes recipientCount/deliveredCount/
// failedCount/sentAt/error back onto the same document. The console can
// never set a subscriber to "confirmed" or a campaign to "sending"/"sent"
// directly — those are backend-owned outcomes.

function mapNewsletterSubscriberRow(
  id: string,
  data: DocumentData,
): NewsletterSubscriberRow {
  return {
    id,
    emailLower: readString(data, "emailLower"),
    status:
      (readString(data, "status") as NewsletterSubscriberStatus | null) ??
      "pending",
    source: readString(data, "source"),
    consentAt: toIso(data["consentAt"]),
    confirmedAt: toIso(data["confirmedAt"]),
    unsubscribedAt: toIso(data["unsubscribedAt"]),
    sendFailureCount: readNumber(data, "sendFailureCount") ?? 0,
    createdAt: toIso(data["createdAt"]),
    updatedAt: toIso(data["updatedAt"]),
  };
}

export async function listNewsletterSubscribers(): Promise<
  NewsletterSubscriberRow[]
> {
  const db = getAdminDb();
  const snapshot = await db.collection(NEWSLETTER_SUBSCRIBERS).get();
  const rows = snapshot.docs.map((doc) =>
    mapNewsletterSubscriberRow(doc.id, doc.data()),
  );

  // Newest first, in-memory (mirrors listReports()/listFeedback() above) so
  // this never requires a composite index on the emulator.
  rows.sort((left, right) =>
    (right.createdAt ?? "").localeCompare(left.createdAt ?? ""),
  );

  return rows;
}

// Privacy/GDPR takedown: deletes the subscriber document outright. There is
// deliberately no "set status" mutation alongside this one — the console must
// never be able to fabricate a "confirmed" double-opt-in, only remove a
// record entirely.
export async function deleteNewsletterSubscriber(
  id: string,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();
  const ref = db.collection(NEWSLETTER_SUBSCRIBERS).doc(id);
  const auditRef = db.collection(ADMIN_AUDIT_LOGS).doc();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const emailLower = snapshot.exists
      ? readString(snapshot.data() ?? {}, "emailLower")
      : null;

    transaction.delete(ref);

    transaction.set(
      auditRef,
      buildAuditLogRecord({
        actor: adminEmail,
        action: "newsletter.subscriber.delete",
        targetType: "newsletterSubscriber",
        targetId: id,
        detail: `Deleted newsletter subscriber ${emailLower ?? id}`,
      }),
    );
  });
}

function mapNewsletterCampaignRow(
  id: string,
  data: DocumentData,
): NewsletterCampaignRow {
  const testRecipients = data["testRecipients"];

  return {
    id,
    subject: readString(data, "subject"),
    bodyMarkdown: readString(data, "bodyMarkdown"),
    status:
      (readString(data, "status") as NewsletterCampaignStatus | null) ??
      "draft",
    createdBy: readString(data, "createdBy"),
    createdAt: toIso(data["createdAt"]),
    queuedAt: toIso(data["queuedAt"]),
    sentAt: toIso(data["sentAt"]),
    recipientCount: readNumber(data, "recipientCount") ?? 0,
    deliveredCount: readNumber(data, "deliveredCount") ?? 0,
    failedCount: readNumber(data, "failedCount") ?? 0,
    testRecipients: Array.isArray(testRecipients)
      ? testRecipients.filter(
          (value): value is string => typeof value === "string",
        )
      : [],
    lastTestSentAt: toIso(data["lastTestSentAt"]),
    error: readString(data, "error"),
  };
}

export async function listNewsletterCampaigns(): Promise<
  NewsletterCampaignRow[]
> {
  const db = getAdminDb();
  const snapshot = await db.collection(NEWSLETTER_CAMPAIGNS).get();
  const rows = snapshot.docs.map((doc) =>
    mapNewsletterCampaignRow(doc.id, doc.data()),
  );

  rows.sort((left, right) =>
    (right.createdAt ?? "").localeCompare(left.createdAt ?? ""),
  );

  return rows;
}

export async function getNewsletterCampaignById(
  id: string,
): Promise<NewsletterCampaignRow | null> {
  const db = getAdminDb();
  const snapshot = await db.collection(NEWSLETTER_CAMPAIGNS).doc(id).get();
  const data = snapshot.data();

  if (!snapshot.exists || !data) {
    return null;
  }

  return mapNewsletterCampaignRow(snapshot.id, data);
}

// Creates a new draft campaign. `subject`/`bodyMarkdown` are trusted here —
// the caller (src/lib/actions/newsletter.ts) already validated them.
export async function createNewsletterCampaign(
  subject: string,
  bodyMarkdown: string,
  adminEmail: string,
): Promise<string> {
  const db = getAdminDb();
  const ref = db.collection(NEWSLETTER_CAMPAIGNS).doc();
  const auditRef = db.collection(ADMIN_AUDIT_LOGS).doc();

  // No conditional read is needed here (unlike the update/queue paths below),
  // so a batch — rather than a transaction — is the natural way to make the
  // create and its audit entry commit atomically together.
  const batch = db.batch();

  batch.set(ref, {
    subject,
    bodyMarkdown,
    status: "draft",
    createdBy: adminEmail,
    createdAt: FieldValue.serverTimestamp(),
    recipientCount: 0,
    deliveredCount: 0,
    failedCount: 0,
    testRecipients: [],
  });

  batch.set(
    auditRef,
    buildAuditLogRecord({
      actor: adminEmail,
      action: "newsletter.campaign.create",
      targetType: "newsletterCampaign",
      targetId: ref.id,
      detail: `Created newsletter campaign draft "${subject}"`,
    }),
  );

  await batch.commit();

  return ref.id;
}

// Edits an existing draft's subject/body. Throws once the campaign has left
// "draft" — a queued/sending/sent campaign's content is what was (or is
// about to be) actually mailed, and must not silently change under it.
export async function updateNewsletterCampaignDraft(
  id: string,
  subject: string,
  bodyMarkdown: string,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();
  const ref = db.collection(NEWSLETTER_CAMPAIGNS).doc(id);
  const auditRef = db.collection(ADMIN_AUDIT_LOGS).doc();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);

    if (!snapshot.exists) {
      throw new Error("This campaign no longer exists.");
    }

    const status = readString(snapshot.data() ?? {}, "status") ?? "draft";

    if (status !== "draft") {
      throw new Error("Only a draft campaign can be edited.");
    }

    transaction.set(
      ref,
      { subject, bodyMarkdown, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

    transaction.set(
      auditRef,
      buildAuditLogRecord({
        actor: adminEmail,
        action: "newsletter.campaign.edit",
        targetType: "newsletterCampaign",
        targetId: id,
        detail: `Edited newsletter campaign draft "${subject}"`,
      }),
    );
  });
}

// Queues a self-test send: only the signed-in admin's own email is ever
// written as the recipient, so the console can never be used to mail an
// arbitrary address. Only a "draft" campaign may be test-queued (mirrors
// updateNewsletterCampaignDraft()'s guard); the backend trigger reverts
// status back to "draft" once the test send completes.
// The audit-log write below happens INSIDE the same transaction as the
// status transition, on a pre-allocated doc ref, rather than as a separate
// await after transaction commit. A transaction's writes all commit or fail
// together: if a plain post-transaction appendAuditLog() call threw (network
// blip, quota), the status flip would already be durably committed with no
// audit record for it — for a queue action that a Firestore trigger picks up
// and mails out, that would mean mail is already going out while the admin
// sees a thrown error and no trace of what happened. Doing both writes in one
// transaction makes that outcome impossible.
export async function queueNewsletterCampaignTest(
  id: string,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();
  const ref = db.collection(NEWSLETTER_CAMPAIGNS).doc(id);
  const auditRef = db.collection(ADMIN_AUDIT_LOGS).doc();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);

    if (!snapshot.exists) {
      throw new Error("This campaign no longer exists.");
    }

    const status = readString(snapshot.data() ?? {}, "status") ?? "draft";

    if (status !== "draft") {
      throw new Error(
        "Only a draft campaign can be sent as a test. Wait for the current run to finish.",
      );
    }

    transaction.set(
      ref,
      { status: "testQueued", testRecipients: [adminEmail] },
      { merge: true },
    );

    transaction.set(
      auditRef,
      buildAuditLogRecord({
        actor: adminEmail,
        action: "newsletter.campaign.testQueued",
        targetType: "newsletterCampaign",
        targetId: id,
        detail: `Queued a test send to ${adminEmail}`,
      }),
    );
  });
}

// Queues the real send to every confirmed subscriber. Same "draft only" guard
// as the test-send path above, so a campaign can never be queued twice. Also
// mirrors its in-transaction audit write — see that function's header
// comment for why — which matters even more directly here since this is the
// actually-irreversible send.
export async function queueNewsletterCampaignSend(
  id: string,
  adminEmail: string,
): Promise<void> {
  const db = getAdminDb();
  const ref = db.collection(NEWSLETTER_CAMPAIGNS).doc(id);
  const auditRef = db.collection(ADMIN_AUDIT_LOGS).doc();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);

    if (!snapshot.exists) {
      throw new Error("This campaign no longer exists.");
    }

    const status = readString(snapshot.data() ?? {}, "status") ?? "draft";

    if (status !== "draft") {
      throw new Error(
        "This campaign has already been queued or sent and cannot be sent again.",
      );
    }

    transaction.set(
      ref,
      { status: "queued", queuedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

    transaction.set(
      auditRef,
      buildAuditLogRecord({
        actor: adminEmail,
        action: "newsletter.campaign.queued",
        targetType: "newsletterCampaign",
        targetId: id,
        detail: `Queued newsletter campaign ${id} for sending`,
      }),
    );
  });
}

function mapNewsletterDeliveryRow(
  id: string,
  data: DocumentData,
): NewsletterDeliveryRow {
  return {
    id,
    status: readString(data, "status"),
    error: readString(data, "error"),
  };
}

// Per-recipient send history for one campaign, so the console can show which
// specific deliveries failed and why. Read-only: the console never writes to
// this subcollection, only the send trigger does.
export async function listNewsletterCampaignDeliveries(
  campaignId: string,
): Promise<NewsletterDeliveryRow[]> {
  const db = getAdminDb();
  const snapshot = await db
    .collection(NEWSLETTER_CAMPAIGNS)
    .doc(campaignId)
    .collection(NEWSLETTER_DELIVERIES)
    .get();

  return snapshot.docs.map((doc) =>
    mapNewsletterDeliveryRow(doc.id, doc.data()),
  );
}

