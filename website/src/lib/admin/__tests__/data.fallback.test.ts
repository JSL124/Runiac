import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// This suite locks the liveOrMock() fallback contract in ./data.ts for the
// three overview reads this workstream touches: getSystemHealth(),
// getActiveUsersTrend(), and getOverviewStats(). Per the wiring contract,
// getSystemHealth()/getActiveUsersTrend() are being switched from
// "mock in both modes" to liveOrMock(..., getLiveSystemHealth, SYSTEM_HEALTH)
// / liveOrMock(..., getLiveActiveUsersTrend, ACTIVE_USERS_TREND) — this test
// asserts that target behaviour, not the current mock-always state, so it is
// expected to fail against today's data.ts (RED) until WP3 wires it up.

const {
  hasFirebaseEnvMock,
  getLiveSystemHealthMock,
  getLiveActiveUsersTrendMock,
  getLiveOverviewStatsMock,
  getLiveProgressionHistoryMock,
  getLivePaywallHistoryMock,
} = vi.hoisted(() => ({
  hasFirebaseEnvMock: vi.fn(),
  getLiveSystemHealthMock: vi.fn(),
  getLiveActiveUsersTrendMock: vi.fn(),
  getLiveOverviewStatsMock: vi.fn(),
  getLiveProgressionHistoryMock: vi.fn(),
  getLivePaywallHistoryMock: vi.fn(),
}));

vi.mock("@/lib/firebase/config", () => ({
  hasFirebaseEnv: hasFirebaseEnvMock,
}));

vi.mock("@/lib/admin/live-data", async () => {
  const actual = await vi.importActual<typeof import("../live-data")>(
    "../live-data",
  );

  return {
    ...actual,
    getLiveSystemHealth: getLiveSystemHealthMock,
    getLiveActiveUsersTrend: getLiveActiveUsersTrendMock,
    getLiveOverviewStats: getLiveOverviewStatsMock,
    getLiveProgressionHistory: getLiveProgressionHistoryMock,
    getLivePaywallHistory: getLivePaywallHistoryMock,
  };
});

import {
  getActiveUsersTrend,
  getOverviewStats,
  getPaywallHistory,
  getProgressionHistory,
  getSystemHealth,
} from "../data";
import { ACTIVE_USERS_TREND, OVERVIEW_STATS, SYSTEM_HEALTH } from "../mock-data";

describe("liveOrMock fallback contract", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe("getSystemHealth", () => {
    it("returns the mock value when Firebase is not configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(false);

      const result = await getSystemHealth();

      expect(result).toBe(SYSTEM_HEALTH);
      expect(getLiveSystemHealthMock).not.toHaveBeenCalled();
    });

    it("returns the live value when Firebase is configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      const live = [
        {
          id: "firestore",
          name: "Firestore",
          description: "Primary application datastore",
          status: "operational" as const,
          lastCheckedAt: "2026-07-15T00:00:00.000Z",
        },
      ];
      getLiveSystemHealthMock.mockResolvedValue(live);

      const result = await getSystemHealth();

      expect(result).toBe(live);
    });

    it("degrades to the mock value (resolves, does not throw) when the live read rejects", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveSystemHealthMock.mockRejectedValue(new Error("firestore down"));

      await expect(getSystemHealth()).resolves.toBe(SYSTEM_HEALTH);
    });
  });

  describe("getActiveUsersTrend", () => {
    it("returns the mock value when Firebase is not configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(false);

      const result = await getActiveUsersTrend();

      expect(result).toBe(ACTIVE_USERS_TREND);
      expect(getLiveActiveUsersTrendMock).not.toHaveBeenCalled();
    });

    it("returns the live value when Firebase is configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      const live = [{ label: "Jul", activeUsers: 42 }];
      getLiveActiveUsersTrendMock.mockResolvedValue(live);

      const result = await getActiveUsersTrend();

      expect(result).toBe(live);
    });

    it("degrades to the mock value (resolves, does not throw) when the live read rejects", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveActiveUsersTrendMock.mockRejectedValue(new Error("firestore down"));

      await expect(getActiveUsersTrend()).resolves.toBe(ACTIVE_USERS_TREND);
    });
  });

  describe("getOverviewStats", () => {
    it("returns the mock value when Firebase is not configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(false);

      const result = await getOverviewStats();

      expect(result).toBe(OVERVIEW_STATS);
      expect(getLiveOverviewStatsMock).not.toHaveBeenCalled();
    });

    it("returns the live value when Firebase is configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      const live = [
        {
          id: "registered-users",
          label: "Registered users",
          value: 7,
          hint: "0 premium · 7 basic",
          tone: "neutral" as const,
          href: "/admin/users",
        },
      ];
      getLiveOverviewStatsMock.mockResolvedValue(live);

      const result = await getOverviewStats();

      expect(result).toBe(live);
    });

    it("degrades to the mock value (resolves, does not throw) when the live read rejects", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveOverviewStatsMock.mockRejectedValue(new Error("firestore down"));

      await expect(getOverviewStats()).resolves.toBe(OVERVIEW_STATS);
    });
  });

  describe("regression", () => {
    it("getSystemHealth resolves to a non-empty array even when the live read rejects", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveSystemHealthMock.mockRejectedValue(new Error("boom"));

      const result = await getSystemHealth();

      expect(Array.isArray(result)).toBe(true);
      expect(result.length).toBeGreaterThan(0);
    });

    it("getActiveUsersTrend resolves to a non-empty array even when the live read rejects", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveActiveUsersTrendMock.mockRejectedValue(new Error("boom"));

      const result = await getActiveUsersTrend();

      expect(Array.isArray(result)).toBe(true);
      expect(result.length).toBeGreaterThan(0);
    });

    it("getOverviewStats resolves to a non-empty array even when the live read rejects", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveOverviewStatsMock.mockRejectedValue(new Error("boom"));

      const result = await getOverviewStats();

      expect(Array.isArray(result)).toBe(true);
      expect(result.length).toBeGreaterThan(0);
    });

    it("getProgressionHistory mock fallback stays an empty array, never fabricated", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLiveProgressionHistoryMock.mockRejectedValue(new Error("boom"));

      const result = await getProgressionHistory();

      expect(result).toEqual([]);
    });

    it("getPaywallHistory mock fallback stays an empty array, never fabricated", async () => {
      hasFirebaseEnvMock.mockReturnValue(true);
      getLivePaywallHistoryMock.mockRejectedValue(new Error("boom"));

      const result = await getPaywallHistory();

      expect(result).toEqual([]);
    });

    it("getProgressionHistory mock fallback stays an empty array when Firebase is not configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(false);

      const result = await getProgressionHistory();

      expect(result).toEqual([]);
    });

    it("getPaywallHistory mock fallback stays an empty array when Firebase is not configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(false);

      const result = await getPaywallHistory();

      expect(result).toEqual([]);
    });
  });
});
