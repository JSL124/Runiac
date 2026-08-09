// The operator command that seeds, refreshes, verifies and cleans up mock
// leaderboard data.
//
// It can be pointed at a real project, so it is written to fail closed. A
// destructive action against production is refused unless the project matches
// [allowedProductionProject] and the scope is stated explicitly, `dry-run` is a
// first-class action, and cleanup consults the inventory first — see
// [isBlockedInventory], which stops a cleanup that would touch documents the
// seeder did not create.

import { pathToFileURL } from "node:url";
import { parseSeedCommand } from "./leaderboardSeedArguments.js";
import {
  allowedProductionProject,
  cleanupAllRegionsSentinel,
  productionSeedScope,
  type DatasetCommand,
  type InventorySummary,
} from "./leaderboardSeedCommandTypes.js";
import { createSeedDataset, seedDatasetSummary } from "./leaderboardSeedDataset.js";
import {
  configureFirebaseCliApplicationDefault,
  productionOrEmulatorFirestore,
} from "./leaderboardSeedFirestore.js";
import { inventoryLeaderboardSeedRuns } from "./leaderboardSeedInventory.js";
import {
  cleanupLeaderboardSeedRun,
  previewLeaderboardCleanup,
  seedLeaderboardDataset,
} from "./leaderboardSeedMutation.js";
import { refreshMonthlyLeaderboardSnapshots } from "./monthlyLeaderboardWriter.js";
import { verifyLeaderboardSeedRun } from "./leaderboardSeedVerification.js";

export async function runSeedCommand(
  rawArguments: readonly string[],
): Promise<Record<string, unknown>> {
  const command = parseSeedCommand(rawArguments);
  switch (command.kind) {
    case "inventory":
      return withFirebaseCliAuth(command.projectId, () =>
        inventoryLeaderboardSeedRuns(
          productionOrEmulatorFirestore(command.projectId),
          command.projectId,
        ),
      );
    case "dataset":
      return runDatasetCommand(command);
  }
}

async function runDatasetCommand(
  command: DatasetCommand,
): Promise<Record<string, unknown>> {
  assertProductionDatasetScope(command);
  const seedDataset = createSeedDataset({
    runId: command.runId,
    periodKey: command.periodKey,
    usersPerRegion: command.usersPerRegion,
    regionId: command.regionId,
  });
  const summary = seedDatasetSummary(command.projectId, seedDataset);
  if (command.actions.has("dry-run")) {
    return { action: "dry-run", ...summary };
  }
  if (command.actions.has("preview-cleanup")) {
    assertReadAuthorization(command);
    return withFirebaseCliAuth(command.projectId, () =>
      previewLeaderboardCleanup({
        firestore: productionOrEmulatorFirestore(command.projectId),
        projectId: command.projectId,
        seedDataset,
      }),
    );
  }
  assertMutationAuthorization(command);
  return withFirebaseCliAuth(command.projectId, async () => {
    const firestore = productionOrEmulatorFirestore(command.projectId);
    const results: Record<string, unknown> = { ...summary };
    if (command.actions.has("lifecycle")) {
      results["seed"] = await seedLeaderboardDataset({ firestore, projectId: command.projectId, seedDataset });
      results["refresh"] = await refreshMonthlyLeaderboardSnapshots(
        firestore,
        seedDataset.dataset.periodKey,
        { buildId: `lifecycle_${seedDataset.dataset.runId}_${seedDataset.dataset.periodKey}` },
      );
      assertCompletedRefresh(results["refresh"]);
      await recordRefreshBuild(firestore, seedDataset.dataset.runId, results["refresh"]);
      results["verify"] = await verifyLeaderboardSeedRun({ firestore, projectId: command.projectId, seedDataset });
      results["cleanup"] = await cleanupLeaderboardSeedRun({
        firestore, projectId: command.projectId, seedDataset,
        confirmInventory: command.confirmInventory,
        replacementRunId: command.replacementRunId,
      });
      results["remainingMockDocuments"] = 0;
      return results;
    }
    if (command.actions.has("cleanup")) {
      results["cleanup"] = await cleanupLeaderboardSeedRun({
        firestore, projectId: command.projectId, seedDataset,
        confirmInventory: command.confirmInventory,
        replacementRunId: command.replacementRunId,
      });
      return results;
    }
    if (command.actions.has("seed")) {
      results["seed"] = await seedLeaderboardDataset({ firestore, projectId: command.projectId, seedDataset });
    }
    if (command.actions.has("refresh")) {
      results["refresh"] = await refreshMonthlyLeaderboardSnapshots(
        firestore,
        seedDataset.dataset.periodKey,
        { buildId: `seed_${seedDataset.dataset.runId}_${seedDataset.dataset.periodKey}` },
      );
      assertCompletedRefresh(results["refresh"]);
      await recordRefreshBuild(firestore, seedDataset.dataset.runId, results["refresh"]);
    }
    if (command.actions.has("verify")) {
      results["verify"] = await verifyLeaderboardSeedRun({ firestore, projectId: command.projectId, seedDataset });
    }
    return results;
  });
}

