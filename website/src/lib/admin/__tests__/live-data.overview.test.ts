import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// RED by design: getLiveSystemHealth / getLiveActiveUsersTrend do not exist
// yet in ../live-data.ts, and getLiveOverviewStats does not yet compute
// critical-errors/failed-jobs from real data. This file locks the target
// behaviour from overview-wiring-contract.md so WP3's implementation has an
// executable spec to satisfy; every test below is expected to fail until
// then (import resolves to `undefined`, so calling it throws "is not a
// function" — not a bug in this test file).

const {
  getConfigDocMock,
  listErrorGroupsMock,
  getLeaderboardCurrentPeriodMock,
  getLatestLeaderboardSnapshotMock,
  getLeaderboardAggregationLockMock,
  currentSingaporeMonthKeyMock,
  listActivityOwnerUidsInWindowMock,
  listReportsMock,
  listAccountDeletionCommandsMock,
  countUsersMock,
  countUsersBySubscriptionMock,
  countActivitiesSinceMock,
} = vi.hoisted(() => ({
  getConfigDocMock: vi.fn(),
  listErrorGroupsMock: vi.fn(),
  getLeaderboardCurrentPeriodMock: vi.fn(),
  getLatestLeaderboardSnapshotMock: vi.fn(),
  getLeaderboardAggregationLockMock: vi.fn(),
  currentSingaporeMonthKeyMock: vi.fn(),
  listActivityOwnerUidsInWindowMock: vi.fn(),
  listReportsMock: vi.fn(),
  listAccountDeletionCommandsMock: vi.fn(),
  countUsersMock: vi.fn(),
  countUsersBySubscriptionMock: vi.fn(),
  countActivitiesSinceMock: vi.fn(),
}));

vi.mock("@/lib/firebase/firestore", () => ({
  getConfigDoc: getConfigDocMock,
  listErrorGroups: listErrorGroupsMock,
  getLeaderboardCurrentPeriod: getLeaderboardCurrentPeriodMock,
  getLatestLeaderboardSnapshot: getLatestLeaderboardSnapshotMock,
  getLeaderboardAggregationLock: getLeaderboardAggregationLockMock,
  currentSingaporeMonthKey: currentSingaporeMonthKeyMock,
  listActivityOwnerUidsInWindow: listActivityOwnerUidsInWindowMock,
  listReports: listReportsMock,
  listAccountDeletionCommands: listAccountDeletionCommandsMock,
  countUsers: countUsersMock,
  countUsersBySubscription: countUsersBySubscriptionMock,
  countActivitiesSince: countActivitiesSinceMock,
}));

import type {
  ErrorGroupRow,
  LeaderboardAggregationLockRow,
  LeaderboardCurrentPeriodRow,
} from "@/lib/firebase/types";

import {
  getLiveActiveUsersTrend,
  getLiveOverviewStats,
  getLiveSystemHealth,
} from "../live-data";

const NOW_ISO = "2026-07-15T00:00:00.000Z";

function errorGroupRow(overrides: Partial<ErrorGroupRow> = {}): ErrorGroupRow {
  return {
    id: "err-1",
    title: "Something broke",
    errorType: "TypeError",
    screen: "home",
    appVersion: "1.0.0",
    os: "iOS 18",
    platform: "ios",
    source: "mobile",
    occurrences: 5,
    affectedUsers: 3,
    severity: "low",
    status: "new",
    firstSeenAt: "2026-07-01T00:00:00.000Z",
    lastSeenAt: "2026-07-01T00:00:00.000Z",
    stackSummary: "",
    sanitized: true,
    note: null,
    ...overrides,
  };
}

function lockRow(
  overrides: Partial<LeaderboardAggregationLockRow> = {},
): LeaderboardAggregationLockRow {
  return {
    periodKey: "2026-07",
    buildId: "build-1",
    status: "completed",
    startedAt: "2026-07-01T00:00:00.000Z",
    completedAt: "2026-07-01T00:05:00.000Z",
    failedAt: null,
    leaseExpiresAt: null,
    updatedAt: "2026-07-01T00:05:00.000Z",
    ...overrides,
  };
}

