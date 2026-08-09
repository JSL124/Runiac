import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import {
  refreshMonthlyLeaderboardSnapshots,
  writeLeaderboardContribution,
} from "../src/leaderboard/monthlyLeaderboard.js";
import { buildAvatarDownloadUrl } from "../src/profile/avatar/avatarPaths.js";

// A fabricated bucket name for the avatar-resolution tests below. These
// tests never touch the Storage emulator: `refreshMonthlyLeaderboardSnapshots`
// is given an explicit `AvatarUrlContext` carrying this bucket, and
// `testAvatarUrl` mints a URL against the same bucket, so `resolveProfileAvatarUrl`
// can be exercised end-to-end with nothing but the Firestore emulator.
const AVATAR_TEST_BUCKET = "monthly-leaderboard-writer-test.appspot.com";

function testAvatarUrl(objectId: string): string {
  return buildAvatarDownloadUrl({
    bucket: AVATAR_TEST_BUCKET,
    objectPath: `avatars/${objectId}.png`,
    token: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  });
}

describe(
  "monthly leaderboard Firestore writer",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: "runiac-functions-test" });
      }
      firestore = getFirestore();
    });

    beforeEach(async () => {
      await clearCollections(firestore, [
        "users",
        "userProfiles",
        "leaderboardContributions",
        "leaderboardSnapshots",
        "leaderboardUserRanks",
        "leaderboardCurrentViews",
        "leaderboardPeriods",
        "leaderboardAggregationLocks",
        "config",
      ]);
    });

    it("claims one lease and publishes bounded projections before current views", async () => {
      const batch = firestore.batch();
      for (let index = 0; index < 15; index += 1) {
        const uid = `writer-runner-${String(index + 1).padStart(2, "0")}`;
        batch.set(firestore.doc(`users/${uid}`), {
          subscriptionStatus: "basic",
        });
        batch.set(firestore.doc(`userProfiles/${uid}`), {
          nickname: `Writer ${index + 1}`,
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        });
        batch.set(
          firestore.doc(`leaderboardContributions/${uid}_monthly_2026-07`),
          contribution({ ownerUid: uid, scoreXp: 1_000 - index }),
        );
      }
      await batch.commit();

      await firestore.doc("leaderboardAggregationLocks/monthly_2026-07").set({
        periodType: "monthly",
        periodKey: "2026-07",
        buildId: "already-running",
        status: "running",
        leaseExpiresAt: "2026-07-10T00:10:00.000Z",
      });
      const locked = await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:01.000Z"),
        buildId: "writer-build-b",
      });
      assert.equal(locked.status, "skipped_locked");
      await firestore.doc("leaderboardAggregationLocks/monthly_2026-07").delete();
      const completed = await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:02.000Z"),
        buildId: "writer-build-a",
      });
      assert.equal(completed.status, "completed");

      const snapshot = await firestore
        .doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07")
        .get();
      assert.equal(snapshot.get("entryCount"), 15);
      assert.equal(snapshot.get("topEntries").length, 10);
      assert.equal(snapshot.get("entries"), undefined);
      const rank = await firestore
        .doc("leaderboardUserRanks/writer-runner-12_monthly_2026-07")
        .get();
      assert.equal(rank.get("nearbyEntries").length, 5);
      const currentView = await firestore
        .doc("leaderboardCurrentViews/writer-runner-12")
        .get();
      assert.equal(currentView.get("status"), "ranked");
      assert.equal(currentView.get("buildId"), snapshot.get("buildId"));
    });

    it("rolls prior participants into an unranked new monthly period", async () => {
      const uid = "rollover-runner";
      await Promise.all([
        firestore.doc(`users/${uid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${uid}`).set({
          nickname: "Rollover",
          locationLabel: "Tampines, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore.doc(`leaderboardContributions/${uid}_monthly_2026-07`).set(
          contribution({
            ownerUid: uid,
            regionId: "tampines",
            regionLabel: "Tampines",
            planningAreaName: "TAMPINES",
            planningAreaCode: "TM",
            planningRegionCode: "ER",
          }),
        ),
      ]);
      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-20T00:00:00.000Z"),
        buildId: "rollover-july",
      });
      await clearCollections(firestore, ["leaderboardContributions"]);
      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-08", {
        now: new Date("2026-08-01T00:00:00.000Z"),
        buildId: "rollover-august",
      });

      const currentView = await firestore.doc(`leaderboardCurrentViews/${uid}`).get();
      assert.equal(currentView.get("periodKey"), "2026-08");
      assert.equal(currentView.get("homeRegionId"), "tampines");
      assert.equal(currentView.get("status"), "unranked");
      assert.equal(currentView.get("activeRankProjectionId"), null);
    });

    // Premium parity: premium runners earn XP on the same terms as Basic
    // runners, so with no config document they rank on the same board.
    it("includes a premium user by default (config/leaderboard missing)", async () => {
      const uid = "premium-runner-default";
      await Promise.all([
        firestore.doc(`users/${uid}`).set({ subscriptionStatus: "premium" }),
        firestore.doc(`userProfiles/${uid}`).set({
          nickname: "Premium Default",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore
          .doc(`leaderboardContributions/${uid}_monthly_2026-07`)
          .set(contribution({ ownerUid: uid })),
      ]);
      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "premium-default-build",
      });

      const currentView = await firestore
        .doc(`leaderboardCurrentViews/${uid}`)
        .get();
      assert.equal(currentView.get("status"), "ranked");
    });

    // Exclusion remains a supported configuration, just no longer the default.
    it("excludes a premium user when config/leaderboard.excludePremium is true", async () => {
      const uid = "premium-runner-excluded";
      await firestore.doc("config/leaderboard").set({ excludePremium: true });
      await Promise.all([
        firestore.doc(`users/${uid}`).set({ subscriptionStatus: "premium" }),
        firestore.doc(`userProfiles/${uid}`).set({
          nickname: "Premium Excluded",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore
          .doc(`leaderboardContributions/${uid}_monthly_2026-07`)
          .set(contribution({ ownerUid: uid })),
      ]);
      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "premium-excluded-build",
      });

      const currentView = await firestore
        .doc(`leaderboardCurrentViews/${uid}`)
        .get();
      assert.equal(currentView.get("status"), "ineligible_premium");
      await firestore.doc("config/leaderboard").delete();
    });

    // A currentView is only ever `set`, so an owner who stops contributing
    // keeps whatever status was last written. That made a policy change
    // invisible to exactly the users it freed: a premium owner excluded under
    // `excludePremium: true` kept `ineligible_premium` and kept seeing
    // "Monthly ranking is not available for this account yet".
    it("re-evaluates a stale ineligible_premium view once exclusion is off", async () => {
      const uid = "stale-premium-view-runner";
      await Promise.all([
        firestore.doc(`users/${uid}`).set({ subscriptionStatus: "premium" }),
        firestore.doc(`userProfiles/${uid}`).set({
          nickname: "Stale Premium",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        // Written by an earlier run under the old policy. This owner has NO
        // contribution for the period, so nothing puts them in ownerUids.
        firestore.doc(`leaderboardCurrentViews/${uid}`).set({
          ownerUid: uid,
          periodType: "monthly",
          periodKey: "2026-07",
          status: "ineligible_premium",
          snapshotId: null,
          rankId: null,
          activeSnapshotId: null,
          activeRankProjectionId: null,
        }),
      ]);

      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "stale-premium-view-build",
      });

      const currentView = await firestore
        .doc(`leaderboardCurrentViews/${uid}`)
        .get();
      assert.notEqual(
        currentView.get("status"),
        "ineligible_premium",
        "the stale exclusion must not survive a run under the current config",
      );
      assert.equal(currentView.get("status"), "unranked");
    });

    // Same rewrite-on-every-run rule as the premium case above, applied to the
    // minimum-runs gate: a view stamped ineligible_min_runs while the owner was
    // under quota must flip back to ranked once their contribution meets
    // minRunsToQualify, because currentViews are only ever `set`.
    it("re-evaluates a stale ineligible_min_runs view to ranked once the owner meets the quota", async () => {
      const uid = "stale-min-runs-runner";
      await firestore.doc("config/leaderboard").set({ minRunsToQualify: 3 });
      await Promise.all([
        firestore.doc(`users/${uid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${uid}`).set({
          nickname: "Stale Min Runs",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        // Written by an earlier refresh while qualifyingRunCount was still 2.
        firestore.doc(`leaderboardCurrentViews/${uid}`).set({
          ownerUid: uid,
          periodType: "monthly",
          periodKey: "2026-07",
          status: "ineligible_min_runs",
          snapshotId: null,
          rankId: null,
          activeSnapshotId: null,
          activeRankProjectionId: null,
        }),
        // The owner's third qualifying run has since been recomputed in.
        firestore.doc(`leaderboardContributions/${uid}_monthly_2026-07`).set({
          ...contribution({ ownerUid: uid }),
          qualifyingRunCount: 3,
        }),
      ]);

      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "stale-min-runs-view-build",
      });

      const currentView = await firestore
        .doc(`leaderboardCurrentViews/${uid}`)
        .get();
      assert.notEqual(
        currentView.get("status"),
        "ineligible_min_runs",
        "the stale under-quota exclusion must not survive a run once the quota is met",
      );
      assert.equal(currentView.get("status"), "ranked");
      assert.equal(
        currentView.get("activeRankProjectionId"),
        `${uid}_monthly_2026-07`,
      );
      await firestore.doc("config/leaderboard").delete();
    });

    // Retention rule (retainedPeriodKeys): the refreshed month plus the two
    // months before it survive; every older monthly projection is deleted by
    // cleanupExpiredProjections after the refresh commits.
    it("deletes projections for periods outside the three-month retained window after a refresh", async () => {
      const staleSnapshotRef = firestore.doc(
        "leaderboardSnapshots/monthly_jurong-east_tier_01_2026-03",
      );
      const staleRankRef = firestore.doc(
        "leaderboardUserRanks/stale-runner_monthly_2026-03",
      );
      const staleLockRef = firestore.doc(
        "leaderboardAggregationLocks/monthly_2026-03",
      );
      const retainedSnapshotRef = firestore.doc(
        "leaderboardSnapshots/monthly_jurong-east_tier_01_2026-05",
      );
      const retainedRankRef = firestore.doc(
        "leaderboardUserRanks/retained-runner_monthly_2026-05",
      );
      await Promise.all([
        staleSnapshotRef.set({
          periodType: "monthly",
          periodKey: "2026-03",
          regionId: "jurong-east",
          divisionKey: "tier_01",
        }),
        staleRankRef.set({
          periodType: "monthly",
          periodKey: "2026-03",
          ownerUid: "stale-runner",
        }),
        staleLockRef.set({
          periodType: "monthly",
          periodKey: "2026-03",
          status: "completed",
        }),
        retainedSnapshotRef.set({
          periodType: "monthly",
          periodKey: "2026-05",
          regionId: "jurong-east",
          divisionKey: "tier_01",
        }),
        retainedRankRef.set({
          periodType: "monthly",
          periodKey: "2026-05",
          ownerUid: "retained-runner",
        }),
      ]);

      const completed = await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "cleanup-retention-build",
      });
      assert.equal(completed.status, "completed");

      // 2026-03 is outside {2026-07, 2026-06, 2026-05} and must be gone.
      assert.equal((await staleSnapshotRef.get()).exists, false);
      assert.equal((await staleRankRef.get()).exists, false);
      assert.equal((await staleLockRef.get()).exists, false);
      // 2026-05 is inside the retained window and must survive untouched.
      assert.equal((await retainedSnapshotRef.get()).exists, true);
      assert.equal((await retainedRankRef.get()).exists, true);
    });

    it("writes qualifyingRunCount as an absolute value, never an increment", async () => {
      const uid = "absolute-count-runner";
      const contributionRef = firestore.doc(
        `leaderboardContributions/${uid}_monthly_2026-07`,
      );

      // Seed a stored count of 3, as if a prior write already recomputed it.
      await firestore.runTransaction(async (transaction) => {
        writeLeaderboardContribution({
          transaction,
          firestore,
          uid,
          progressionEventId: "progression-absolute-count-1",
          completedAt: "2026-07-10T00:00:00.000Z",
          periodKey: "2026-07",
          scoreXp: 50,
          divisionKey: "tier_01",
          divisionLabel: "Iron League",
          levelLabel: "Level 1",
          profileData: {
            nickname: "Absolute Count",
            locationLabel: "Jurong East, Singapore",
          },
          existingContributionData: undefined,
          qualifyingRunCount: 3,
        });
      });
      const afterFirst = await contributionRef.get();
      assert.equal(afterFirst.get("qualifyingRunCount"), 3);

      // A later recompute of 7 must land as 7, not 3 + 7 = 10. This is the
      // exact regression `FieldValue.increment` would have reintroduced.
      await firestore.runTransaction(async (transaction) => {
        writeLeaderboardContribution({
          transaction,
          firestore,
          uid,
          progressionEventId: "progression-absolute-count-2",
          completedAt: "2026-07-11T00:00:00.000Z",
          periodKey: "2026-07",
          scoreXp: 50,
          divisionKey: "tier_01",
          divisionLabel: "Iron League",
          levelLabel: "Level 1",
          profileData: {
            nickname: "Absolute Count",
            locationLabel: "Jurong East, Singapore",
          },
          existingContributionData: afterFirst.data(),
          qualifyingRunCount: 7,
        });
      });
      const afterSecond = await contributionRef.get();
      assert.equal(afterSecond.get("qualifyingRunCount"), 7);

      // A `null` qualifyingRunCount (completeCoolDown's contract) must leave
      // the previously-recomputed value untouched.
      await firestore.runTransaction(async (transaction) => {
        writeLeaderboardContribution({
          transaction,
          firestore,
          uid,
          progressionEventId: "progression-absolute-count-3",
          completedAt: "2026-07-12T00:00:00.000Z",
          periodKey: "2026-07",
          scoreXp: 50,
          divisionKey: "tier_01",
          divisionLabel: "Iron League",
          levelLabel: "Level 1",
          profileData: {
            nickname: "Absolute Count",
            locationLabel: "Jurong East, Singapore",
          },
          existingContributionData: afterSecond.data(),
          qualifyingRunCount: null,
        });
      });
      const afterCoolDown = await contributionRef.get();
      assert.equal(afterCoolDown.get("qualifyingRunCount"), 7);
    });

    it("leaves qualifyingRunCount unset when a first write passes null", async () => {
      const uid = "null-first-write-runner";
      const contributionRef = firestore.doc(
        `leaderboardContributions/${uid}_monthly_2026-07`,
      );

      await firestore.runTransaction(async (transaction) => {
        writeLeaderboardContribution({
          transaction,
          firestore,
          uid,
          progressionEventId: "progression-null-first-write",
          completedAt: "2026-07-10T00:00:00.000Z",
          periodKey: "2026-07",
          scoreXp: 50,
          divisionKey: "tier_01",
          divisionLabel: "Iron League",
          levelLabel: "Level 1",
          profileData: {
            nickname: "Null First Write",
            locationLabel: "Jurong East, Singapore",
          },
          existingContributionData: undefined,
          qualifyingRunCount: null,
        });
      });
      const afterWrite = await contributionRef.get();
      assert.equal(afterWrite.get("qualifyingRunCount"), undefined);
    });

    it("resolves each contributor's avatarUrl onto their topEntries row and their currentEntry/nearbyEntries rows, with zero extra reads beyond the existing ownerFacts load", async () => {
      const withAvatarUid = "avatar-writer-with-avatar";
      const withoutAvatarUid = "avatar-writer-without-avatar";
      const avatarUrl = testAvatarUrl("0123456789abcdef0123456789abcdef");
      await Promise.all([
        firestore.doc(`users/${withAvatarUid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${withAvatarUid}`).set({
          nickname: "Has Avatar",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
          avatarUrl,
        }),
        firestore
          .doc(`leaderboardContributions/${withAvatarUid}_monthly_2026-07`)
          .set(contribution({ ownerUid: withAvatarUid, scoreXp: 200 })),
        firestore.doc(`users/${withoutAvatarUid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${withoutAvatarUid}`).set({
          nickname: "No Avatar",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore
          .doc(`leaderboardContributions/${withoutAvatarUid}_monthly_2026-07`)
          .set(contribution({ ownerUid: withoutAvatarUid, scoreXp: 100 })),
      ]);

      await refreshMonthlyLeaderboardSnapshots(
        firestore,
        "2026-07",
        { now: new Date("2026-07-10T00:00:00.000Z"), buildId: "avatar-resolve-build" },
        { bucket: AVATAR_TEST_BUCKET },
      );

      const snapshot = await firestore
        .doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07")
        .get();
      const topEntries = snapshot.get("topEntries") as readonly Record<string, unknown>[];
      // Rows carry the live profile nickname, not the alias stored on the
      // contribution — see the rename test below.
      const withAvatarEntry = topEntries.find((entryItem) => entryItem["publicAlias"] === "Has Avatar");
      const withoutAvatarEntry = topEntries.find((entryItem) => entryItem["publicAlias"] === "No Avatar");
      assert.equal(withAvatarEntry?.["avatarUrl"], avatarUrl);
      assert.equal(withoutAvatarEntry?.["avatarUrl"], "");

      const rank = await firestore
        .doc(`leaderboardUserRanks/${withAvatarUid}_monthly_2026-07`)
        .get();
      const currentEntry = rank.get("currentEntry") as Record<string, unknown>;
      assert.equal(currentEntry["avatarUrl"], avatarUrl);
      const nearbyEntries = rank.get("nearbyEntries") as readonly Record<string, unknown>[];
      const nearbySelf = nearbyEntries.find((entryItem) => entryItem["publicAlias"] === "Has Avatar");
      assert.equal(nearbySelf?.["avatarUrl"], avatarUrl);
    });

    // A contribution stores the alias captured by the run that wrote it, so a
    // runner who renames afterwards stayed on the board under the old name
    // until their next run. This asserts the refresh republishes the current
    // nickname over the stale stored one, on every projected row.
    it("republishes the live profile nickname over the alias frozen into the contribution", async () => {
      const renamedUid = "alias-writer-renamed";
      const namelessUid = "alias-writer-no-nickname";
      await Promise.all([
        firestore.doc(`users/${renamedUid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${renamedUid}`).set({
          nickname: "Jinseo_main",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore
          .doc(`leaderboardContributions/${renamedUid}_monthly_2026-07`)
          .set({
            ...contribution({ ownerUid: renamedUid, scoreXp: 200 }),
            publicAlias: "babo",
          }),
        firestore.doc(`users/${namelessUid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${namelessUid}`).set({
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore
          .doc(`leaderboardContributions/${namelessUid}_monthly_2026-07`)
          .set(contribution({ ownerUid: namelessUid, scoreXp: 100 })),
      ]);

      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "alias-refresh-build",
      });

      const snapshot = await firestore
        .doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07")
        .get();
      assert.deepEqual(
        (snapshot.get("topEntries") as readonly Record<string, unknown>[]).map(
          (entryItem) => entryItem["publicAlias"],
        ),
        ["Jinseo_main", `Runner ${namelessUid}`],
      );

      const rank = await firestore
        .doc(`leaderboardUserRanks/${renamedUid}_monthly_2026-07`)
        .get();
      assert.equal(
        (rank.get("currentEntry") as Record<string, unknown>)["publicAlias"],
        "Jinseo_main",
      );
      // The renamed runner also has to be renamed inside everyone else's view.
      const neighbourRank = await firestore
        .doc(`leaderboardUserRanks/${namelessUid}_monthly_2026-07`)
        .get();
      assert.deepEqual(
        (
          neighbourRank.get("nearbyEntries") as readonly Record<string, unknown>[]
        ).map((entryItem) => entryItem["publicAlias"]),
        ["Jinseo_main", `Runner ${namelessUid}`],
      );
    });

    // Same staleness class as the rename above: levelling up on a run in a
    // DIFFERENT region never rewrites this board's contribution, so its
    // levelLabel froze at the last run here. The percent is new entirely —
    // it drives the XP ring the client draws around each row's avatar, which
    // every leaderboard row previously rendered empty.
    it("republishes the live profile level and progress over the contribution's frozen label", async () => {
      const levelledUid = "level-writer-levelled";
      const levellessUid = "level-writer-no-level";
      await Promise.all([
        firestore.doc(`users/${levelledUid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${levelledUid}`).set({
          nickname: "Levelled",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 9,
          levelLabel: "Level 9",
          levelProgressPercent: 64,
        }),
        firestore
          .doc(`leaderboardContributions/${levelledUid}_monthly_2026-07`)
          .set({
            ...contribution({ ownerUid: levelledUid, scoreXp: 200 }),
            levelLabel: "Level 8",
          }),
        firestore.doc(`users/${levellessUid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${levellessUid}`).set({
          nickname: "No Level",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
        }),
        firestore
          .doc(`leaderboardContributions/${levellessUid}_monthly_2026-07`)
          .set(contribution({ ownerUid: levellessUid, scoreXp: 100 })),
      ]);

      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-07", {
        now: new Date("2026-07-10T00:00:00.000Z"),
        buildId: "level-refresh-build",
      });

      const snapshot = await firestore
        .doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07")
        .get();
      const topEntries = snapshot.get("topEntries") as readonly Record<string, unknown>[];
      const levelledEntry = topEntries.find((entryItem) => entryItem["publicAlias"] === "Levelled");
      const levellessEntry = topEntries.find((entryItem) => entryItem["publicAlias"] === "No Level");
      assert.equal(levelledEntry?.["levelLabel"], "Level 9");
      assert.equal(levelledEntry?.["levelProgressPercent"], 64);
      // A profile with a level but no stored percent still publishes a row;
      // its ring is simply empty.
      assert.equal(levellessEntry?.["levelLabel"], "Lv.1");
      assert.equal(levellessEntry?.["levelProgressPercent"], 0);

      const rank = await firestore
        .doc(`leaderboardUserRanks/${levelledUid}_monthly_2026-07`)
        .get();
      const currentEntry = rank.get("currentEntry") as Record<string, unknown>;
      assert.equal(currentEntry["levelLabel"], "Level 9");
      assert.equal(currentEntry["levelProgressPercent"], 64);
      // And inside every neighbour's view of that runner, not only their own.
      const neighbourRank = await firestore
        .doc(`leaderboardUserRanks/${levellessUid}_monthly_2026-07`)
        .get();
      const nearbySelf = (
        neighbourRank.get("nearbyEntries") as readonly Record<string, unknown>[]
      ).find((entryItem) => entryItem["publicAlias"] === "Levelled");
      assert.equal(nearbySelf?.["levelProgressPercent"], 64);
    });

    it("resolves a foreign-bucket avatarUrl to empty string, proving the sanitiser is live on the leaderboard read path and not vacuous", async () => {
      const uid = "avatar-writer-foreign-bucket";
      const foreignUrl = buildAvatarDownloadUrl({
        bucket: "some-other-bucket.appspot.com",
        objectPath: "avatars/fedcba9876543210fedcba9876543210.png",
        token: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      });
      await Promise.all([
        firestore.doc(`users/${uid}`).set({ subscriptionStatus: "basic" }),
        firestore.doc(`userProfiles/${uid}`).set({
          nickname: "Foreign Bucket",
          locationLabel: "Jurong East, Singapore",
          divisionKey: "tier_01",
          level: 1,
          avatarUrl: foreignUrl,
        }),
        firestore
          .doc(`leaderboardContributions/${uid}_monthly_2026-07`)
          .set(contribution({ ownerUid: uid })),
      ]);

      await refreshMonthlyLeaderboardSnapshots(
        firestore,
        "2026-07",
        { now: new Date("2026-07-10T00:00:00.000Z"), buildId: "avatar-foreign-bucket-build" },
        { bucket: AVATAR_TEST_BUCKET },
      );

      const rank = await firestore
        .doc(`leaderboardUserRanks/${uid}_monthly_2026-07`)
        .get();
      const currentEntry = rank.get("currentEntry") as Record<string, unknown>;
      assert.equal(currentEntry["avatarUrl"], "");
    });

    // The entire opaque-object-path avatar design exists so that a
    // world-readable row (`leaderboardSnapshots`: `allow read: if
    // isSignedIn()`) never leaks WHO a ranked runner is via their avatar URL.
    // This asserts that property directly against every row this run wrote,
    // rather than trusting the design intent alone.
    it("never writes an avatarUrl containing any contributor's uid as a substring", async () => {
      const uids = [
        "avatar-security-alpha-uid",
        "avatar-security-bravo-uid",
        "avatar-security-charlie-uid",
      ];
      // Distinct, valid 32-character-lowercase-hex object ids — never derived
      // from the uid strings above, matching real ids minted by
      // newAvatarObjectPath (a server-generated random id).
      const objectIds = [
        "11111111111111111111111111111111".slice(0, 32),
        "22222222222222222222222222222222".slice(0, 32),
        "33333333333333333333333333333333".slice(0, 32),
      ];
      await Promise.all(
        uids.flatMap((uid, index) => [
          firestore.doc(`users/${uid}`).set({ subscriptionStatus: "basic" }),
          firestore.doc(`userProfiles/${uid}`).set({
            nickname: `Security ${index}`,
            locationLabel: "Jurong East, Singapore",
            divisionKey: "tier_01",
            level: 1,
            avatarUrl: testAvatarUrl(objectIds[index] ?? "00000000000000000000000000000000".slice(0, 32)),
          }),
          firestore
            .doc(`leaderboardContributions/${uid}_monthly_2026-07`)
            .set(contribution({ ownerUid: uid, scoreXp: 300 - index })),
        ]),
      );

      await refreshMonthlyLeaderboardSnapshots(
        firestore,
        "2026-07",
        { now: new Date("2026-07-10T00:00:00.000Z"), buildId: "avatar-security-build" },
        { bucket: AVATAR_TEST_BUCKET },
      );

      const snapshot = await firestore
        .doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07")
        .get();
      const topEntries = snapshot.get("topEntries") as readonly Record<string, unknown>[];
      const rankSnapshots = await Promise.all(
        uids.map((uid) =>
          firestore.doc(`leaderboardUserRanks/${uid}_monthly_2026-07`).get(),
        ),
      );
      const avatarUrls: string[] = [];
      for (const entryItem of topEntries) {
        avatarUrls.push(String(entryItem["avatarUrl"] ?? ""));
      }
      for (const rankSnapshot of rankSnapshots) {
        const currentEntry = rankSnapshot.get("currentEntry") as Record<string, unknown> | undefined;
        if (currentEntry !== undefined) {
          avatarUrls.push(String(currentEntry["avatarUrl"] ?? ""));
        }
        const nearbyEntries = (rankSnapshot.get("nearbyEntries") as readonly Record<string, unknown>[] | undefined) ?? [];
        for (const entryItem of nearbyEntries) {
          avatarUrls.push(String(entryItem["avatarUrl"] ?? ""));
        }
      }
      assert.ok(avatarUrls.length > 0, "expected at least one written avatarUrl to inspect");
      for (const url of avatarUrls) {
        for (const uid of uids) {
          assert.equal(
            url.includes(uid),
            false,
            `avatarUrl ${url} must never contain contributor uid ${uid}`,
          );
        }
      }
    });
  },
);

