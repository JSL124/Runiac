import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import { LeaderboardOversight } from "../LeaderboardOversight";
import { DEFAULT_LEADERBOARD_CONFIG } from "@/lib/admin/config-validation";
import {
  AGGREGATION_JOB,
  LEADERBOARD_COVERAGE,
  LEADERBOARD_CURRENT_PERIOD,
  LEADERBOARD_PARTICIPATION,
} from "@/lib/admin/mock-data";
import type { LeaderboardParticipationBreakdown } from "@/lib/admin/types";

vi.mock("@/lib/actions/admin", () => ({
  flagLeaderboardScore: vi.fn(),
  getLeaderboardRecalculationStatus: vi.fn(),
  loadLeaderboardSnapshot: vi.fn(),
  requestLeaderboardRecalculation: vi.fn(),
  saveLeaderboardConfig: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

// A deployment in the shape the panel is designed for: nobody is sitting in an
// exception bucket, and most accounts have never produced a run.
const healthy: LeaderboardParticipationBreakdown = {
  ranked: 2,
  unranked: 3,
  regionRequired: 0,
  ineligiblePremium: 0,
  ineligibleMinRuns: 0,
  total: 5,
  registeredUsers: 12,
};

function renderPanel(participation: LeaderboardParticipationBreakdown) {
  render(
    <LeaderboardOversight
      job={AGGREGATION_JOB}
      leaderboardConfig={DEFAULT_LEADERBOARD_CONFIG}
      suspicious={[]}
      currentPeriod={LEADERBOARD_CURRENT_PERIOD}
      participation={participation}
      coverage={LEADERBOARD_COVERAGE}
    />,
  );
}

// Reads the number rendered inside the StatCard carrying `label`, so the
// assertions cannot be satisfied by the same digits appearing elsewhere on a
// page that is full of counts.
function statCardValue(label: string): string {
  const card = screen.getByText(label).closest("div");
  expect(card).not.toBeNull();
  return card!.querySelector("p")?.textContent ?? "";
}

describe("LeaderboardOversight participation panel", () => {
  it("derives the never-ran cohort from the gap between registered users and the cycle", () => {
    renderPanel(healthy);

    expect(statCardValue("Never ran")).toBe("7");
    expect(statCardValue("Registered users")).toBe("12");
    expect(statCardValue("Ranked")).toBe("2");
    expect(statCardValue("Unranked")).toBe("3");
  });

  it("states the cycle size as a share of the user base rather than as a bare total", () => {
    renderPanel(healthy);

    expect(
      screen.getByText(
        /5 of 12 registered users are in this month's leaderboard cycle/i,
      ),
    ).toBeInTheDocument();
  });

  it("hides every exception bucket while all of them are zero", () => {
    renderPanel(healthy);

    expect(screen.queryByText("Region required")).not.toBeInTheDocument();
    expect(screen.queryByText("Ineligible: min runs")).not.toBeInTheDocument();
    expect(screen.queryByText("Ineligible: premium")).not.toBeInTheDocument();
  });

  it("surfaces only the exception bucket that is actually non-zero", () => {
    renderPanel({ ...healthy, regionRequired: 4 });

    expect(statCardValue("Region required")).toBe("4");
    // The hint names the real cause. A stored label can only stop resolving
    // because the catalog moved underneath it — the profile form never lets a
    // user save one that is absent from the catalog.
    expect(
      screen.getByText(/Stored planning area no longer resolves/i),
    ).toBeInTheDocument();
    expect(screen.queryByText("Ineligible: min runs")).not.toBeInTheDocument();
  });

  it("floors the never-ran cohort and says so when a view outlives its account", () => {
    renderPanel({ ...healthy, total: 20, registeredUsers: 12 });

    expect(statCardValue("Never ran")).toBe("0");
    expect(
      screen.getByText(/has outlived its account/i),
    ).toBeInTheDocument();
  });

  it("keeps the mock dataset renderable, so the Firebase-less console still shows the gap", () => {
    renderPanel(LEADERBOARD_PARTICIPATION);

    expect(statCardValue("Never ran")).toBe("440");
  });
});
