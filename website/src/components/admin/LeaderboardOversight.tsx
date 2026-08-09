"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  flagLeaderboardScore,
  getLeaderboardRecalculationStatus,
  loadLeaderboardSnapshot,
  requestLeaderboardRecalculation,
  saveLeaderboardConfig,
} from "@/lib/actions/admin";
import { validateLeaderboardConfig } from "@/lib/admin/config-validation";
import {
  btnBrand,
  btnSecondary,
  inputBase,
} from "@/components/admin/button-styles";
import {
  AdminSection,
  CaptionLabel,
  Chip,
  EmptyState,
  InfoBanner,
  StatCard,
  StatusPill,
} from "@/components/admin/primitives";
import { formatDateTime, formatNumber } from "@/lib/admin/format";
import type {
  AggregationJob,
  LeaderboardConfig,
  LeaderboardCoverageSummary,
  LeaderboardCurrentPeriod,
  LeaderboardParticipationBreakdown,
  SuspiciousScore,
} from "@/lib/admin/types";
import {
  SUSPICIOUS_SCORE_LIST_CAP,
  TOTAL_LEADERBOARD_LEAGUE_TIERS,
  TOTAL_SUPPORTED_LEADERBOARD_REGIONS,
} from "@/lib/admin/types";
import type { LeaderboardSnapshotRow } from "@/lib/firebase/types";

type SaveState = "idle" | "confirm" | "saving" | "saved-live" | "saved-staged" | "error";

// Bounded polling for the leaderboardAdminCommands document the recalculation
// request writes: the leaderboardAdminCommandCreated Cloud Function trigger
// consumes it asynchronously, so the console has to poll rather than block on
// a single round trip. Polling stops after maxPollAttempts rather than
// running forever.
const maxPollAttempts = 15;
const pollIntervalMs = 2000;

