export const allowedProductionProject = "runiac-fypp";
export const cleanupAllRegionsSentinel = "all";
export const productionSeedScope = {
  periodKey: "2026-07",
  regionId: "jurong-east",
  usersPerRegion: 100,
} as const;

export type SeedAction =
  | "dry-run"
  | "seed"
  | "refresh"
  | "verify"
  | "cleanup"
  | "preview-cleanup"
  | "lifecycle"
  | "inventory";

export type InventoryCommand = {
  readonly kind: "inventory";
  readonly projectId: string;
  readonly firebaseCliAuth: true;
};

export type DatasetCommand = {
  readonly kind: "dataset";
  readonly projectId: string;
  readonly periodKey: string;
  readonly runId: string;
  readonly regionId: string | undefined;
  readonly usersPerRegion: number;
  readonly actions: ReadonlySet<SeedAction>;
  readonly firebaseCliAuth: boolean;
  readonly confirmProject: string | null;
  readonly confirmCleanup: string | null;
  readonly confirmPeriod: string | null;
  readonly confirmRegion: string | null;
  readonly confirmUsers: string | null;
  readonly confirmInventory: string | null;
  readonly replacementRunId: string | null;
};

export type SeedCommand = InventoryCommand | DatasetCommand;

export type InventoryIssue = {
  readonly code: string;
  readonly collection: string | null;
  readonly runId: string | null;
  readonly count: number;
};

export type InventoryCandidateCounts = Readonly<Record<
  | "users"
  | "userProfiles"
  | "leaderboardContributions"
  | "leaderboardUserRanks"
  | "leaderboardCurrentViews",
  number
>>;

export type InventoryRun = {
  readonly runId: string;
  readonly uidPrefix: string;
  readonly users: number;
  readonly profiles: number;
  readonly contributions: number;
  readonly ranks: number;
  readonly currentViews: number;
  readonly candidateCounts: InventoryCandidateCounts;
  readonly manifestStatus: string | null;
  readonly periodKey: string | null;
  readonly cleanupInventoryFingerprint: string;
  readonly status: "ready" | "blocked";
  readonly issues: readonly InventoryIssue[];
};

export type InventorySummary = {
  readonly action: "inventory";
  readonly projectId: string;
  readonly status: "ready" | "blocked";
  readonly runs: readonly InventoryRun[];
  readonly issues: readonly InventoryIssue[];
};

export type CleanupPreview = {
  readonly action: "preview-cleanup";
  readonly projectId: string;
  readonly runId: string;
  readonly periodKey: string;
  readonly uidPrefix: string;
  readonly status: "ready" | "blocked";
  readonly sourceDocumentCount: number;
  readonly rankDocumentCount: number;
  readonly currentViewDocumentCount: number;
  readonly candidateCounts: Readonly<Record<string, number>>;
  readonly cleanupInventoryFingerprint: string;
  readonly issues: readonly InventoryIssue[];
};
