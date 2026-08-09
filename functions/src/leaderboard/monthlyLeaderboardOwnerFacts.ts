import type { Firestore } from "firebase-admin/firestore";
import { isPremiumSubscription } from "../progression/progressionAuditHelpers.js";
import {
  leaderboardLeagueForKey,
  leaderboardLeagueForLevel,
} from "../progression/leaderboardLeagues.js";
import { singaporePlanningAreaForLocationLabel } from "./singaporePlanningAreas.js";
import { monthlyLeaderboardSnapshotId } from "./monthlyLeaderboardPlanner.js";
import type { MonthlyLeaderboardCurrentViewPlan } from "./leaderboardTypes.js";

const profileReadChunkSize = 250;

export type OwnerFacts = {
  readonly isPremium: boolean;
  readonly profile: FirebaseFirestore.DocumentData | undefined;
};

export async function readOwnerFacts(
  firestore: Firestore,
  ownerUids: ReadonlySet<string>,
  nowMs: number,
): Promise<ReadonlyMap<string, OwnerFacts>> {
  const result = new Map<string, OwnerFacts>();
  const uids = [...ownerUids];
  for (let index = 0; index < uids.length; index += profileReadChunkSize) {
    const chunk = uids.slice(index, index + profileReadChunkSize);
    const refs = chunk.flatMap((uid) => [
      firestore.collection("users").doc(uid),
      firestore.collection("userProfiles").doc(uid),
    ]);
    const snapshots = refs.length === 0 ? [] : await firestore.getAll(...refs);
    for (let offset = 0; offset < chunk.length; offset += 1) {
      const uid = chunk[offset];
      if (uid === undefined) {
        continue;
      }
      const userData = snapshots[offset * 2]?.data();
      const profileData = snapshots[offset * 2 + 1]?.data();
      result.set(uid, {
        isPremium:
          isPremiumSubscription(userData, nowMs) ||
          isPremiumSubscription(profileData, nowMs),
        profile: profileData,
      });
    }
  }
  return result;
}
export function mergeRolloverViews(input: {
  readonly periodKey: string;
  readonly plannedViews: readonly MonthlyLeaderboardCurrentViewPlan[];
  readonly rolloverUids: readonly string[];
  readonly ownerFacts: ReadonlyMap<string, OwnerFacts>;
  readonly excludePremium?: boolean;
}): MonthlyLeaderboardCurrentViewPlan[] {
  const excludePremium = input.excludePremium ?? false;
  const views = new Map(
    input.plannedViews.map((view) => [view.ownerUid, view]),
  );
  for (const uid of input.rolloverUids) {
    if (views.has(uid)) {
      continue;
    }
    const facts = input.ownerFacts.get(uid);
    const area = singaporePlanningAreaForLocationLabel(
      facts?.profile?.["locationLabel"],
    );
    const league =
      leaderboardLeagueForKey(facts?.profile?.["divisionKey"]) ??
      leaderboardLeagueForLevel(readLevel(facts?.profile?.["level"]));
    const status = excludePremium && facts?.isPremium
      ? "ineligible_premium"
      : area === null
        ? "region_required"
        : "unranked";
    views.set(uid, {
      ownerUid: uid,
      snapshotId:
        area === null
          ? null
          : monthlyLeaderboardSnapshotId({
              periodKey: input.periodKey,
              regionId: area.regionId,
              divisionKey: league.key,
            }),
      rankId: null,
      periodKey: input.periodKey,
      regionId: area?.regionId ?? null,
      divisionKey: league.key,
      status,
    });
  }
  return [...views.values()].sort((left, right) =>
    left.ownerUid.localeCompare(right.ownerUid),
  );
}

function readLevel(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.floor(value)
    : 1;
}
