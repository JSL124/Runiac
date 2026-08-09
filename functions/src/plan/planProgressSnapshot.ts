import type { DocumentData } from "firebase-admin/firestore";
import type { RawRunCompletionPayload } from "../run/runCompletionTypes.js";
import { isRecord, readOptionalString } from "./planProgressParsing.js";

export function trustedPlanData(
  generatedPlanData: DocumentData | undefined,
  progressData: DocumentData | undefined,
  payload: RawRunCompletionPayload,
): DocumentData | undefined {
  const enrollmentId = payload.planEnrollmentId;
  if (enrollmentId === undefined) {
    return generatedPlanData;
  }

  const storedPlanData = readStoredPlanSnapshot(progressData, enrollmentId);
  if (storedPlanData !== undefined) {
    return storedPlanData;
  }

  return readGeneratedPlanId(generatedPlanData) === enrollmentId ? generatedPlanData : undefined;
}

export function readGeneratedPlanId(generatedPlanData: DocumentData | undefined): string | undefined {
  if (generatedPlanData === undefined) {
    return undefined;
  }

  return readOptionalString(generatedPlanData["planId"]);
}

export function planSnapshot(planData: DocumentData | undefined): Readonly<Record<string, unknown>> {
  if (planData === undefined) {
    return {};
  }

  return {
    planId: readGeneratedPlanId(planData),
    startsOnDate: readOptionalString(planData["startsOnDate"]) ?? null,
    weeks: Array.isArray(planData["weeks"]) ? planData["weeks"] : [],
  };
}

function readStoredPlanSnapshot(progressData: DocumentData | undefined, planId: string): DocumentData | undefined {
  if (progressData === undefined) {
    return undefined;
  }

  const snapshotsValue: unknown = progressData["planSnapshots"];
  if (!isRecord(snapshotsValue)) {
    return undefined;
  }

  const planValue: unknown = snapshotsValue[planId];
  return isRecord(planValue) ? planValue : undefined;
}