function assertMutationAuthorization(command: DatasetCommand): void {
  const usingEmulator = process.env["FIRESTORE_EMULATOR_HOST"] !== undefined;
  if (command.actions.has("lifecycle") && !usingEmulator) {
    throw new Error("--lifecycle is emulator-only");
  }
  if (!usingEmulator) {
    if (!command.firebaseCliAuth) {
      throw new Error("production mutation requires --firebase-cli-auth");
    }
    if (command.projectId !== allowedProductionProject) {
      throw new Error(`production mutation is restricted to ${allowedProductionProject}`);
    }
    if (command.confirmProject !== command.projectId) {
      throw new Error(`repeat --confirm-project ${command.projectId} for production mutation`);
    }
    if (requiresProductionScopeConfirmation(command)) {
      if (command.confirmPeriod !== productionSeedScope.periodKey) {
        throw new Error(`repeat --confirm-period ${productionSeedScope.periodKey} for production mutation`);
      }
      if (command.confirmRegion !== productionSeedScope.regionId) {
        throw new Error(`repeat --confirm-region ${productionSeedScope.regionId} for production mutation`);
      }
      if (command.confirmUsers !== String(productionSeedScope.usersPerRegion)) {
        throw new Error(`repeat --confirm-users ${productionSeedScope.usersPerRegion} for production mutation`);
      }
    }
    if (command.actions.has("cleanup")) {
      assertProductionCleanupConfirmation(command);
    }
  }
  if (command.actions.has("cleanup") && command.confirmCleanup !== command.runId) {
    throw new Error(`repeat --confirm-cleanup ${command.runId} for cleanup`);
  }
}

function assertProductionCleanupConfirmation(command: DatasetCommand): void {
  if (command.confirmProject !== command.projectId) {
    throw new Error(`repeat --confirm-project ${command.projectId} for cleanup`);
  }
  if (command.confirmPeriod !== command.periodKey) {
    throw new Error(`repeat --confirm-period ${command.periodKey} for cleanup`);
  }
  const regionScope = command.regionId ?? cleanupAllRegionsSentinel;
  if (command.confirmRegion !== regionScope) {
    throw new Error(`repeat --confirm-region ${regionScope} for cleanup`);
  }
  if (command.confirmUsers !== String(command.usersPerRegion)) {
    throw new Error(`repeat --confirm-users ${command.usersPerRegion} for cleanup`);
  }
}

function assertProductionDatasetScope(command: DatasetCommand): void {
  if (process.env["FIRESTORE_EMULATOR_HOST"] !== undefined) {
    return;
  }
  if (command.actions.has("cleanup") || command.actions.has("preview-cleanup")) {
    return;
  }
  if (
    command.periodKey !== productionSeedScope.periodKey ||
    command.regionId !== productionSeedScope.regionId ||
    command.usersPerRegion !== productionSeedScope.usersPerRegion
  ) {
    throw new Error(
      `production dataset commands require --period ${productionSeedScope.periodKey} --region-id ${productionSeedScope.regionId} --users-per-region ${productionSeedScope.usersPerRegion}`,
    );
  }
}

async function recordRefreshBuild(
  firestore: ReturnType<typeof productionOrEmulatorFirestore>,
  runId: string,
  refresh: unknown,
): Promise<void> {
  if (typeof refresh !== "object" || refresh === null || typeof Reflect.get(refresh, "buildId") !== "string") {
    throw new Error("completed refresh did not return a build identity");
  }
  await firestore.collection("leaderboardSeedRuns").doc(runId).set({
    lastRefreshBuildId: Reflect.get(refresh, "buildId"),
    refreshedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  }, { merge: true });
}

function requiresProductionScopeConfirmation(command: DatasetCommand): boolean {
  return command.actions.has("seed") ||
    command.actions.has("refresh") ||
    command.actions.has("verify");
}

function assertCompletedRefresh(value: unknown): void {
  if (
    typeof value !== "object" ||
    value === null ||
    Reflect.get(value, "status") !== "completed"
  ) {
    throw new Error("refresh did not complete; verification was not attempted");
  }
}

function assertReadAuthorization(command: DatasetCommand): void {
  if (process.env["FIRESTORE_EMULATOR_HOST"] === undefined) {
    if (command.projectId !== allowedProductionProject || !command.firebaseCliAuth) {
      throw new Error(`--preview-cleanup requires ${allowedProductionProject} and --firebase-cli-auth`);
    }
  }
}

async function withFirebaseCliAuth<T>(
  projectId: string,
  action: () => Promise<T>,
): Promise<T> {
  const cleanupCredential = await configureFirebaseCliApplicationDefault();
  try {
    return await action();
  } finally {
    await cleanupCredential();
  }
}

export function isBlockedInventory(result: Record<string, unknown>): boolean {
  return result["action"] === "inventory" && result["status"] === "blocked";
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await runSeedCommand(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (isBlockedInventory(result)) {
    process.exitCode = 1;
  }
}