function currentPeriodRow(
  overrides: Partial<LeaderboardCurrentPeriodRow> = {},
): LeaderboardCurrentPeriodRow {
  return {
    periodType: "monthly",
    periodKey: "2026-07",
    periodLabel: "July 2026",
    timezone: "Asia/Singapore",
    refreshesAt: "2026-08-01T00:00:00.000Z",
    buildId: "build-1",
    generatedAt: "2026-07-01T00:00:00.000Z",
    aggregationStatus: "completed",
    updatedAt: "2026-07-01T00:00:00.000Z",
    ...overrides,
  };
}

describe("getLiveSystemHealth", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(NOW_ISO));
    vi.clearAllMocks();
    // Sane "all healthy" defaults so each test only overrides what its own
    // branch needs.
    getConfigDocMock.mockResolvedValue({ version: 1 });
    listErrorGroupsMock.mockResolvedValue([]);
    listAccountDeletionCommandsMock.mockResolvedValue([]);
    getLeaderboardCurrentPeriodMock.mockResolvedValue(currentPeriodRow());
    getLatestLeaderboardSnapshotMock.mockResolvedValue(null);
    getLeaderboardAggregationLockMock.mockResolvedValue(
      lockRow({ status: "completed" }),
    );
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns exactly 5 components with the contract ids/names/descriptions, sharing one lastCheckedAt", async () => {
    const components = await getLiveSystemHealth();

    expect(components).toHaveLength(5);
    expect(components.map((c) => c.id)).toEqual([
      "firestore",
      "leaderboard-aggregation",
      "account-deletion",
      "cloud-functions",
      "app-error-rate",
    ]);

    const byId = new Map(components.map((c) => [c.id, c]));
    expect(byId.get("firestore")).toMatchObject({
      name: "Firestore",
      description: "Primary application datastore",
    });
    expect(byId.get("leaderboard-aggregation")).toMatchObject({
      name: "Monthly leaderboard aggregation job",
      description: "Aggregates monthly and territory standings",
    });
    expect(byId.get("account-deletion")).toMatchObject({
      name: "Account deletion queue",
      description: "Erases the data of runners who asked to be deleted",
    });
    expect(byId.get("cloud-functions")).toMatchObject({
      name: "Cloud Functions",
      description: "Rule execution and background jobs",
    });
    expect(byId.get("app-error-rate")).toMatchObject({
      name: "App error rate",
      description: "Critical crash groups in the last 24 hours",
    });

    for (const component of components) {
      expect(component.lastCheckedAt).toBe(NOW_ISO);
    }
  });

  it("marks firestore down when the config probe throws", async () => {
    getConfigDocMock.mockRejectedValue(new Error("emulator down"));

    const components = await getLiveSystemHealth();
    const firestore = components.find((c) => c.id === "firestore");

    expect(firestore?.status).toBe("down");
  });

  it("marks firestore operational when the config probe succeeds", async () => {
    const components = await getLiveSystemHealth();
    const firestore = components.find((c) => c.id === "firestore");

    expect(firestore?.status).toBe("operational");
  });

  it("marks leaderboard-aggregation degraded when there is no aggregation job at all", async () => {
    getLeaderboardCurrentPeriodMock.mockResolvedValue(null);
    getLatestLeaderboardSnapshotMock.mockResolvedValue(null);

    const components = await getLiveSystemHealth();
    const aggregation = components.find(
      (c) => c.id === "leaderboard-aggregation",
    );

    expect(aggregation?.status).toBe("degraded");
  });

  it("marks leaderboard-aggregation down when the aggregation lock failed", async () => {
    getLeaderboardAggregationLockMock.mockResolvedValue(
      lockRow({ status: "failed" }),
    );

    const components = await getLiveSystemHealth();
    const aggregation = components.find(
      (c) => c.id === "leaderboard-aggregation",
    );

    expect(aggregation?.status).toBe("down");
  });

  it("marks leaderboard-aggregation operational when the aggregation lock completed", async () => {
    getLeaderboardAggregationLockMock.mockResolvedValue(
      lockRow({ status: "completed" }),
    );

    const components = await getLiveSystemHealth();
    const aggregation = components.find(
      (c) => c.id === "leaderboard-aggregation",
    );

    expect(aggregation?.status).toBe("operational");
  });

  // Account deletion is judged on STATE, not on a recent-error window. A
  // failed erase means a runner who asked to be deleted still has data in
  // Firestore and nothing will retry it, so the badge must stay lit no matter
  // how old the failure is — the case that let two real deletions sit failed
  // for 7 and 5 days while every time-boxed signal had long since cleared.
  const deletionCommand = (
    overrides: Partial<{
      uid: string;
      status: string;
      requestedAt: string | null;
      completedSteps: number;
      error: string | null;
    }> = {},
  ) => ({
    uid: "uid_1",
    status: "completed",
    requestedAt: NOW_ISO,
    completedSteps: 38,
    error: null,
    ...overrides,
  });

  const deletionStatus = async () =>
    (await getLiveSystemHealth()).find((c) => c.id === "account-deletion")?.status;

  it("marks account-deletion down for a failed command however old it is", async () => {
    listAccountDeletionCommandsMock.mockResolvedValue([
      deletionCommand({
        status: "failed",
        requestedAt: "2026-06-01T00:00:00.000Z",
        completedSteps: 3,
        error: "9 FAILED_PRECONDITION",
      }),
    ]);

    expect(await deletionStatus()).toBe("down");
  });

  it("marks account-deletion degraded for a command still unfinished past the stall window", async () => {
    listAccountDeletionCommandsMock.mockResolvedValue([
      deletionCommand({
        status: "erasing",
        requestedAt: "2026-07-14T20:00:00.000Z",
        completedSteps: 12,
      }),
    ]);

    expect(await deletionStatus()).toBe("degraded");
  });

  it("leaves account-deletion operational for a command that has only just been queued", async () => {
    listAccountDeletionCommandsMock.mockResolvedValue([
      deletionCommand({ status: "pending", completedSteps: 0 }),
    ]);

    expect(await deletionStatus()).toBe("operational");
  });

  it("marks account-deletion degraded when the command read itself fails", async () => {
    listAccountDeletionCommandsMock.mockRejectedValue(new Error("unreachable"));

    expect(await deletionStatus()).toBe("degraded");
  });

  it("marks account-deletion operational when every command completed", async () => {
    listAccountDeletionCommandsMock.mockResolvedValue([
      deletionCommand({ requestedAt: "2026-06-01T00:00:00.000Z" }),
      deletionCommand({ uid: "uid_2" }),
    ]);

    expect(await deletionStatus()).toBe("operational");
  });

  it("marks cloud-functions down when a critical functions-source error group fired within 24h", async () => {
    listErrorGroupsMock.mockResolvedValue([
      errorGroupRow({
        id: "fn-critical",
        source: "functions",
        severity: "critical",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
    ]);

    const components = await getLiveSystemHealth();
    const cloudFunctions = components.find((c) => c.id === "cloud-functions");

    expect(cloudFunctions?.status).toBe("down");
  });

  it("marks cloud-functions degraded when only a high-severity functions-source error group fired within 24h", async () => {
    listErrorGroupsMock.mockResolvedValue([
      errorGroupRow({
        id: "fn-high",
        source: "functions",
        severity: "high",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
    ]);

    const components = await getLiveSystemHealth();
    const cloudFunctions = components.find((c) => c.id === "cloud-functions");

    expect(cloudFunctions?.status).toBe("degraded");
  });

  it("marks cloud-functions operational when no matching functions-source error group is within 24h", async () => {
    listErrorGroupsMock.mockResolvedValue([
      // Critical, but a mobile-source group — must not affect cloud-functions.
      errorGroupRow({
        id: "mobile-critical",
        source: "mobile",
        severity: "critical",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
      // Critical functions-source group, but outside the 24h window.
      errorGroupRow({
        id: "fn-critical-stale",
        source: "functions",
        severity: "critical",
        lastSeenAt: "2026-07-01T00:00:00.000Z",
      }),
    ]);

    const components = await getLiveSystemHealth();
    const cloudFunctions = components.find((c) => c.id === "cloud-functions");

    expect(cloudFunctions?.status).toBe("operational");
  });

  it("marks app-error-rate degraded when any source has a critical error group within 24h", async () => {
    listErrorGroupsMock.mockResolvedValue([
      errorGroupRow({
        id: "mobile-critical",
        source: "mobile",
        severity: "critical",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
    ]);

    const components = await getLiveSystemHealth();
    const appErrorRate = components.find((c) => c.id === "app-error-rate");

    expect(appErrorRate?.status).toBe("degraded");
  });

  it("marks app-error-rate operational when no critical error group is within 24h", async () => {
    listErrorGroupsMock.mockResolvedValue([
      errorGroupRow({
        id: "mobile-critical-stale",
        source: "mobile",
        severity: "critical",
        lastSeenAt: "2026-07-01T00:00:00.000Z",
      }),
      errorGroupRow({
        id: "fn-high-recent",
        source: "functions",
        severity: "high",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
    ]);

    const components = await getLiveSystemHealth();
    const appErrorRate = components.find((c) => c.id === "app-error-rate");

    expect(appErrorRate?.status).toBe("operational");
  });

  it("marks the error-derived components degraded (not operational) when the errorGroups read fails", async () => {
    // A failed read must not be reported as healthy: cloud-functions and
    // app-error-rate report `degraded` (unknown) rather than "operational".
    listErrorGroupsMock.mockRejectedValue(new Error("errorGroups read failed"));

    const components = await getLiveSystemHealth();
    const byId = new Map(components.map((c) => [c.id, c]));

    expect(byId.get("cloud-functions")?.status).toBe("degraded");
    expect(byId.get("app-error-rate")?.status).toBe("degraded");
    // Firestore probe is independent and still succeeds here.
    expect(byId.get("firestore")?.status).toBe("operational");
  });
});

describe("getLiveActiveUsersTrend", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getLeaderboardCurrentPeriodMock.mockResolvedValue(
      currentPeriodRow({ periodKey: "2026-07" }),
    );
  });

  it("returns 6 points labelled Feb..Jul oldest to newest, forwards listActivityOwnerUidsInWindow's raw length (no extra dedupe), and treats an empty month as 0", async () => {
    listActivityOwnerUidsInWindowMock
      .mockResolvedValueOnce(["u1", "u2", "u3"]) // Feb
      .mockResolvedValueOnce([]) // Mar — empty month
      .mockResolvedValueOnce(["u4", "u5"]) // Apr
      // May: the Set-based dedupe is listActivityOwnerUidsInWindow's own
      // responsibility (see the firestore.ts helper contract), not
      // getLiveActiveUsersTrend's. This mock resolves an array that still
      // contains a duplicate to prove the caller trusts and forwards the
      // resolved array's raw .length rather than re-deduping it itself.
      .mockResolvedValueOnce(["u6", "u6", "u7"]) // May -> length 3
      .mockResolvedValueOnce(["u8"]) // Jun
      .mockResolvedValueOnce(["u9", "u10", "u11", "u12"]); // Jul

    const points = await getLiveActiveUsersTrend();

    expect(points).toEqual([
      { label: "Feb", activeUsers: 3 },
      { label: "Mar", activeUsers: 0 },
      { label: "Apr", activeUsers: 2 },
      { label: "May", activeUsers: 3 },
      { label: "Jun", activeUsers: 1 },
      { label: "Jul", activeUsers: 4 },
    ]);
    expect(listActivityOwnerUidsInWindowMock).toHaveBeenCalledTimes(6);
  });
});

describe("getLiveOverviewStats", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(NOW_ISO));
    vi.clearAllMocks();
    listReportsMock.mockResolvedValue([]);
    countUsersMock.mockResolvedValue(10);
    countUsersBySubscriptionMock.mockResolvedValue({
      basic: 8,
      premium: 2,
      other: 0,
      total: 10,
    });
    countActivitiesSinceMock.mockResolvedValue(25);
    listErrorGroupsMock.mockResolvedValue([]);
    getLeaderboardCurrentPeriodMock.mockResolvedValue(currentPeriodRow());
    getLatestLeaderboardSnapshotMock.mockResolvedValue(null);
    getLeaderboardAggregationLockMock.mockResolvedValue(
      lockRow({ status: "completed" }),
    );
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("still includes the 3 pre-existing stats, computed the same way as before", async () => {
    const stats = await getLiveOverviewStats();
    const byId = new Map(stats.map((s) => [s.id, s]));

    expect(byId.get("unresolved-reports")).toMatchObject({
      label: "Unresolved reports",
      value: 0,
      tone: "neutral",
      href: "/admin/exceptions",
    });
    // The duplicate "pending-cases" card is gone; it restated
    // unresolved-reports under a second label.
    expect(byId.get("pending-cases")).toBeUndefined();
    expect(byId.get("registered-users")).toMatchObject({
      label: "Registered users",
      value: 10,
      hint: "2 premium · 8 basic",
      href: "/admin/users",
    });
    expect(byId.get("recent-runs")).toMatchObject({
      label: "Runs recorded (30 days)",
      value: 25,
      hint: "Backend-reported",
    });
  });

  // Guards getLiveUnresolvedReportCount()'s definition-by-exclusion, which
  // mirrors TERMINAL_RESOLUTION_STATUSES in
  // functions/src/moderation/staleReportSweep.ts. Counting only "pending"
  // dropped a "reviewing" case out of this figure while the backend sweep
  // kept aging it, so the console read handled and the backend read
  // outstanding for the same report.
  it("counts every non-terminal report as unresolved, not just pending ones", async () => {
    listReportsMock.mockResolvedValue([
      { id: "r1", resolutionStatus: "pending" },
      { id: "r2", resolutionStatus: "reviewing" },
      // mapReportRow() reads a missing field as "pending".
      { id: "r3", resolutionStatus: "pending" },
      { id: "r4", resolutionStatus: "resolved" },
      { id: "r5", resolutionStatus: "dismissed" },
    ]);

    const byId = new Map(
      (await getLiveOverviewStats()).map((stat) => [stat.id, stat]),
    );

    expect(byId.get("unresolved-reports")).toMatchObject({
      value: 3,
      tone: "accent",
    });
  });

  it("computes critical-errors from severity=critical, status=new, lastSeenAt<24h groups and flips tone critical when > 0", async () => {
    listErrorGroupsMock.mockResolvedValue([
      errorGroupRow({
        id: "match",
        severity: "critical",
        status: "new",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
      // Wrong status — must not count.
      errorGroupRow({
        id: "wrong-status",
        severity: "critical",
        status: "resolved",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
      // Wrong severity — must not count.
      errorGroupRow({
        id: "wrong-severity",
        severity: "high",
        status: "new",
        lastSeenAt: "2026-07-14T20:00:00.000Z",
      }),
      // Outside the 24h window — must not count.
      errorGroupRow({
        id: "stale",
        severity: "critical",
        status: "new",
        lastSeenAt: "2026-07-01T00:00:00.000Z",
      }),
    ]);

    const stats = await getLiveOverviewStats();
    const criticalErrors = stats.find((s) => s.id === "critical-errors");

    expect(criticalErrors).toMatchObject({
      label: "Critical app errors today",
      value: 1,
      hint: "New crash groups",
      tone: "critical",
      href: "/admin/errors",
    });
  });

  it("reports critical-errors as 0 with neutral tone when nothing matches", async () => {
    const stats = await getLiveOverviewStats();
    const criticalErrors = stats.find((s) => s.id === "critical-errors");

    expect(criticalErrors).toMatchObject({ value: 0, tone: "neutral" });
  });

  it("zeroes only critical-errors (not every stat) when the errorGroups read fails", async () => {
    // A flaky errorGroups read must stay scoped to critical-errors; the
    // unrelated live stats still compute from their own reads.
    listErrorGroupsMock.mockRejectedValue(new Error("errorGroups read failed"));

    const stats = await getLiveOverviewStats();
    const byId = new Map(stats.map((s) => [s.id, s]));

    expect(byId.get("critical-errors")).toMatchObject({ value: 0, tone: "neutral" });
    expect(byId.get("registered-users")).toMatchObject({ value: 10 });
    expect(byId.get("recent-runs")).toMatchObject({ value: 25 });
  });

  it("reports failed-jobs as 1 with critical tone when the aggregation job status is down", async () => {
    getLeaderboardAggregationLockMock.mockResolvedValue(
      lockRow({ status: "failed" }),
    );

    const stats = await getLiveOverviewStats();
    const failedJobs = stats.find((s) => s.id === "failed-jobs");

    expect(failedJobs).toMatchObject({
      label: "Failed backend jobs",
      value: 1,
      hint: "Last 24 hours",
      tone: "critical",
      href: "/admin/audit",
    });
  });

  it("reports failed-jobs as 0 with neutral tone when the aggregation job is not down", async () => {
    getLeaderboardAggregationLockMock.mockResolvedValue(
      lockRow({ status: "completed" }),
    );

    const stats = await getLiveOverviewStats();
    const failedJobs = stats.find((s) => s.id === "failed-jobs");

    expect(failedJobs).toMatchObject({ value: 0, tone: "neutral" });
  });
});
