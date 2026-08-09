// The LLM call behind AI activity feedback: prompt construction, the provider
// seam, and output validation.
//
// Model output is never trusted as-is. It is validated against the expected
// section structure (`activityFeedbackModelOutput.ts`) and rejected on
// mismatch, so a malformed or off-topic completion surfaces as a failure rather
// than as advice shown to a runner.
//
// [ActivityFeedbackModelProvider] is the seam that makes this testable: the
// suites run a deterministic fake provider, which is why the functions tests
// need no OpenAI key.

import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { ChatOpenAI } from "@langchain/openai";
import type {
  ActivityFeedbackRequest,
  ActivityFeedbackSections,
} from "./activityFeedbackTypes.js";
import {
  validateActivityFeedbackModelOutputDetailed,
  type ActivityFeedbackModelValidationIssue,
} from "./activityFeedbackModelOutput.js";

export { validateActivityFeedbackModelOutput } from "./activityFeedbackModelOutput.js";

export const ACTIVITY_FEEDBACK_MODEL_CONFIG = {
  model: "gpt-4o-mini",
  temperature: 0.2,
  maxTokens: 360,
  timeout: 10_000,
  maxRetries: 0,
} as const;

const OUTPUT_SCHEMA = {
  summary: "beginner-safe run summary",
  wentWell: "what went well",
  improve: "one improvement area",
  nextFocus: "one next focus",
} as const;

export type ActivityFeedbackProviderRequest = {
  readonly systemPrompt: string;
  readonly userPrompt: string;
};

export interface ActivityFeedbackModelProvider {
  invoke(request: ActivityFeedbackProviderRequest): Promise<unknown>;
}

export type ActivityFeedbackModelPrompt = {
  readonly systemPrompt: string;
  readonly userPrompt: string;
};

export type ActivityFeedbackProviderFactoryInput = {
  readonly apiKey: string | undefined;
  readonly environment: ActivityFeedbackModelEnvironment;
};

export type ActivityFeedbackModelEnvironment = {
  readonly functionsEmulator: string | undefined;
  readonly projectId: string | undefined;
  readonly fakeProviderFlag: string | undefined;
};

export type ActivityFeedbackGenerationFallbackCategory =
  | "provider_error"
  | "timeout"
  | ActivityFeedbackModelValidationIssue;

export type ActivityFeedbackGenerationOutcome =
  | { readonly kind: "generated"; readonly sections: ActivityFeedbackSections }
  | {
      readonly kind: "fallback";
      readonly fallbackCategory: ActivityFeedbackGenerationFallbackCategory;
    };

export type ActivityFeedbackModelGenerationInput = {
  readonly provider: ActivityFeedbackModelProvider;
  readonly metrics: ActivityFeedbackRequest;
  readonly timeoutMillis?: number;
};

export function buildActivityFeedbackModelPrompt(
  metrics: ActivityFeedbackRequest,
): ActivityFeedbackModelPrompt {
  return {
    systemPrompt:
      "Return JSON only matching the requested schema. You are Runiac's beginner-running feedback agent. Use only supplied derived metrics. Be specific but cautious. Qualify estimated cadence as estimated. Do not diagnose injuries, shame the runner, mention XP, rank, leaderboard rewards, URLs, markdown, route names, locations, or unsupported claims.",
    userPrompt: `Schema: ${JSON.stringify(OUTPUT_SCHEMA)}\nDerived metrics: ${JSON.stringify(metrics)}`,
  };
}

export async function generateActivityFeedbackSections(
  input: ActivityFeedbackModelGenerationInput,
): Promise<ActivityFeedbackGenerationOutcome> {
  const prompt = buildActivityFeedbackModelPrompt(input.metrics);
  const timeoutMillis = input.timeoutMillis ?? ACTIVITY_FEEDBACK_MODEL_CONFIG.timeout;
  let output: unknown;
  try {
    output = await invokeWithTimeout(input.provider, prompt, timeoutMillis);
  } catch (error) {
    if (error instanceof ActivityFeedbackModelTimeoutError) {
      return { kind: "fallback", fallbackCategory: "timeout" };
    }
    return { kind: "fallback", fallbackCategory: "provider_error" };
  }
  const validation = validateActivityFeedbackModelOutputDetailed(output);
  if (validation.kind === "invalid") {
    return { kind: "fallback", fallbackCategory: validation.issue };
  }
  return { kind: "generated", sections: validation.sections };
}

