import {
  allowedProductionProject,
  cleanupAllRegionsSentinel,
  type DatasetCommand,
  type SeedAction,
  type SeedCommand,
} from "./leaderboardSeedCommandTypes.js";

// Parses the leaderboard seeder's command line.
//
// Kept apart from the command itself so the argument rules are unit-testable
// without a Firestore connection — which matters because this parser is the
// first of the seeder's safety checks. An unrecognised action, a missing scope
// or a production target that was not spelled out is rejected here, before
// anything is opened.

const actions = new Set<SeedAction>([
  "dry-run",
  "seed",
  "refresh",
  "verify",
  "cleanup",
  "preview-cleanup",
  "lifecycle",
  "inventory",
]);

const valueOptions = new Set([
  "project",
  "period",
  "run-id",
  "region-id",
  "users-per-region",
  "confirm-project",
  "confirm-cleanup",
  "confirm-period",
  "confirm-region",
  "confirm-users",
  "confirm-inventory",
  "replacement-run-id",
]);

export function parseSeedCommand(rawArguments: readonly string[]): SeedCommand {
  const parsed = parseRawArguments(rawArguments);
  if (parsed.actions.has("inventory")) {
    return parseInventoryCommand(parsed);
  }
  return parseDatasetCommand(parsed);
}

type RawArguments = {
  readonly values: ReadonlyMap<string, string>;
  readonly actions: ReadonlySet<SeedAction>;
  readonly firebaseCliAuth: boolean;
};

function parseRawArguments(rawArguments: readonly string[]): RawArguments {
  const values = new Map<string, string>();
  const selectedActions = new Set<SeedAction>();
  let firebaseCliAuth = false;
  for (let index = 0; index < rawArguments.length; index += 1) {
    const token = rawArguments[index];
    if (token === undefined || !token.startsWith("--")) {
      throw new Error(`unexpected argument: ${token ?? ""}`);
    }
    const key = token.slice(2);
    if (key === "firebase-cli-auth") {
      if (firebaseCliAuth) {
        throw new Error("duplicate option: --firebase-cli-auth");
      }
      firebaseCliAuth = true;
      continue;
    }
    if (isSeedAction(key)) {
      if (selectedActions.has(key)) {
        throw new Error(`duplicate option: --${key}`);
      }
      selectedActions.add(key);
      continue;
    }
    if (!valueOptions.has(key)) {
      throw new Error(`unknown option: --${key}`);
    }
    if (values.has(key)) {
      throw new Error(`duplicate option: --${key}`);
    }
    const value = rawArguments[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`missing value for --${key}`);
    }
    values.set(key, value);
    index += 1;
  }
  return { values, actions: selectedActions, firebaseCliAuth };
}

function parseInventoryCommand(raw: RawArguments): SeedCommand {
  if (raw.actions.size !== 1 || !raw.firebaseCliAuth) {
    throw new Error("--inventory must be used alone with --firebase-cli-auth");
  }
  const projectId = requiredValue(raw.values, "project");
  if (isProduction() && projectId !== allowedProductionProject) {
    throw new Error(`inventory is restricted to ${allowedProductionProject}`);
  }
  return { kind: "inventory", projectId, firebaseCliAuth: true };
}

function parseDatasetCommand(raw: RawArguments): DatasetCommand {
  if (raw.actions.size === 0) {
    throw new Error("choose an action");
  }
  const actionCount = raw.actions.size;
  if (raw.actions.has("cleanup") && actionCount !== 1) {
    throw new Error("--cleanup must be used alone");
  }
  if (raw.actions.has("preview-cleanup") && actionCount !== 1) {
    throw new Error("--preview-cleanup must be used alone");
  }
  if (raw.actions.has("lifecycle") && actionCount !== 1) {
    throw new Error("--lifecycle must be used alone");
  }
  if (raw.actions.has("dry-run") && actionCount !== 1) {
    throw new Error("--dry-run must be used alone");
  }
  const command: DatasetCommand = {
    kind: "dataset",
    projectId: requiredValue(raw.values, "project"),
    periodKey: requiredValue(raw.values, "period"),
    runId: requiredValue(raw.values, "run-id"),
    regionId: optionalValue(raw.values, "region-id") ?? undefined,
    usersPerRegion: Number(raw.values.get("users-per-region") ?? "100"),
    actions: raw.actions,
    firebaseCliAuth: raw.firebaseCliAuth,
    confirmProject: optionalValue(raw.values, "confirm-project"),
    confirmCleanup: optionalValue(raw.values, "confirm-cleanup"),
    confirmPeriod: optionalValue(raw.values, "confirm-period"),
    confirmRegion: optionalValue(raw.values, "confirm-region"),
    confirmUsers: optionalValue(raw.values, "confirm-users"),
    confirmInventory: optionalValue(raw.values, "confirm-inventory"),
    replacementRunId: optionalValue(raw.values, "replacement-run-id"),
  };
  assertProductionCommandAuthorization(command);
  return command;
}

function assertProductionCommandAuthorization(command: DatasetCommand): void {
  if (!isProduction()) {
    return;
  }
  if (requiresMutationAuthorization(command) && !command.firebaseCliAuth) {
    throw new Error("production mutation requires --firebase-cli-auth");
  }
  if (!command.actions.has("cleanup")) {
    return;
  }
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
  if (command.confirmCleanup !== command.runId) {
    throw new Error(`repeat --confirm-cleanup ${command.runId} for cleanup`);
  }
  if (command.confirmInventory === null) {
    throw new Error("production cleanup requires --confirm-inventory <fingerprint>");
  }
  if (command.replacementRunId === null) {
    throw new Error("production cleanup requires --replacement-run-id <runId>");
  }
}

function requiresMutationAuthorization(command: DatasetCommand): boolean {
  return command.actions.has("seed") ||
    command.actions.has("refresh") ||
    command.actions.has("verify") ||
    command.actions.has("cleanup");
}

function isSeedAction(value: string): value is SeedAction {
  switch (value) {
    case "dry-run":
    case "seed":
    case "refresh":
    case "verify":
    case "cleanup":
    case "preview-cleanup":
    case "lifecycle":
    case "inventory":
      return true;
    default:
      return false;
  }
}

function requiredValue(values: ReadonlyMap<string, string>, key: string): string {
  const value = optionalValue(values, key);
  if (value === null) {
    throw new Error(`missing --${key}`);
  }
  return value;
}

function optionalValue(
  values: ReadonlyMap<string, string>,
  key: string,
): string | null {
  const value = values.get(key)?.trim();
  return value === undefined || value.length === 0 ? null : value;
}

function isProduction(): boolean {
  return process.env["FIRESTORE_EMULATOR_HOST"] === undefined;
}
