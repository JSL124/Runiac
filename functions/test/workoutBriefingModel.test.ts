import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  WORKOUT_BRIEFING_MODEL_CONFIG,
  buildWorkoutBriefingModelPrompt,
  createWorkoutBriefingModelProvider,
  generateWorkoutBriefingSections,
  type WorkoutBriefingModelEnvironment,
  type WorkoutBriefingModelProvider,
  type WorkoutBriefingProviderRequest,
} from "../src/agent/workoutBriefingModel.js";
import { WORKOUT_BRIEFING_FALLBACK_SECTIONS } from "../src/agent/workoutBriefingModelOutput.js";
import type { WorkoutBriefingRequest } from "../src/agent/workoutBriefingTypes.js";

describe("buildWorkoutBriefingModelPrompt", () => {
  it("states the beginner-coach role and the invention ban in the system prompt", () => {
    // Given / When
    const prompt = buildWorkoutBriefingModelPrompt(request());

    // Then
    assert.match(prompt.systemPrompt, /beginner-running coach/u);
    assert.match(prompt.systemPrompt, /never state a number that was not given to you/u);
    assert.match(prompt.systemPrompt, /untrusted display text/u);
    assert.match(prompt.systemPrompt, /Write in English\./u);
  });

  it("sends the parsed request verbatim and carries no identifier field", () => {
    // Given / When
    const prompt = buildWorkoutBriefingModelPrompt(request());
    const payload: unknown = JSON.parse(prompt.userPrompt.split("Planned session: ")[1] ?? "null");

    // Then
    assert.deepEqual(payload, request());
    // Asserted over the key set rather than raw substrings, because ordinary
    // coaching words contain identifier fragments ("guide" contains "uid").
    const keys = collectKeys(payload);
    assert.deepEqual([...keys].sort(), [
      "coachNotes",
      "dayLabel",
      "detail",
      "effortGuide",
      "label",
      "metrics",
      "planTitle",
      "schemaVersion",
      "steps",
      "title",
      "value",
      "weekNumber",
      "workout",
    ]);
    for (const forbidden of ["uid", "planId", "activityId", "polyline", "coordinates", "latitude"]) {
      assert.equal(keys.has(forbidden), false, `${forbidden} must not be a payload key`);
    }
  });

  it("pins a single-shot, bounded model configuration", () => {
    // Given / When / Then
    assert.equal(WORKOUT_BRIEFING_MODEL_CONFIG.model, "gpt-4o-mini");
    assert.equal(WORKOUT_BRIEFING_MODEL_CONFIG.maxRetries, 0);
    assert.equal(WORKOUT_BRIEFING_MODEL_CONFIG.timeout, 10_000);
  });
});

describe("generateWorkoutBriefingSections", () => {
  it("returns generated sections when the provider answers in shape", async () => {
    // Given
    const provider = new StubProvider(safeOutput());

    // When
    const outcome = await generateWorkoutBriefingSections({ provider, request: request() });

    // Then
    assert.equal(outcome.kind, "generated");
    assert.equal(
      outcome.kind === "generated" ? outcome.sections.todaySession : "",
      safeOutput().todaySession,
    );
  });

  it("classifies a provider rejection as provider_error", async () => {
    // Given
    const provider = new StubProvider(() => Promise.reject(new Error("private provider detail")));

    // When
    const outcome = await generateWorkoutBriefingSections({ provider, request: request() });

    // Then
    assert.deepEqual(outcome, { kind: "fallback", fallbackCategory: "provider_error" });
  });

  it("classifies a hung provider as timeout", async () => {
    // Given
    const provider = new StubProvider(() => new Promise(() => {}));

    // When
    const outcome = await generateWorkoutBriefingSections({
      provider,
      request: request(),
      timeoutMillis: 10,
    });

    // Then
    assert.deepEqual(outcome, { kind: "fallback", fallbackCategory: "timeout" });
  });

  it("classifies wrong shapes as json_shape", async () => {
    // Given
    const wrongShapes: readonly unknown[] = [
      null,
      "text",
      [],
      { todaySession: "a", whyItHelps: "b", howItFeels: "c" },
      { todaySession: "a", whyItHelps: "b", howItFeels: "c", beforeYouStart: "d", extra: "e" },
      { todaySession: 1, whyItHelps: "b", howItFeels: "c", beforeYouStart: "d" },
    ];

    // When / Then
    for (const value of wrongShapes) {
      const outcome = await generateWorkoutBriefingSections({
        provider: new StubProvider(value),
        request: request(),
      });
      assert.deepEqual(
        outcome,
        { kind: "fallback", fallbackCategory: "json_shape" },
        `expected json_shape for ${JSON.stringify(value)}`,
      );
    }
  });

  it("classifies each policy violation as policy_validation", async () => {
    // Given
    const violations: Readonly<Record<string, string>> = {
      url: "Read more at https://example.com about easy running.",
      markdown: "**Today** is an easy run.",
      diagnosis: "This will help your knee injury heal properly.",
      shame: "Do not be lazy about this session.",
      competitive: "Finish this run to earn XP on the leaderboard.",
      tooLong: "x".repeat(281),
      blank: "   ",
    };

    // When / Then
    for (const [name, value] of Object.entries(violations)) {
      const outcome = await generateWorkoutBriefingSections({
        provider: new StubProvider({ ...safeOutput(), todaySession: value }),
        request: request(),
      });
      assert.deepEqual(
        outcome,
        { kind: "fallback", fallbackCategory: "policy_validation" },
        `expected policy_validation for ${name}`,
      );
    }
  });

  it("ships deterministic fallback copy that passes its own policy guard", async () => {
    // Given
    const provider = new StubProvider(WORKOUT_BRIEFING_FALLBACK_SECTIONS);

    // When
    const outcome = await generateWorkoutBriefingSections({ provider, request: request() });

    // Then
    assert.equal(outcome.kind, "generated");
  });
});

