// Firestore-emulator integration tests for the admin Overview page's public
// data functions (src/lib/admin/data.ts). Unlike live-data.overview.test.ts
// (which mocks @/lib/firebase/firestore and exercises pure derivation logic),
// this file writes real documents into the emulator and reads them back
// through the exact same path the admin console itself uses — proving the
// whole stack (data.ts -> live-data.ts -> firestore.ts -> emulator) actually
// wires together, not just that each layer is individually well-mocked.
//
// Skips itself entirely when no Firestore emulator is configured (see
// emulatorAvailable() in ./helpers/emulator) so `npm run test:integration`
// never accidentally talks to a live project.

import type { Firestore } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";

import {
  getActiveUsersTrend,
  getConfigSummaries,
  getOverviewStats,
  getSystemHealth,
} from "@/lib/admin/data";

import {
  emulatorAvailable,
  getTestDb,
  resetFirestore,
  seedActivity,
  seedAggregationLock,
  seedConfigDoc,
  seedCurrentPeriod,
  seedErrorGroup,
  seedReport,
  seedUser,
} from "./helpers/emulator";

describe.skipIf(!emulatorAvailable())(
  "admin overview — Firestore emulator integration",
  () => {
    let db: Firestore;

    beforeEach(async () => {
      db = getTestDb();
      await resetFirestore();
    });

    describe("getActiveUsersTrend (monthly active users)", () => {
      it("returns 6 points labelled Feb..Jul with distinct per-month owner counts", async () => {
        await seedCurrentPeriod(db, {
          periodKey: "2026-07",
          generatedAt: "2026-07-01T00:00:00.000Z",
        });

        // July window: 3 distinct owners; user-1 has a second activity in
        // the same window and must only count once.
        await seedActivity(db, {
          ownerUid: "user-1",
          startedAt: "2026-07-05T04:00:00.000Z",
        });
        await seedActivity(db, {
          ownerUid: "user-2",
          startedAt: "2026-07-10T04:00:00.000Z",
        });
        await seedActivity(db, {
          ownerUid: "user-3",
          startedAt: "2026-07-20T04:00:00.000Z",
        });
        await seedActivity(db, {
          ownerUid: "user-1",
          startedAt: "2026-07-25T04:00:00.000Z",
        });

        // June window: 1 distinct owner.
        await seedActivity(db, {
          ownerUid: "user-4",
          startedAt: "2026-06-15T04:00:00.000Z",
        });

        const points = await getActiveUsersTrend();

        expect(points).toEqual([
          { label: "Feb", activeUsers: 0 },
          { label: "Mar", activeUsers: 0 },
          { label: "Apr", activeUsers: 0 },
          { label: "May", activeUsers: 0 },
          { label: "Jun", activeUsers: 1 },
          { label: "Jul", activeUsers: 3 },
        ]);
      });
    });

    describe("getSystemHealth", () => {
      it("marks leaderboard-aggregation down when the current period's aggregation lock failed", async () => {
        await seedCurrentPeriod(db, {
          periodKey: "2026-07",
          generatedAt: "2026-07-01T00:00:00.000Z",
        });
        await seedAggregationLock(db, { periodKey: "2026-07", status: "failed" });

        const components = await getSystemHealth();
        const aggregation = components.find(
          (component) => component.id === "leaderboard-aggregation",
        );

        expect(aggregation?.status).toBe("down");
      });

      it("marks cloud-functions down when a functions-source critical error group fired within 24h", async () => {
        await seedErrorGroup(db, {
          source: "functions",
          severity: "critical",
          status: "new",
          lastSeenAt: new Date().toISOString(),
        });

        const components = await getSystemHealth();
        const cloudFunctions = components.find(
          (component) => component.id === "cloud-functions",
        );

        expect(cloudFunctions?.status).toBe("down");
      });

      it("reports every component operational with a clean completed lock and no recent critical errors", async () => {
        await seedCurrentPeriod(db, {
          periodKey: "2026-07",
          generatedAt: "2026-07-01T00:00:00.000Z",
        });
        await seedAggregationLock(db, {
          periodKey: "2026-07",
          status: "completed",
        });

        const components = await getSystemHealth();
        const statusById = new Map(
          components.map((component) => [component.id, component.status]),
        );

        expect(statusById.get("firestore")).toBe("operational");
        expect(statusById.get("leaderboard-aggregation")).toBe("operational");
        expect(statusById.get("cloud-functions")).toBe("operational");
        expect(statusById.get("app-error-rate")).toBe("operational");
      });
    });

    describe("getOverviewStats", () => {
      it("computes registered-users, unresolved-reports, and critical-errors from seeded data", async () => {
        await seedReport(db, { resolutionStatus: "pending" });
        await seedReport(db, { resolutionStatus: "pending" });
        // Resolved — must not count toward unresolved-reports.
        await seedReport(db, { resolutionStatus: "resolved" });

        await seedUser(db);
        await seedUser(db);
        await seedUser(db);

        await seedErrorGroup(db, {
          severity: "critical",
          status: "new",
          lastSeenAt: new Date().toISOString(),
        });

        const stats = await getOverviewStats();
        const statById = new Map(stats.map((stat) => [stat.id, stat]));

        expect(statById.get("registered-users")?.value).toBe(3);
        expect(statById.get("unresolved-reports")?.value).toBe(2);
        expect(statById.get("critical-errors")?.value).toBe(1);
      });

      it("reports failed-jobs = 1 when the current period's aggregation lock failed", async () => {
        await seedCurrentPeriod(db, {
          periodKey: "2026-07",
          generatedAt: "2026-07-01T00:00:00.000Z",
        });
        await seedAggregationLock(db, { periodKey: "2026-07", status: "failed" });

        const stats = await getOverviewStats();
        const failedJobs = stats.find((stat) => stat.id === "failed-jobs");

        expect(failedJobs?.value).toBe(1);
      });

      it("reports failed-jobs = 0 when the current period's aggregation lock completed", async () => {
        await seedCurrentPeriod(db, {
          periodKey: "2026-07",
          generatedAt: "2026-07-01T00:00:00.000Z",
        });
        await seedAggregationLock(db, {
          periodKey: "2026-07",
          status: "completed",
        });

        const stats = await getOverviewStats();
        const failedJobs = stats.find((stat) => stat.id === "failed-jobs");

        expect(failedJobs?.value).toBe(0);
      });
    });

    describe("getConfigSummaries", () => {
      it("marks a seeded config doc configured with its stored version, and an unseeded doc as not configured", async () => {
        await seedConfigDoc(db, "progression", {
          version: 2,
          updatedBy: "admin@x",
        });

        const summaries = await getConfigSummaries();
        const summaryById = new Map(
          summaries.map((summary) => [summary.id, summary]),
        );

        expect(summaryById.get("progression")).toMatchObject({
          configured: true,
          version: 2,
          updatedBy: "admin@x",
        });
        expect(summaryById.get("leaderboard")).toMatchObject({
          configured: false,
          version: null,
        });
      });
    });

    describe("empty emulator (live-not-mock proof)", () => {
      it("reads live zeros rather than the non-zero mock overview stats", async () => {
        const stats = await getOverviewStats();
        const statById = new Map(stats.map((stat) => [stat.id, stat]));

        // OVERVIEW_STATS mock data hardcodes unresolved-reports: 12 and
        // critical-errors: 3 (see ./mock-data.ts) — a nonzero read here would
        // mean this function is silently still serving the mock, not a live
        // (and correctly empty) Firestore emulator.
        expect(statById.get("registered-users")?.value).toBe(0);
        expect(statById.get("critical-errors")?.value).toBe(0);
      });
    });
  },
);
