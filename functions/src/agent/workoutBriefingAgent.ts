import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onCall } from "firebase-functions/v2/https";
import { createWorkoutBriefingAgentHandler } from "./workoutBriefingAgentHandler.js";
import {
  createWorkoutBriefingModelProvider,
  workoutBriefingModelEnvironmentFromProcess,
  type WorkoutBriefingModelProvider,
} from "./workoutBriefingModel.js";
import { shouldEnforceAppCheck } from "../security/appCheck.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

const handler = createWorkoutBriefingAgentHandler({
  firestore: getFirestore,
  now: () => new Date(),
  providerFactory: createProvider,
});

export const workoutBriefingAgent = onCall(
  {
    region: "asia-southeast1",
    secrets: [OPENAI_API_KEY],
    enforceAppCheck: shouldEnforceAppCheck(),
  },
  withCallableErrorReporting("workoutBriefingAgent", handler),
);

function createProvider(): WorkoutBriefingModelProvider {
  const environment = workoutBriefingModelEnvironmentFromProcess();
  return createWorkoutBriefingModelProvider({
    apiKey: environment.fakeProviderFlag === undefined
      ? resolveOpenAiApiKey()
      : undefined,
    environment,
  });
}

// A missing secret must degrade to deterministic fallback copy, never to a 500.
function resolveOpenAiApiKey(): string | undefined {
  try {
    const value = OPENAI_API_KEY.value();
    return value.length > 0 ? value : undefined;
  } catch (error) {
    if (error instanceof Error) return undefined;
    throw error;
  }
}