function contribution(input: {
  readonly ownerUid: string;
  readonly scoreXp?: number;
  readonly regionId?: string;
  readonly regionLabel?: string;
  readonly planningAreaName?: string;
  readonly planningAreaCode?: string;
  readonly planningRegionCode?: string;
  readonly divisionKey?: string;
  readonly divisionLabel?: string;
  readonly levelLabel?: string;
}): Record<string, unknown> {
  return {
    schemaVersion: 2,
    ownerUid: input.ownerUid,
    publicAlias: `Runner ${input.ownerUid}`,
    regionId: input.regionId ?? "jurong-east",
    regionLabel: input.regionLabel ?? "Jurong East",
    planningAreaName: input.planningAreaName ?? "JURONG EAST",
    planningAreaCode: input.planningAreaCode ?? "JE",
    planningRegionCode: input.planningRegionCode ?? "WR",
    divisionKey: input.divisionKey ?? "tier_01",
    divisionLabel: input.divisionLabel ?? "Iron League",
    levelLabel: input.levelLabel ?? "Level 1",
    periodType: "monthly",
    periodKey: "2026-07",
    timezone: "Asia/Singapore",
    scoreXp: input.scoreXp ?? 75,
    eligible: true,
    eligibilityReason: "eligible_basic_awarded_xp",
    lastProgressionAt: "2026-07-10T00:00:00.000Z",
    sourceProgressionEventIds: [`event-${input.ownerUid}`],
  };
}

async function clearCollections(
  firestore: Firestore,
  collectionNames: readonly string[],
): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    if (snapshot.empty) {
      continue;
    }
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}