describe("createWorkoutBriefingModelProvider", () => {
  it("uses the deterministic provider only under the verified emulator triple", async () => {
    // Given
    const provider = createWorkoutBriefingModelProvider({
      apiKey: undefined,
      environment: environment({
        functionsEmulator: "true",
        projectId: "runiac-functions-test",
        fakeProviderFlag: "deterministic",
      }),
    });

    // When
    const outcome = await generateWorkoutBriefingSections({ provider, request: request() });

    // Then
    assert.equal(outcome.kind, "generated");
  });

  it("downgrades a stray fake flag to unavailable rather than to a real model call", async () => {
    // Given
    const strayEnvironments: readonly WorkoutBriefingModelEnvironment[] = [
      environment({ functionsEmulator: undefined, projectId: "runiac-functions-test", fakeProviderFlag: "deterministic" }),
      environment({ functionsEmulator: "true", projectId: "runiac-fypp", fakeProviderFlag: "deterministic" }),
      environment({ functionsEmulator: "true", projectId: "runiac-functions-test", fakeProviderFlag: "yes" }),
    ];

    // When / Then
    for (const candidate of strayEnvironments) {
      // A real key is supplied on purpose: the flag must still not select OpenAI.
      const provider = createWorkoutBriefingModelProvider({ apiKey: "sk-real", environment: candidate });
      const outcome = await generateWorkoutBriefingSections({ provider, request: request() });
      assert.deepEqual(
        outcome,
        { kind: "fallback", fallbackCategory: "provider_error" },
        `expected unavailable for ${JSON.stringify(candidate)}`,
      );
    }
  });

  it("falls back to unavailable when no API key is resolvable", async () => {
    // Given
    const provider = createWorkoutBriefingModelProvider({
      apiKey: "",
      environment: environment({ functionsEmulator: undefined, projectId: undefined, fakeProviderFlag: undefined }),
    });

    // When
    const outcome = await generateWorkoutBriefingSections({ provider, request: request() });

    // Then
    assert.deepEqual(outcome, { kind: "fallback", fallbackCategory: "provider_error" });
  });
});

/// Every object key reachable in the payload, at any depth.
function collectKeys(value: unknown, into: Set<string> = new Set()): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) collectKeys(item, into);
    return into;
  }
  if (typeof value === "object" && value !== null) {
    for (const [key, nested] of Object.entries(value)) {
      into.add(key);
      collectKeys(nested, into);
    }
  }
  return into;
}

function environment(
  overrides: Partial<WorkoutBriefingModelEnvironment>,
): WorkoutBriefingModelEnvironment {
  return {
    functionsEmulator: undefined,
    projectId: undefined,
    fakeProviderFlag: undefined,
    ...overrides,
  };
}

function request(): WorkoutBriefingRequest {
  return {
    schemaVersion: 1,
    workout: {
      dayLabel: "Thursday · Easy Run",
      planTitle: "First Continuous Running Start",
      effortGuide: "Keep the effort easy enough to talk in full sentences.",
      weekNumber: 3,
    },
    metrics: [{ label: "Distance", value: "3.0 km" }],
    steps: [{ title: "Warm up", detail: "Walk briskly for five minutes." }],
    coachNotes: ["Start slower than you think."],
  };
}

function safeOutput() {
  return {
    todaySession: "Today is a short easy run with a walking warm up first.",
    whyItHelps: "Easy running like this builds the habit without wearing you out.",
    howItFeels: "You should be able to speak in full sentences the whole way.",
    beforeYouStart: "Set off slower than feels natural and walk whenever you need to.",
  };
}

class StubProvider implements WorkoutBriefingModelProvider {
  public calls = 0;

  public constructor(private readonly result: unknown | (() => Promise<unknown>)) {}

  public async invoke(_request: WorkoutBriefingProviderRequest): Promise<unknown> {
    this.calls += 1;
    return typeof this.result === "function" ? this.result() : this.result;
  }
}
