import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onCall } from "firebase-functions/v2/https";
import { createHomeGuideAgentHandler } from "./homeGuideAgentHandler.js";
import {
  createHomeGuideModelProvider,
  homeGuideModelEnvironmentFromProcess,
  type HomeGuideModelProvider,
} from "./homeGuideModel.js";
import { shouldEnforceAppCheck } from "../security/appCheck.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

const handler = createHomeGuideAgentHandler({
  firestore: getFirestore,
  now: () => new Date(),
  providerFactory: createProvider,
});

export const homeGuideAgent = onCall(
  {
    region: "asia-southeast1",
    secrets: [OPENAI_API_KEY],
    enforceAppCheck: shouldEnforceAppCheck(),
  },
  withCallableErrorReporting("homeGuideAgent", handler),
);

function createProvider(): HomeGuideModelProvider {
  const environment = homeGuideModelEnvironmentFromProcess();
  return createHomeGuideModelProvider({
    apiKey: environment.fakeProviderFlag === undefined ? resolveOpenAiApiKey() : undefined,
    environment,
  });
}

function resolveOpenAiApiKey(): string | undefined {
  try {
    const value = OPENAI_API_KEY.value();
    return value.length > 0 ? value : undefined;
  } catch (error) {
    if (error instanceof Error) return undefined;
    throw error;
  }
}
