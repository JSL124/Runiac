export const feedFixtureScenarios = ["reset", "baseline", "unfriend", "block-viewer", "block-author", "delete-activity"] as const;
export type FeedFixtureScenario = (typeof feedFixtureScenarios)[number];
export type FeedFixtureEnvironment = Readonly<Record<string, string | undefined>>;
export type FixtureGuardError = { readonly kind: "invalid_fixture_environment"; readonly field: string };
export type FeedFixtureEnvironmentResult =
  | { readonly ok: true }
  | { readonly ok: false; readonly error: FixtureGuardError };
export type FixtureScenarioResult =
  | { readonly ok: true; readonly scenario: FeedFixtureScenario }
  | { readonly ok: false; readonly error: FixtureGuardError | { readonly kind: "invalid_fixture_scenario" } };

const requiredEnvironment = {
  GCLOUD_PROJECT: "demo-runiac-feed",
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
  FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5001",
  FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199",
} as const;

export function assertFeedFixtureEnvironment(environment: FeedFixtureEnvironment): FeedFixtureEnvironmentResult {
  for (const [field, expected] of Object.entries(requiredEnvironment)) {
    if (environment[field] !== expected) return { ok: false, error: { kind: "invalid_fixture_environment", field } };
  }
  return { ok: true };
}

export async function runFeedFixtureScenario(input: {
  readonly environment: FeedFixtureEnvironment;
  readonly scenario: string;
  readonly mutate: (scenario: FeedFixtureScenario) => Promise<void>;
}): Promise<FixtureScenarioResult> {
  const guard = assertFeedFixtureEnvironment(input.environment);
  if (!guard.ok) return guard;
  if (!isFixtureScenario(input.scenario)) return { ok: false, error: { kind: "invalid_fixture_scenario" } };
  await input.mutate(input.scenario);
  return { ok: true, scenario: input.scenario };
}

function isFixtureScenario(value: string): value is FeedFixtureScenario {
  switch (value) {
    case "reset":
    case "baseline":
    case "unfriend":
    case "block-viewer":
    case "block-author":
    case "delete-activity":
      return true;
    default:
      return false;
  }
}
