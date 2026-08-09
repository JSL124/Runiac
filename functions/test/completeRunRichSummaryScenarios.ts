import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { completeRunForCallable } from "../src/run/completeRun.js";
import type { CompleteRunResult } from "../src/run/runCompletionTypes.js";
import { rejectionScenarios } from "./completeRunRichSummaryCases.js";
import {
  validElevationSeries,
  validElevationSeriesWithSampleCount,
  validPaceAnalysisSeries,
  validPaceAnalysisSeriesWithSampleCount,
  validPayload,
  validRoutePreview,
} from "./completeRunRichSummaryFixtures.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "runner-001";

describe("completeRun masked rich summary contract", () => {
  let firestore: Firestore;

  before(() => {
    if (getApps().length === 0) {
      initializeApp({ projectId: PROJECT_ID });
    }
    firestore = getFirestore();
  });

  beforeEach(async () => {
    await clearCollections(firestore, [
      "activities",
      "runSummaries",
      "progressionEvents",
      "users",
      "userProfiles",
      "generatedPlans",
      "planProgress",
      "adaptivePlanEstimates",
      "leaderboardContributions",
    ]);
    await firestore.doc(`userProfiles/${USER_UID}`).set({
      nickname: "Test Runner",
      locationLabel: "Jurong East, Singapore",
    });
  });

  it("persists and returns rich run detail only through the owner scoped summary", async () => {
    const routePreview = validRoutePreview(1, 2);
    const paceAnalysisSeries = validPaceAnalysisSeries();
    const elevationSeries = validElevationSeries();
    const result = await callCompleteRun(firestore, {
      ...validPayload(),
      clientRunSessionId: "local-session-rich-summary",
      routePreview,
      paceAnalysisSeries,
      elevationSeries,
    });

    const activity = await firestore.doc(`activities/${result.activityId}`).get();
    const summary = await firestore.doc(`runSummaries/${result.summaryId}`).get();

    assert.deepEqual(result.runSummary.routePreview, routePreview);
    assert.deepEqual(result.runSummary.paceAnalysisSeries, paceAnalysisSeries);
    assert.deepEqual(result.runSummary.elevationSeries, elevationSeries);
    assert.deepEqual(summary.get("routePreview"), routePreview);
    assert.deepEqual(summary.get("paceAnalysisSeries"), paceAnalysisSeries);
    assert.deepEqual(summary.get("elevationSeries"), elevationSeries);
    assert.equal(activity.get("routePreview"), undefined);
    assert.equal(summary.get("routeSnapshot"), undefined);
    assert.equal(activity.get("paceAnalysisSeries"), undefined);
    assert.equal(activity.get("elevationSeries"), undefined);
  });

  it("persists the maximum bounded rich run detail sample counts", async () => {
    const routePreview = validRoutePreview(64, 4);
    const paceAnalysisSeries = validPaceAnalysisSeriesWithSampleCount(360);
    const elevationSeries = validElevationSeriesWithSampleCount(360);
    const result = await callCompleteRun(firestore, {
      ...validPayload(),
      clientRunSessionId: "local-session-rich-summary-max",
      routePreview,
      paceAnalysisSeries,
      elevationSeries,
    });
    const summary = await firestore.doc(`runSummaries/${result.summaryId}`).get();

    assert.deepEqual(result.runSummary.routePreview, routePreview);
    assert.deepEqual(result.runSummary.paceAnalysisSeries, paceAnalysisSeries);
    assert.deepEqual(result.runSummary.elevationSeries, elevationSeries);
    assert.deepEqual(summary.get("routePreview"), routePreview);
    assert.deepEqual(summary.get("paceAnalysisSeries"), paceAnalysisSeries);
    assert.deepEqual(summary.get("elevationSeries"), elevationSeries);
  });

  for (const scenario of rejectionScenarios()) {
    it(scenario.name, async () => {
      await expectRejectsCodeAndMessage(
        () =>
          callCompleteRun(firestore, {
            ...validPayload(),
            clientRunSessionId: "rich-summary-rejected",
            ...scenario.richData,
          }),
        "invalid-argument",
        scenario.expectedMessage,
      );
      assert.equal(await countDocuments(firestore, "runSummaries"), 0);
    });
  }
});

async function callCompleteRun(
  firestore: Firestore,
  data: Readonly<Record<string, unknown>>,
): Promise<CompleteRunResult> {
  return completeRunForCallable({ auth: { uid: USER_UID }, data }, firestore);
}

async function countDocuments(firestore: Firestore, collectionName: string): Promise<number> {
  return (await firestore.collection(collectionName).get()).size;
}

async function clearCollections(
  firestore: Firestore,
  collectionNames: readonly string[],
): Promise<void> {
  await Promise.all(
    collectionNames.map(async (collectionName) => {
      const snapshot = await firestore.collection(collectionName).get();
      await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
    }),
  );
}

async function expectRejectsCodeAndMessage(
  action: () => Promise<unknown>,
  code: string,
  message: string,
): Promise<void> {
  await assert.rejects(action, (error: unknown) => {
    assert.equal(getErrorCode(error), code);
    assert.equal(error instanceof Error ? error.message : "", message);
    return true;
  });
}

function getErrorCode(error: unknown): string {
  if (!isRecord(error) || typeof error["code"] !== "string") {
    return "";
  }
  return error["code"];
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
