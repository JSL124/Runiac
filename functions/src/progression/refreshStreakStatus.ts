import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { dailyCapDateForCompletedAt } from "./progressionCalculator.js";
import { readTrustedProtectedRestDates } from "./planBoundedStreakState.js";
import {
  calculateStreakExpiryTransition,
  type StreakState,
} from "./streakCalculator.js";

type CallableStreakRefreshRequest = {
  readonly auth?: {
    readonly uid: string;
  };
  readonly data: unknown;
};

export type StreakRefreshResult = {
  readonly streakCount: number;
};

if (getApps().length === 0) {
  initializeApp();
}

export const refreshStreakStatus = onCall(
  { region: "asia-southeast1" },
  async (request) => refreshStreakStatusForCallable(request, getFirestore()),
);

export async function refreshStreakStatusForCallable(
  request: CallableStreakRefreshRequest,
  firestore: Firestore,
  refreshedAt: string = new Date().toISOString(),
): Promise<StreakRefreshResult> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication is required to refresh streak status.",
    );
  }

  return firestore.runTransaction(async (transaction) => {
    const profileRef = firestore.collection("userProfiles").doc(uid);
    const generatedPlanRef = firestore.collection("generatedPlans").doc(uid);
    const [profileSnapshot, generatedPlanSnapshot] = await Promise.all([
      transaction.get(profileRef),
      transaction.get(generatedPlanRef),
    ]);
    const currentState = readStreakState(profileSnapshot.data());
    const transition = calculateStreakExpiryTransition({
      currentState,
      asOfDate: dailyCapDateForCompletedAt(refreshedAt),
      protectedRestDates: readTrustedProtectedRestDates(
        generatedPlanSnapshot.data(),
      ),
    });

    if (transition.shouldUpdateProfile) {
      transaction.set(
        profileRef,
        {
          streakCount: transition.nextStreak,
          streakUpdatedAt: refreshedAt,
        },
        { merge: true },
      );
    }

    return { streakCount: transition.nextStreak };
  });
}

function readStreakState(
  profileData: FirebaseFirestore.DocumentData | undefined,
): StreakState {
  if (profileData === undefined) {
    return { streakCount: 0, lastStreakRunDate: null };
  }

  const streakCount = profileData["streakCount"];
  const lastStreakRunDate = profileData["lastStreakRunDate"];
  const hasPersistedStreak =
    typeof streakCount === "number" &&
    Number.isInteger(streakCount) &&
    streakCount > 0 &&
    typeof lastStreakRunDate === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(lastStreakRunDate);

  return {
    streakCount: hasPersistedStreak ? streakCount : 0,
    lastStreakRunDate: hasPersistedStreak ? lastStreakRunDate : null,
  };
}
