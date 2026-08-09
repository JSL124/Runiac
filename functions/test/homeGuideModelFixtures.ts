import type { HomeGuideEvidence, HomeGuideEvidenceFact, HomeGuidePlanDisplayContext } from "../src/agent/homeGuideContracts.js";
import type { HomeGuideModelProvider, HomeGuideProviderRequest } from "../src/agent/homeGuideModel.js";

export function modelPlanContext(): HomeGuidePlanDisplayContext {
  return {
    planTitle: "Beginner running plan",
    weekNumber: 2,
    weekFocus: "Build endurance",
    dayLabel: "Wednesday",
    workoutTitle: "Easy run",
    durationMinutes: 25,
    intensity: "easy",
    description: "Steady and comfortable.",
    steps: ["Warm up", "Run easily"],
    supportiveNote: "Keep it comfortable.",
  };
}

export function evidenceFact(
  direction: HomeGuideEvidenceFact["direction"],
  id: string = "week_to_date.distance",
): HomeGuideEvidenceFact {
  return {
    id,
    window: "week_to_date",
    metric: "distance",
    direction,
    text: "Distance: 4.0 km vs 3.0 km (+1.0 km, +33%).",
  };
}

export function evidence(...facts: readonly HomeGuideEvidenceFact[]): HomeGuideEvidence {
  return { facts };
}

export function modelOutput(overrides: Readonly<Record<string, unknown>> = {}): Readonly<Record<string, unknown>> {
  return {
    schemaVersion: 1,
    planSummaryText: "The planned session is ready.",
    runningTipText: "Keep the effort relaxed and conversational.",
    selectedProgressionFactIds: [],
    nextActionCode: "build_baseline",
    ...overrides,
  };
}

export class StubProvider implements HomeGuideModelProvider {
  public calls = 0;

  public constructor(private readonly response: unknown | (() => Promise<unknown>)) {}

  public async invoke(_request: HomeGuideProviderRequest): Promise<unknown> {
    this.calls += 1;
    return typeof this.response === "function" ? this.response() : this.response;
  }
}
