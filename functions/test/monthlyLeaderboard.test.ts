import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  currentSingaporeMonthKey,
  leaderboardContributionFields,
  planMonthlyLeaderboards,
  singaporeMonthLabel,
} from "../src/leaderboard/monthlyLeaderboard.js";

describe("monthly leaderboard aggregation", () => {
  it("partitions one monthly score by planning area and current league", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: [
        contribution({ ownerUid: "je-iron-2", scoreXp: 90 }),
        contribution({ ownerUid: "je-iron-1", scoreXp: 130 }),
        contribution({
          ownerUid: "tm-iron-1",
          scoreXp: 80,
          regionId: "tampines",
          regionLabel: "Tampines",
          planningAreaName: "TAMPINES",
          planningAreaCode: "TM",
          planningRegionCode: "ER",
        }),
        contribution({
          ownerUid: "je-bronze-1",
          scoreXp: 70,
          divisionKey: "tier_02",
          divisionLabel: "Bronze League",
          levelLabel: "Level 11",
        }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.map((snapshot) => snapshot.snapshotId),
      [
        "monthly_jurong-east_tier_01_2026-07",
        "monthly_jurong-east_tier_02_2026-07",
        "monthly_tampines_tier_01_2026-07",
      ],
    );
    const jurongIron = plan.snapshots[0];
    assert.equal(jurongIron?.entryCount, 2);
    assert.deepEqual(
      jurongIron?.topEntries.map((entry) => [
        entry.publicAlias,
        entry.rankLabel,
        entry.scoreLabel,
      ]),
      [
        ["Runner je-iron-1", "#1", "130 XP"],
        ["Runner je-iron-2", "#2", "90 XP"],
      ],
    );
    assert.equal(
      Object.hasOwn(jurongIron?.topEntries[0] ?? {}, "ownerUid"),
      false,
    );
  });

  it("bounds public top rows at ten and private nearby rows at five", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: Array.from({ length: 15 }, (_, index) =>
        contribution({
          ownerUid: `runner-${String(index + 1).padStart(2, "0")}`,
          scoreXp: 1_000 - index,
        }),
      ),
    });

    assert.equal(plan.snapshots[0]?.entryCount, 15);
    assert.equal(plan.snapshots[0]?.topEntries.length, 10);
    const rank = plan.ranks.find((item) => item.ownerUid === "runner-12");
    assert.equal(rank?.rankLabel, "#12");
    assert.equal(rank?.nearbyEntries.length, 5);
    assert.ok(
      rank?.nearbyEntries.some((entry) => entry.rankLabel === "#12"),
    );
    assert.equal(Object.hasOwn(rank?.currentEntry ?? {}, "ownerUid"), false);
  });

  it("re-checks current Premium status and rejects malformed legacy rows", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      currentPremiumUids: new Set(["premium"]),
      // Exclusion is no longer the default, so ask for it explicitly to keep
      // covering the premium re-check alongside the malformed-row rejection.
      excludePremium: true,
      contributions: [
        contribution({ ownerUid: "basic", scoreXp: 70 }),
        contribution({ ownerUid: "premium", scoreXp: 500 }),
        {
          ...contribution({ ownerUid: "legacy", scoreXp: 900 }),
          schemaVersion: 1,
        },
        {
          ...contribution({ ownerUid: "unsupported", scoreXp: 800 }),
          regionId: "sg",
        },
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => entry.publicAlias),
      ),
      ["Runner basic"],
    );
    assert.equal(
      plan.currentViews.find((view) => view.ownerUid === "premium")?.status,
      "ineligible_premium",
    );
  });

  // Premium parity: with no `excludePremium` supplied, a premium runner is
  // ranked beside Basic runners under the same scoring formula. Guards the
  // default itself, which is the only thing separating the two policies.
  it("ranks a premium runner by default, ordering by score alone", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      currentPremiumUids: new Set(["premium"]),
      contributions: [
        contribution({ ownerUid: "basic", scoreXp: 70 }),
        contribution({ ownerUid: "premium", scoreXp: 500 }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => entry.publicAlias),
      ),
      ["Runner premium", "Runner basic"],
    );
    assert.equal(
      plan.currentViews.find((view) => view.ownerUid === "premium")?.status,
      "ranked",
      "a premium runner must get a ranked currentView, not an excluded one",
    );
  });

  it("preserves zero-score Premium exclusions without projecting inactive rows", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      currentPremiumUids: new Set(["premium-zero"]),
      excludePremium: true,
      contributions: [
        contribution({ ownerUid: "ranked-basic", scoreXp: 70 }),
        {
          ...contribution({ ownerUid: "premium-zero", scoreXp: 0 }),
          eligible: false,
          eligibilityReason: "ineligible_premium",
        },
        contribution({ ownerUid: "basic-zero", scoreXp: 0 }),
        contribution({ ownerUid: "negative", scoreXp: -1 }),
      ],
    });

    assert.deepEqual(
      plan.currentViews.filter((view) => view.ownerUid === "premium-zero"),
      [
        {
          ownerUid: "premium-zero",
          snapshotId: null,
          rankId: null,
          periodKey: "2026-07",
          regionId: "jurong-east",
          divisionKey: "tier_01",
          status: "ineligible_premium",
        },
      ],
    );
    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => entry.publicAlias),
      ),
      ["Runner ranked-basic"],
    );
    assert.deepEqual(plan.ranks.map((rank) => rank.ownerUid), ["ranked-basic"]);
    assert.equal(plan.currentViews.some((view) => ["basic-zero", "negative"].includes(view.ownerUid)), false);
  });

  it("ranks a contribution normally at the default minRunsToQualify of 1 (zero regression)", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: [
        contribution({ ownerUid: "one-run", scoreXp: 70, qualifyingRunCount: 1 }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => entry.publicAlias),
      ),
      ["Runner one-run"],
    );
    assert.equal(
      plan.currentViews.find((view) => view.ownerUid === "one-run")?.status,
      "ranked",
    );
  });

  it("excludes a contribution under minRunsToQualify and emits an ineligible_min_runs currentView", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      minRunsToQualify: 3,
      contributions: [
        contribution({ ownerUid: "under-quota", scoreXp: 70, qualifyingRunCount: 2 }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => entry.publicAlias),
      ),
      [],
    );
    const view = plan.currentViews.find(
      (candidate) => candidate.ownerUid === "under-quota",
    );
    assert.ok(view !== undefined, "expected an ineligible_min_runs currentView to be emitted");
    assert.deepEqual(view, {
      ownerUid: "under-quota",
      snapshotId: null,
      rankId: null,
      periodKey: "2026-07",
      regionId: "jurong-east",
      divisionKey: "tier_01",
      status: "ineligible_min_runs",
    });
  });

  it("grandfathers a legacy contribution with no qualifyingRunCount field", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      minRunsToQualify: 5,
      contributions: [
        contribution({ ownerUid: "legacy-runner", scoreXp: 70 }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => entry.publicAlias),
      ),
      ["Runner legacy-runner"],
    );
    assert.equal(
      plan.currentViews.find((view) => view.ownerUid === "legacy-runner")
        ?.status,
      "ranked",
    );
  });

  it("assigns avatarUrl from avatarUrlByOwner, defaulting an absent owner or an omitted map to an empty string", () => {
    const withMap = planMonthlyLeaderboards({
      periodKey: "2026-07",
      avatarUrlByOwner: new Map([["je-iron-1", "https://firebasestorage.googleapis.com/v0/b/x/o/avatars%2Fabc.png?alt=media&token=t"]]),
      contributions: [
        contribution({ ownerUid: "je-iron-1", scoreXp: 130 }),
        contribution({ ownerUid: "je-iron-2", scoreXp: 90 }),
      ],
    });
    const jurongIron = withMap.snapshots[0];
    assert.deepEqual(
      jurongIron?.topEntries.map((entry) => [entry.publicAlias, entry.avatarUrl]),
      [
        ["Runner je-iron-1", "https://firebasestorage.googleapis.com/v0/b/x/o/avatars%2Fabc.png?alt=media&token=t"],
        ["Runner je-iron-2", ""],
      ],
    );
    const rank = withMap.ranks.find((item) => item.ownerUid === "je-iron-1");
    assert.equal(rank?.currentEntry.avatarUrl, "https://firebasestorage.googleapis.com/v0/b/x/o/avatars%2Fabc.png?alt=media&token=t");

    // Existing callers that omit avatarUrlByOwner entirely (every planner
    // test above this one) must keep compiling and resolving to "" — the
    // whole point of making the input optional.
    const withoutMap = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: [contribution({ ownerUid: "je-iron-1", scoreXp: 130 })],
    });
    assert.equal(withoutMap.snapshots[0]?.topEntries[0]?.avatarUrl, "");
  });

  it("publishes the live publicAliasByOwner nickname over the alias frozen into the contribution", () => {
    const renamed = planMonthlyLeaderboards({
      periodKey: "2026-07",
      publicAliasByOwner: new Map([
        ["je-iron-1", "Jinseo_main"],
        // A profile with no usable nickname must not blank the row.
        ["je-iron-2", "   "],
      ]),
      contributions: [
        contribution({ ownerUid: "je-iron-1", scoreXp: 130 }),
        contribution({ ownerUid: "je-iron-2", scoreXp: 90 }),
        // Absent from the map entirely: keeps the stored alias.
        contribution({ ownerUid: "je-iron-3", scoreXp: 50 }),
      ],
    });

    assert.deepEqual(
      renamed.snapshots[0]?.topEntries.map((entry) => entry.publicAlias),
      ["Jinseo_main", "Runner je-iron-2", "Runner je-iron-3"],
    );
    assert.equal(
      renamed.ranks.find((item) => item.ownerUid === "je-iron-1")?.currentEntry
        .publicAlias,
      "Jinseo_main",
    );
    // Nearby entries are projected from the same rows, so the rename reaches
    // every runner's view of the renamed one, not only their own.
    assert.deepEqual(
      renamed.ranks
        .find((item) => item.ownerUid === "je-iron-3")
        ?.nearbyEntries.map((entry) => entry.publicAlias),
      ["Jinseo_main", "Runner je-iron-2", "Runner je-iron-3"],
    );

    const withoutMap = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: [contribution({ ownerUid: "je-iron-1", scoreXp: 130 })],
    });
    assert.equal(
      withoutMap.snapshots[0]?.topEntries[0]?.publicAlias,
      "Runner je-iron-1",
    );
  });

  it("publishes the live levelDisplayByOwner level and progress over the contribution's frozen label", () => {
    const planned = planMonthlyLeaderboards({
      periodKey: "2026-07",
      levelDisplayByOwner: new Map([
        ["je-iron-1", { levelLabel: "Level 9", levelProgressPercent: 64 }],
        // A profile with no usable label must not blank the row's level, but
        // its percent is still honoured.
        ["je-iron-2", { levelLabel: "   ", levelProgressPercent: 12 }],
      ]),
      contributions: [
        contribution({ ownerUid: "je-iron-1", scoreXp: 130, levelLabel: "Level 8" }),
        contribution({ ownerUid: "je-iron-2", scoreXp: 90, levelLabel: "Level 3" }),
        // Absent from the map entirely: stored label, empty ring.
        contribution({ ownerUid: "je-iron-3", scoreXp: 50, levelLabel: "Level 2" }),
      ],
    });

    assert.deepEqual(
      planned.snapshots[0]?.topEntries.map((entry) => entry.levelLabel),
      ["Level 9", "Level 3", "Level 2"],
    );
    assert.deepEqual(
      planned.snapshots[0]?.topEntries.map((entry) => entry.levelProgressPercent),
      [64, 12, 0],
    );
    // The pair reaches a runner's own view and every neighbour's view of them,
    // exactly like the alias above.
    const ownRank = planned.ranks.find((item) => item.ownerUid === "je-iron-1");
    assert.equal(ownRank?.currentEntry.levelLabel, "Level 9");
    assert.equal(ownRank?.currentEntry.levelProgressPercent, 64);
    assert.deepEqual(
      planned.ranks
        .find((item) => item.ownerUid === "je-iron-3")
        ?.nearbyEntries.map((entry) => entry.levelProgressPercent),
      [64, 12, 0],
    );

    const withoutMap = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: [
        contribution({ ownerUid: "je-iron-1", scoreXp: 130, levelLabel: "Level 8" }),
      ],
    });
    assert.equal(withoutMap.snapshots[0]?.topEntries[0]?.levelLabel, "Level 8");
    assert.equal(
      withoutMap.snapshots[0]?.topEntries[0]?.levelProgressPercent,
      0,
    );
  });

  it("uses Asia Singapore month boundaries and labels", () => {
    assert.equal(
      currentSingaporeMonthKey(new Date("2026-06-30T15:59:59.000Z")),
      "2026-06",
    );
    assert.equal(
      currentSingaporeMonthKey(new Date("2026-06-30T16:00:00.000Z")),
      "2026-07",
    );
    assert.equal(singaporeMonthLabel("2026-07"), "July 2026");
  });

  it("derives contribution geography from profile and freezes it for the month", () => {
    const initial = leaderboardContributionFields({
      uid: "runner-1",
      progressionEventId: "progression-runner-1-session-1",
      completedAt: "2026-07-10T00:00:00.000Z",
      periodKey: "2026-07",
      scoreXp: 75,
      divisionKey: "tier_01",
      divisionLabel: "ignored client label",
      levelLabel: "Level 1",
      profileData: {
        nickname: "Jinseo",
        locationLabel: "Jurong East, Singapore",
      },
    });
    assert.equal(initial?.regionId, "jurong-east");
    assert.equal(initial?.planningAreaCode, "JE");
    assert.equal(initial?.divisionLabel, "Iron League");
    assert.equal(initial?.publicAlias, "Jinseo");

    const movedProfile = leaderboardContributionFields({
      uid: "runner-1",
      progressionEventId: "progression-runner-1-session-2",
      completedAt: "2026-07-11T00:00:00.000Z",
      periodKey: "2026-07",
      scoreXp: 50,
      divisionKey: "tier_02",
      divisionLabel: "ignored client label",
      levelLabel: "Level 11",
      profileData: {
        nickname: "Jinseo",
        locationLabel: "Jurong East, Singapore",
      },
      existingContributionData: contribution({
        ownerUid: "runner-1",
        regionId: "tampines",
        regionLabel: "Tampines",
        planningAreaName: "TAMPINES",
        planningAreaCode: "TM",
        planningRegionCode: "ER",
      }),
    });
    assert.equal(movedProfile?.regionId, "tampines");
    assert.equal(movedProfile?.divisionKey, "tier_02");
    assert.equal(movedProfile?.divisionLabel, "Bronze League");

    const unsupported = leaderboardContributionFields({
      uid: "runner-2",
      progressionEventId: "progression-runner-2-session-1",
      completedAt: "2026-07-10T00:00:00.000Z",
      periodKey: "2026-07",
      scoreXp: 75,
      divisionKey: "tier_01",
      divisionLabel: "Iron League",
      levelLabel: "Level 1",
      profileData: { nickname: "No Area", locationLabel: "Tuas, Singapore" },
    });
    assert.equal(unsupported, null);
  });
});