type RecalcState =
  | { kind: "idle" }
  | { kind: "requesting" }
  | { kind: "polling"; attempt: number }
  | {
      kind: "completed";
      buildId: string | null;
      snapshotCount: number | null;
      rankCount: number | null;
      currentViewCount: number | null;
    }
  | { kind: "skipped_locked" }
  | { kind: "rejected"; reason: string | null }
  | { kind: "failed"; reason: string | null }
  | { kind: "timed-out" }
  | { kind: "not-live" }
  | { kind: "error"; message: string };

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Mirrors functions/src/leaderboard/singaporePlanningAreas.ts (regionId +
// regionName only — the standings viewer's region select does not need the
// extra planning-area/region codes). Hardcoded here because website/ and
// functions/ are separate packages with no shared import boundary; kept in
// lockstep manually with the generated backend file. Used only to populate
// the select — the actual standings always come from a live Firestore read.
const SINGAPORE_PLANNING_AREAS: ReadonlyArray<{
  regionId: string;
  regionName: string;
}> = [
  { regionId: "jurong-east", regionName: "Jurong East" },
  { regionId: "orchard", regionName: "Orchard" },
  { regionId: "ang-mo-kio", regionName: "Ang Mo Kio" },
  { regionId: "bedok", regionName: "Bedok" },
  { regionId: "bishan", regionName: "Bishan" },
  { regionId: "boon-lay", regionName: "Boon Lay" },
  { regionId: "bukit-batok", regionName: "Bukit Batok" },
  { regionId: "bukit-merah", regionName: "Bukit Merah" },
  { regionId: "bukit-panjang", regionName: "Bukit Panjang" },
  { regionId: "bukit-timah", regionName: "Bukit Timah" },
  { regionId: "changi", regionName: "Changi" },
  { regionId: "choa-chu-kang", regionName: "Choa Chu Kang" },
  { regionId: "clementi", regionName: "Clementi" },
  { regionId: "downtown-core", regionName: "Downtown Core" },
  { regionId: "geylang", regionName: "Geylang" },
  { regionId: "hougang", regionName: "Hougang" },
  { regionId: "jurong-west", regionName: "Jurong West" },
  { regionId: "kallang", regionName: "Kallang" },
  { regionId: "marine-parade", regionName: "Marine Parade" },
  { regionId: "museum", regionName: "Museum" },
  { regionId: "newton", regionName: "Newton" },
  { regionId: "novena", regionName: "Novena" },
  { regionId: "outram", regionName: "Outram" },
  { regionId: "pasir-ris", regionName: "Pasir Ris" },
  { regionId: "punggol", regionName: "Punggol" },
  { regionId: "queenstown", regionName: "Queenstown" },
  { regionId: "river-valley", regionName: "River Valley" },
  { regionId: "rochor", regionName: "Rochor" },
  { regionId: "sembawang", regionName: "Sembawang" },
  { regionId: "sengkang", regionName: "Sengkang" },
  { regionId: "serangoon", regionName: "Serangoon" },
  { regionId: "singapore-river", regionName: "Singapore River" },
  { regionId: "tampines", regionName: "Tampines" },
  { regionId: "tanglin", regionName: "Tanglin" },
  { regionId: "toa-payoh", regionName: "Toa Payoh" },
  { regionId: "woodlands", regionName: "Woodlands" },
  { regionId: "yishun", regionName: "Yishun" },
];

// Mirrors functions/src/progression/leaderboardLeagues.ts. Same hardcoding
// rationale as SINGAPORE_PLANNING_AREAS above.
const LEADERBOARD_LEAGUE_TIERS: ReadonlyArray<{ key: string; label: string }> = [
  { key: "tier_01", label: "Iron League" },
  { key: "tier_02", label: "Bronze League" },
  { key: "tier_03", label: "Silver League" },
  { key: "tier_04", label: "Gold League" },
  { key: "tier_05", label: "Platinum League" },
  { key: "tier_06", label: "Emerald League" },
  { key: "tier_07", label: "Diamond League" },
  { key: "tier_08", label: "Master League" },
  { key: "tier_09", label: "Grandmaster League" },
  { key: "tier_10", label: "Challenger League" },
];

// Mirrors currentSingaporeMonthKey() in
// functions/src/leaderboard/monthlyLeaderboardPeriod.ts (and its admin-console
// copy in src/lib/firebase/firestore.ts) — used only as a client-side fallback
// default for the standings viewer's target period when
// leaderboardPeriods/monthly_current does not exist yet (e.g. an unseeded
// database). The lookup itself always reads live Firestore data; this never
// stands in for a real period.
function fallbackCurrentSingaporeMonthKey(): string {
  const now = new Date();
  return new Date(now.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 7);
}

// Human-readable "time remaining until X" for the current period's month
// rollover (refreshesAt). Returns null when the target is missing/invalid so
// the caller can omit the line entirely.
function describeTimeRemaining(iso: string | null): string | null {
  if (!iso) {
    return null;
  }

  const target = new Date(iso).getTime();
  if (Number.isNaN(target)) {
    return null;
  }

  const diffMs = target - Date.now();
  if (diffMs <= 0) {
    return "Rollover due now";
  }

  const hourMs = 60 * 60 * 1000;
  const dayMs = 24 * hourMs;
  const days = Math.floor(diffMs / dayMs);
  const hours = Math.floor((diffMs % dayMs) / hourMs);

  if (days > 0) {
    return `${days}d ${hours}h remaining`;
  }

  const minutes = Math.floor((diffMs % hourMs) / (60 * 1000));
  return `${hours}h ${minutes}m remaining`;
}

type StandingsState =
  | { kind: "idle" }
  | { kind: "loading" }
  | { kind: "loaded"; snapshot: LeaderboardSnapshotRow | null }
  | { kind: "error"; message: string };

export function LeaderboardOversight({
  job,
  leaderboardConfig,
  suspicious,
  currentPeriod,
  participation,
  coverage,
}: {
  job: AggregationJob;
  leaderboardConfig: LeaderboardConfig;
  suspicious: SuspiciousScore[];
  currentPeriod: LeaderboardCurrentPeriod | null;
  participation: LeaderboardParticipationBreakdown;
  coverage: LeaderboardCoverageSummary;
}) {
  const router = useRouter();

  const [config, setConfig] = useState<LeaderboardConfig>(leaderboardConfig);
  const [errors, setErrors] = useState<string[]>([]);
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  type FlagRowState =
    | { kind: "idle" }
    | { kind: "pending" }
    | { kind: "sent" }
    | { kind: "error"; message: string };

  const [flagRowStates, setFlagRowStates] = useState<Record<string, FlagRowState>>({});
  const [note, setNote] = useState<string | null>(null);

  const [recalcState, setRecalcState] = useState<RecalcState>({ kind: "idle" });

  const effectivePeriodKey = currentPeriod?.periodKey ?? fallbackCurrentSingaporeMonthKey();

  const [selectedRegion, setSelectedRegion] = useState(SINGAPORE_PLANNING_AREAS[0].regionId);
  const [selectedDivision, setSelectedDivision] = useState(LEADERBOARD_LEAGUE_TIERS[0].key);
  const [standingsState, setStandingsState] = useState<StandingsState>({ kind: "idle" });

  function updateField<K extends keyof LeaderboardConfig>(
    key: K,
    value: LeaderboardConfig[K],
  ) {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function handleSaveClick() {
    const result = validateLeaderboardConfig(config);

    if (!result.valid) {
      setErrors([...result.errors]);
      setSaveState("idle");
      return;
    }

    setErrors([]);
    // Changes the qualifying pool and season length for every runner —
    // confirm before writing.
    setSaveState("confirm");
  }

  function handleCancelConfirm() {
    setSaveState("idle");
  }

  async function handleConfirmSave() {
    setSaveState("saving");
    setErrorMessage(null);

    const result = await saveLeaderboardConfig(config);

    if (!result.ok) {
      setSaveState("error");
      setErrorMessage(result.error);
      return;
    }

    if (result.live) {
      setSaveState("saved-live");
      router.refresh();
    } else {
      setSaveState("saved-staged");
    }
  }

  async function recalc() {
    setRecalcState({ kind: "requesting" });

    const requestResult = await requestLeaderboardRecalculation();

    if (!requestResult.ok) {
      setRecalcState({ kind: "error", message: requestResult.error });
      return;
    }

    if (!requestResult.live) {
      setRecalcState({ kind: "not-live" });
      return;
    }

    const { commandId } = requestResult;
    setRecalcState({ kind: "polling", attempt: 0 });

    for (let attempt = 1; attempt <= maxPollAttempts; attempt += 1) {
      await sleep(pollIntervalMs);
      const statusResult = await getLeaderboardRecalculationStatus(commandId);

      if (!statusResult.ok) {
        setRecalcState({ kind: "error", message: statusResult.error });
        return;
      }

      const command = statusResult.command;

      if (command === null || command.status === "pending") {
        setRecalcState({ kind: "polling", attempt });
        continue;
      }

      switch (command.status) {
        case "completed":
          setRecalcState({
            kind: "completed",
            buildId: command.buildId,
            snapshotCount: command.snapshotCount,
            rankCount: command.rankCount,
            currentViewCount: command.currentViewCount,
          });
          router.refresh();
          return;
        case "skipped_locked":
          setRecalcState({ kind: "skipped_locked" });
          return;
        case "rejected":
          setRecalcState({ kind: "rejected", reason: command.error });
          return;
        case "failed":
          setRecalcState({ kind: "failed", reason: command.error });
          return;
        default:
          setRecalcState({ kind: "polling", attempt });
      }
    }

    setRecalcState({ kind: "timed-out" });
  }

  // Writes a real `reports` document (flagLeaderboardScore ->
  // createLeaderboardReport) instead of only dropping the row from local
  // state. On failure the row is left exactly as it was — the flag must not
  // silently disappear just because the write failed. `suspicious` is
  // re-derived from live data on every server render, so a successful flag
  // does not remove the row here; it stays visible (marked "In Exception
  // Queue") until the underlying anomaly itself is resolved.
  async function sendToQueue(flag: SuspiciousScore) {
    setFlagRowStates((prev) => ({ ...prev, [flag.id]: { kind: "pending" } }));
    setNote(null);

    const result = await flagLeaderboardScore({
      ownerUid: flag.ownerUid,
      contributionId: flag.contributionId,
      reason: flag.reason,
      region: flag.region,
      flaggedScore: flag.flaggedScore,
    });

    if (!result.ok) {
      setFlagRowStates((prev) => ({
        ...prev,
        [flag.id]: { kind: "error", message: result.error },
      }));
      return;
    }

    setFlagRowStates((prev) => ({ ...prev, [flag.id]: { kind: "sent" } }));

    if (!result.live) {
      setNote(
        "Firebase is not connected, so this has not been written to a live backend.",
      );
      return;
    }

    setNote(
      `Flagged score for ${flag.user} sent to the Exception Queue at ${formatDateTime(new Date().toISOString())}. It is now a pending case under Suspicious XP activity.`,
    );
    router.refresh();
  }

  // Loads a single region x division snapshot for the standings viewer on
  // demand. `monthly_{regionId}_{divisionKey}_{periodKey}` is the same id
  // format the backend writes (functions/src/leaderboard/monthlyLeaderboardPlanner.ts),
  // so this is a single-document read, not a scan.
  async function loadStandings() {
    setStandingsState({ kind: "loading" });

    const result = await loadLeaderboardSnapshot(
      selectedRegion,
      selectedDivision,
      effectivePeriodKey,
    );

    if (!result.ok) {
      setStandingsState({ kind: "error", message: result.error });
      return;
    }

    setStandingsState({ kind: "loaded", snapshot: result.snapshot });
  }

  const refreshesAtRemaining = describeTimeRemaining(currentPeriod?.refreshesAt ?? null);

  // Everyone who has never produced a leaderboardContribution, and so has no
  // currentView document to be counted by status at all. Clamped because the
  // two numbers come from different collections: a currentView that outlived
  // its users/{uid} document would otherwise render a negative cohort. That
  // case is called out in the caption rather than silently floored, since it
  // means a deletion did not finish.
  const neverRan = Math.max(
    0,
    participation.registeredUsers - participation.total,
  );
  const countsDisagree = participation.total > participation.registeredUsers;

  // Buckets that are unreachable in a healthy deployment, so they earn their
  // space only when non-zero. Rendering them permanently reads as a dashboard
  // of zeros and buries the two numbers above that actually move:
  //
  // - min runs: mergeRolloverViews (monthlyLeaderboardOwnerFacts.ts) does not
  //   apply minRunsToQualify at all, so at the default of 1 an owner with no
  //   contribution this period becomes `unranked`, and an owner with one has
  //   already cleared the gate. Nothing lands here.
  // - region required: the profile form can only store a label the shared
  //   planning-area catalog contains, so this fires on catalog drift or an
  //   orphaned view, never on a user's choice.
  // - premium: gated behind excludePremium, which Runiac policy keeps off.
  const exceptions = (
    [
      {
        label: "Region required",
        value: participation.regionRequired,
        tone: "critical",
        hint: "Stored planning area no longer resolves — check the region catalog",
      },
      {
        label: "Ineligible: min runs",
        value: participation.ineligibleMinRuns,
        tone: "accent",
        hint: `Fewer than ${leaderboardConfig.minRunsToQualify} qualifying runs`,
      },
      {
        label: "Ineligible: premium",
        value: participation.ineligiblePremium,
        tone: "critical",
        hint: "Excluded by excludePremium — Runiac policy keeps this off",
      },
    ] as const
  ).filter((exception) => exception.value > 0);

  return (
    <div className="space-y-6">
      <AdminSection title="Aggregation job status" actions={<StatusPill status={job.status} />}>
        <dl className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <CaptionLabel>Last run</CaptionLabel>
            <dd className="mt-1 font-semibold text-foreground">
              {formatDateTime(job.lastRunAt)}
            </dd>
          </div>
          <div>
            <CaptionLabel>Duration</CaptionLabel>
            <dd className="mt-1 font-semibold text-foreground">
              {job.durationSeconds}s
            </dd>
          </div>
          <div>
            <CaptionLabel>Next scheduled run (every 60 min)</CaptionLabel>
            <dd className="mt-1 font-semibold text-foreground">
              {formatDateTime(job.nextRunAt)}
            </dd>
          </div>
          <div>
            <CaptionLabel>Period / build</CaptionLabel>
            <dd className="mt-1 font-semibold text-foreground">
              {job.periodKey ?? "—"} · {job.buildId ?? "—"}
            </dd>
          </div>
        </dl>
        {job.staleLease ? (
          <div className="mt-4">
            <InfoBanner tone="warn">
              This job claimed an aggregation lease
              {job.startedAt
                ? ` at ${formatDateTime(job.startedAt)}`
                : ""}{" "}
              and never released it — the run is stuck. It will need a
              backend-side lease recovery before the next scheduled run can
              proceed cleanly.
            </InfoBanner>
          </div>
        ) : null}
        <button
          type="button"
          className={`${btnBrand} mt-5`}
          onClick={recalc}
          disabled={recalcState.kind === "requesting" || recalcState.kind === "polling"}
        >
          {recalcState.kind === "requesting" || recalcState.kind === "polling"
            ? "Recalculating…"
            : "Request recalculation"}
        </button>
        {recalcState.kind === "requesting" ? (
          <p className="mt-3 text-sm text-muted">Requesting recalculation…</p>
        ) : recalcState.kind === "polling" ? (
          <p className="mt-3 text-sm text-muted">
            Recalculation running — checking status ({recalcState.attempt}/{maxPollAttempts})…
          </p>
        ) : recalcState.kind === "completed" ? (
          <p className="mt-3 rounded-lg border border-[#bfe3d0] bg-[#eafaf1] px-3 py-2 text-sm text-[#0f6b4e]">
            Recalculation completed: {formatNumber(recalcState.snapshotCount ?? 0)}{" "}
            snapshots, {formatNumber(recalcState.rankCount ?? 0)} ranks,{" "}
            {formatNumber(recalcState.currentViewCount ?? 0)} current views written
            (build {recalcState.buildId ?? "—"}).
          </p>
        ) : recalcState.kind === "skipped_locked" ? (
          <p className="mt-3 rounded-lg border border-accent/25 bg-accent-soft px-3 py-2 text-sm text-foreground">
            Skipped — another aggregation run already holds the lease for this
            period. Try again shortly.
          </p>
        ) : recalcState.kind === "rejected" ? (
          <p className="mt-3 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-3 py-2 text-sm text-[#b42318]">
            Recalculation rejected: {recalcState.reason ?? "invalid request."}
          </p>
        ) : recalcState.kind === "failed" ? (
          <p className="mt-3 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-3 py-2 text-sm text-[#b42318]">
            Recalculation failed: {recalcState.reason ?? "unknown error."}
          </p>
        ) : recalcState.kind === "timed-out" ? (
          <p className="mt-3 rounded-lg border border-accent/25 bg-accent-soft px-3 py-2 text-sm text-foreground">
            Still running — refresh later to see the outcome.
          </p>
        ) : recalcState.kind === "not-live" ? (
          <p className="mt-3 text-sm font-semibold text-accent">
            Firebase is not connected, so this has not been written to a live
            backend.
          </p>
        ) : recalcState.kind === "error" ? (
          <p className="mt-3 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-3 py-2 text-sm text-[#b42318]">
            {recalcState.message}
          </p>
        ) : null}
        {note ? (
          <p className="mt-3 rounded-lg border border-accent/25 bg-accent-soft px-3 py-2 text-sm text-foreground">
            {note}
          </p>
        ) : null}
      </AdminSection>

      <AdminSection title="Current leaderboard period">
        {currentPeriod === null ? (
          <EmptyState
            title="No current period document"
            description="The mobile app has nothing to read yet — the aggregation job has never completed a run for this database."
          />
        ) : (
          <>
            <dl className="grid grid-cols-2 gap-4 text-sm sm:grid-cols-3">
              <div>
                <CaptionLabel>Period</CaptionLabel>
                <dd className="mt-1 font-semibold text-foreground">
                  {currentPeriod.periodLabel ?? "—"}{" "}
                  <span className="text-muted">({currentPeriod.periodKey ?? "—"})</span>
                </dd>
              </div>
              <div>
                <CaptionLabel>Timezone</CaptionLabel>
                <dd className="mt-1 font-semibold text-foreground">
                  {currentPeriod.timezone ?? "—"}
                </dd>
              </div>
              <div>
                <CaptionLabel>Build</CaptionLabel>
                <dd className="mt-1 font-semibold text-foreground">
                  {currentPeriod.buildId ?? "—"}
                </dd>
              </div>
              <div>
                <CaptionLabel>Aggregation status</CaptionLabel>
                <dd className="mt-1 font-semibold text-foreground">
                  {currentPeriod.aggregationStatus ?? "—"}
                </dd>
              </div>
              <div>
                <CaptionLabel>Last generated</CaptionLabel>
                <dd className="mt-1 font-semibold text-foreground">
                  {currentPeriod.generatedAt ? formatDateTime(currentPeriod.generatedAt) : "—"}
                </dd>
              </div>
              <div>
                <CaptionLabel>Month rollover (refreshesAt)</CaptionLabel>
                <dd className="mt-1 font-semibold text-foreground">
                  {currentPeriod.refreshesAt ? formatDateTime(currentPeriod.refreshesAt) : "—"}
                </dd>
                {refreshesAtRemaining ? (
                  <p className="mt-0.5 text-[0.7rem] text-muted">{refreshesAtRemaining}</p>
                ) : null}
              </div>
            </dl>
          </>
        )}
      </AdminSection>

      <AdminSection title="Participation &amp; eligibility">
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard
            label="Ranked"
            value={formatNumber(participation.ranked)}
            hint="Placed on a region &times; division board"
          />
          <StatCard
            label="Unranked"
            value={formatNumber(participation.unranked)}
            hint="Ran before, no qualifying score this month"
          />
          <StatCard
            label="Never ran"
            value={formatNumber(neverRan)}
            hint="Signed up, no validated run yet"
          />
          <StatCard
            label="Registered users"
            value={formatNumber(participation.registeredUsers)}
          />
        </div>
        {exceptions.length > 0 ? (
          <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
            {exceptions.map((exception) => (
              <StatCard
                key={exception.label}
                label={exception.label}
                value={formatNumber(exception.value)}
                tone={exception.tone}
                hint={exception.hint}
              />
            ))}
          </div>
        ) : null}
        <p className="mt-4 text-xs text-muted">
          {formatNumber(participation.total)} of{" "}
          {formatNumber(participation.registeredUsers)} registered users are in
          this month&apos;s leaderboard cycle.
          {countsDisagree
            ? " More users are in the cycle than exist in the users collection — a leaderboardCurrentViews document has outlived its account."
            : null}
        </p>
      </AdminSection>

      <AdminSection title="Coverage">
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard label="Snapshots" value={formatNumber(coverage.snapshotCount)} />
          <StatCard
            label="Regions covered"
            value={`${coverage.regionsCovered} / ${TOTAL_SUPPORTED_LEADERBOARD_REGIONS}`}
          />
          <StatCard
            label="Divisions covered"
            value={`${coverage.divisionsCovered} / ${TOTAL_LEADERBOARD_LEAGUE_TIERS}`}
          />
          <StatCard label="Ranked entries" value={formatNumber(coverage.totalEntries)} />
        </div>
        <div className="mt-4">
          <CaptionLabel>Period keys with data</CaptionLabel>
          {coverage.periodKeys.length === 0 ? (
            <p className="mt-1 text-sm text-muted">None yet.</p>
          ) : (
            <div className="mt-2 flex flex-wrap gap-2">
              {coverage.periodKeys.map((key) => (
                <Chip key={key} tone="muted">
                  {key}
                </Chip>
              ))}
            </div>
          )}
        </div>
      </AdminSection>

      <AdminSection title="Standings viewer">
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs font-bold uppercase tracking-[0.08em] text-muted">
              Region
            </span>
            <select
              value={selectedRegion}
              onChange={(event) => {
                setSelectedRegion(event.target.value);
                setStandingsState({ kind: "idle" });
              }}
              className={`${inputBase} w-56`}
            >
              {SINGAPORE_PLANNING_AREAS.map((area) => (
                <option key={area.regionId} value={area.regionId}>
                  {area.regionName}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs font-bold uppercase tracking-[0.08em] text-muted">
              Division
            </span>
            <select
              value={selectedDivision}
              onChange={(event) => {
                setSelectedDivision(event.target.value);
                setStandingsState({ kind: "idle" });
              }}
              className={`${inputBase} w-52`}
            >
              {LEADERBOARD_LEAGUE_TIERS.map((tier) => (
                <option key={tier.key} value={tier.key}>
                  {tier.label}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            className={btnBrand}
            onClick={loadStandings}
            disabled={standingsState.kind === "loading"}
          >
            {standingsState.kind === "loading" ? "Loading…" : "Load standings"}
          </button>
        </div>
        <p className="mt-2 text-xs text-muted">Period: {effectivePeriodKey}</p>

        <div className="mt-4">
          {standingsState.kind === "idle" ? (
            <EmptyState
              title="No standing loaded yet"
              description="Pick a region and division, then load standings."
            />
          ) : standingsState.kind === "loading" ? (
            <p className="text-sm text-muted">Loading…</p>
          ) : standingsState.kind === "error" ? (
            <p className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-3 py-2 text-sm text-[#b42318]">
              {standingsState.message}
            </p>
          ) : standingsState.snapshot === null ? (
            <EmptyState
              title="No snapshot for this combination"
              description="This region x division has no runners for the selected period yet — that's expected for most combinations, not an error."
            />
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-3 text-sm">
                <Chip tone="brand">
                  {formatNumber(standingsState.snapshot.entryCount ?? 0)} entries
                </Chip>
                <span className="text-xs text-muted">
                  Generated{" "}
                  {standingsState.snapshot.generatedAt
                    ? formatDateTime(standingsState.snapshot.generatedAt)
                    : "—"}
                </span>
              </div>
              {standingsState.snapshot.entries.length === 0 ? (
                <p className="mt-3 text-sm text-muted">
                  Snapshot exists but has no entries.
                </p>
              ) : (
                <div className="mt-3 overflow-x-auto">
                  <table className="w-full min-w-[520px] text-sm">
                    <thead>
                      <tr className="border-b border-border text-left text-[0.7rem] font-bold uppercase tracking-[0.08em] text-muted">
                        <th className="py-2 pr-4">Rank</th>
                        <th className="py-2 pr-4">Runner</th>
                        <th className="py-2 pr-4">Score</th>
                        <th className="py-2 pr-4">Level</th>
                        <th className="py-2 pr-4">Division</th>
                      </tr>
                    </thead>
                    <tbody>
                      {standingsState.snapshot.entries.map((entry, index) => (
                        <tr
                          key={`${entry.publicAlias ?? "entry"}-${index}`}
                          className="border-b border-border/60"
                        >
                          <td className="py-2 pr-4 font-semibold text-brand">
                            {entry.rankLabel ?? "—"}
                          </td>
                          <td className="py-2 pr-4 font-semibold text-foreground">
                            {entry.publicAlias ?? "—"}
                          </td>
                          <td className="py-2 pr-4 tabular-nums">
                            {entry.scoreLabel ?? "—"}
                          </td>
                          <td className="py-2 pr-4">{entry.levelLabel ?? "—"}</td>
                          <td className="py-2 pr-4">{entry.divisionLabel ?? "—"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </>
          )}
        </div>
      </AdminSection>

      <AdminSection title="Monthly leaderboard settings">
        <div className="space-y-4">
          <div>
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">
                Minimum runs to qualify
              </span>
              <input
                type="number"
                min={0}
                value={config.minRunsToQualify}
                onChange={(event) =>
                  updateField("minRunsToQualify", Number(event.target.value))
                }
                className={`${inputBase} w-24 text-right tabular-nums`}
              />
            </label>
            <p className="mt-1 text-xs text-muted">
              The qualifying-run count is recomputed from each user&apos;s
              validated run history on every run, so it always reflects their
              true total for the period.
            </p>
          </div>
          {errors.length > 0 ? (
            <div className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm text-[#b42318]">
              <p className="font-bold">Fix these before saving:</p>
              <ul className="mt-1 list-disc space-y-0.5 pl-5">
                {errors.map((error) => (
                  <li key={error}>{error}</li>
                ))}
              </ul>
            </div>
          ) : null}

          <div className="flex flex-wrap items-center gap-3 border-t border-border pt-4">
            {saveState === "confirm" ? (
              <>
                <span className="text-sm font-semibold text-foreground">
                  This changes qualification rules for every runner. Confirm
                  save?
                </span>
                <button type="button" className={btnBrand} onClick={handleConfirmSave}>
                  Confirm save
                </button>
                <button type="button" className={btnSecondary} onClick={handleCancelConfirm}>
                  Cancel
                </button>
              </>
            ) : (
              <button
                type="button"
                className={btnBrand}
                onClick={handleSaveClick}
                disabled={saveState === "saving"}
              >
                {saveState === "saving" ? "Saving…" : "Save leaderboard config"}
              </button>
            )}
            {saveState === "saved-live" ? (
              <span className="text-sm font-semibold text-[#0f6b4e]">
                Saved. Live in config/leaderboard.
              </span>
            ) : saveState === "saved-staged" ? (
              <span className="text-sm font-semibold text-accent">
                Saved locally. Firebase is not connected, so this has not
                been written to a live backend.
              </span>
            ) : saveState === "error" && errorMessage ? (
              <span className="text-sm font-semibold text-[#b42318]">{errorMessage}</span>
            ) : null}
          </div>

          <p className="border-t border-border pt-4 text-xs text-muted">
            The only real admin write to leaderboard standings is the
            per-user XP correction under{" "}
            <Link href="/admin/users" className="font-semibold text-accent underline">
              Users
            </Link>{" "}
            (adjusts <code className="font-mono">leaderboardContributions.scoreXp</code>).
            There is no score-edit control on this page.
          </p>
        </div>
      </AdminSection>

      <AdminSection title="Suspicious-activity alerts">
        {suspicious.length >= SUSPICIOUS_SCORE_LIST_CAP ? (
          <p className="mb-3 rounded-lg border border-accent/25 bg-accent-soft px-3 py-2 text-xs text-foreground">
            Showing the {SUSPICIOUS_SCORE_LIST_CAP} highest-severity flags.
            More may exist beyond this cap.
          </p>
        ) : null}
        {note ? (
          <p className="mb-3 rounded-lg border border-accent/25 bg-accent-soft px-3 py-2 text-sm text-foreground">
            {note}
          </p>
        ) : null}
        {suspicious.length === 0 ? (
          <EmptyState title="No flagged scores" description="Nothing needs review right now." />
        ) : (
          <ul className="space-y-3">
            {suspicious.map((flag) => {
              const rowState = flagRowStates[flag.id] ?? { kind: "idle" as const };

              return (
                <li
                  key={flag.id}
                  className="flex flex-col gap-3 rounded-lg border border-border px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-bold text-brand">{flag.user}</p>
                      <Chip tone="muted">{flag.region}</Chip>
                      <Chip tone="accent">
                        Score {formatNumber(flag.flaggedScore)}
                      </Chip>
                    </div>
                    <p className="mt-1 text-xs text-muted">{flag.reason}</p>
                    <p className="mt-0.5 text-[0.7rem] text-muted">
                      Detected {formatDateTime(flag.detectedAt)}
                    </p>
                  </div>
                  <div className="flex shrink-0 flex-col items-start gap-1 sm:items-end">
                    <button
                      type="button"
                      className={btnSecondary}
                      onClick={() => sendToQueue(flag)}
                      disabled={rowState.kind === "pending" || rowState.kind === "sent"}
                    >
                      {rowState.kind === "pending"
                        ? "Sending…"
                        : rowState.kind === "sent"
                          ? "In Exception Queue"
                          : "Send to Exception Queue"}
                    </button>
                    {rowState.kind === "error" ? (
                      <span className="max-w-xs text-right text-xs font-semibold text-[#b42318]">
                        {rowState.message}
                      </span>
                    ) : null}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </AdminSection>
    </div>
  );
}