export function createActivityFeedbackModelProvider(
  input: ActivityFeedbackProviderFactoryInput,
): ActivityFeedbackModelProvider {
  if (input.environment.fakeProviderFlag !== undefined) {
    return isVerifiedFakeEnvironment(input.environment)
      ? new DeterministicActivityFeedbackProvider()
      : new UnavailableActivityFeedbackProvider();
  }
  return input.apiKey === undefined || input.apiKey.length === 0
    ? new UnavailableActivityFeedbackProvider()
    : new OpenAiActivityFeedbackProvider(input.apiKey);
}

export function activityFeedbackModelEnvironmentFromProcess(): ActivityFeedbackModelEnvironment {
  return {
    functionsEmulator: process.env["FUNCTIONS_EMULATOR"],
    projectId: process.env["GCLOUD_PROJECT"],
    fakeProviderFlag: process.env["RUNIAC_ACTIVITY_FEEDBACK_FAKE_PROVIDER"],
  };
}

class DeterministicActivityFeedbackProvider implements ActivityFeedbackModelProvider {
  public async invoke(_request: ActivityFeedbackProviderRequest): Promise<unknown> {
    return {
      summary: "You completed a steady run with useful derived metrics.",
      wentWell: "Your pacing and captured effort signals give you a clear baseline.",
      improve: "Start the next run a little easier before settling into rhythm.",
      nextFocus: "Keep one relaxed, repeatable session as the next target.",
    };
  }
}

class UnavailableActivityFeedbackProvider implements ActivityFeedbackModelProvider {
  public async invoke(_request: ActivityFeedbackProviderRequest): Promise<unknown> {
    return Promise.reject(new ActivityFeedbackModelUnavailableError());
  }
}

class OpenAiActivityFeedbackProvider implements ActivityFeedbackModelProvider {
  private readonly model: ChatOpenAI;

  public constructor(apiKey: string) {
    this.model = new ChatOpenAI({ apiKey, ...ACTIVITY_FEEDBACK_MODEL_CONFIG });
  }

  public async invoke(request: ActivityFeedbackProviderRequest): Promise<unknown> {
    const response = await this.model.invoke([
      new SystemMessage(request.systemPrompt),
      new HumanMessage(request.userPrompt),
    ]);
    return parseJsonResponse(response.content);
  }
}

class ActivityFeedbackModelUnavailableError extends Error {
  public constructor() {
    super("Activity feedback model provider is unavailable.");
    this.name = "ActivityFeedbackModelUnavailableError";
  }
}

class ActivityFeedbackModelTimeoutError extends Error {
  public constructor() {
    super("Activity feedback model provider timed out.");
    this.name = "ActivityFeedbackModelTimeoutError";
  }
}

function isVerifiedFakeEnvironment(
  environment: ActivityFeedbackModelEnvironment,
): boolean {
  return (
    environment.functionsEmulator === "true" &&
    environment.projectId === "runiac-functions-test" &&
    environment.fakeProviderFlag === "deterministic"
  );
}

async function invokeWithTimeout(
  provider: ActivityFeedbackModelProvider,
  request: ActivityFeedbackProviderRequest,
  timeoutMillis: number,
): Promise<unknown> {
  if (!Number.isFinite(timeoutMillis) || timeoutMillis <= 0) {
    return Promise.reject(new ActivityFeedbackModelUnavailableError());
  }
  let timeout: NodeJS.Timeout | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timeout = setTimeout(
      () => reject(new ActivityFeedbackModelTimeoutError()),
      timeoutMillis,
    );
  });
  try {
    return await Promise.race([provider.invoke(request), deadline]);
  } finally {
    if (timeout !== undefined) clearTimeout(timeout);
  }
}

function parseJsonResponse(content: unknown): unknown {
  if (typeof content === "string") {
    return JSON.parse(content);
  }
  return content;
}