function contribution(input: {
  readonly ownerUid: string;
  readonly scoreXp?: number;
  readonly regionId?: string;
  readonly regionLabel?: string;
  readonly planningAreaName?: string;
  readonly planningAreaCode?: string;
  readonly planningRegionCode?: string;
  readonly divisionKey?: string;
  readonly divisionLabel?: string;
  readonly levelLabel?: string;
  readonly qualifyingRunCount?: number;
}): Record<string, unknown> {
  return {
    schemaVersion: 2,
    ownerUid: input.ownerUid,
    publicAlias: `Runner ${input.ownerUid}`,
    regionId: input.regionId ?? "jurong-east",
    regionLabel: input.regionLabel ?? "Jurong East",
    planningAreaName: input.planningAreaName ?? "JURONG EAST",
    planningAreaCode: input.planningAreaCode ?? "JE",
    planningRegionCode: input.planningRegionCode ?? "WR",
    divisionKey: input.divisionKey ?? "tier_01",
    divisionLabel: input.divisionLabel ?? "Iron League",
    levelLabel: input.levelLabel ?? "Level 1",
    periodType: "monthly",
    periodKey: "2026-07",
    timezone: "Asia/Singapore",
    scoreXp: input.scoreXp ?? 75,
    eligible: true,
    eligibilityReason: "eligible_basic_awarded_xp",
    lastProgressionAt: "2026-07-10T00:00:00.000Z",
    sourceProgressionEventIds: [`event-${input.ownerUid}`],
    ...(input.qualifyingRunCount === undefined
      ? {}
      : { qualifyingRunCount: input.qualifyingRunCount }),
  };
}
