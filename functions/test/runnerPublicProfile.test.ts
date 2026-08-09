import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getRunnerPublicProfile, type BlockEdges, type RunnerPublicProfilePorts } from "../src/profile/publicProfile/core.js";
import { canonicalizeNickname, nicknameIndexKey } from "../src/friends/nickname.js";
import { buildAvatarDownloadUrl, type AvatarUrlContext } from "../src/profile/avatar/avatarPaths.js";

const viewer = "viewer-a";
const runner = "runner-a";
const snapshotId = "monthly_jurong-east_tier_03_2026-07";
const buildId = "build-2026-07-26T09";

const BUCKET = "runiac-fypp.appspot.com";
const AVATAR_CONTEXT: AvatarUrlContext = { bucket: BUCKET };
const TOKEN = "3fa85f64-5717-4562-b3fc-2c963f66afa6";
const VALID_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: BUCKET,
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: TOKEN,
});
const FOREIGN_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: "some-other-bucket.appspot.com",
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: TOKEN,
});

function rankKey(snapshot: string, rankLabel: string, build: string): string {
  return `${snapshot}::${rankLabel}::${build}`;
}

function entry(rankLabel = "#3", build = buildId): Record<string, string> {
  return { snapshotId, rankLabel, buildId: build };
}

/**
 * The exact `socialProfile()`-passing shape: nickname, its canonical form,
 * and the canonical's index key all agreeing, plus an active discovery
 * status. Anything less and `socialProfile()` returns `undefined`.
 */
function discoverableProfileFields(nickname: string): Record<string, string> {
  const canonical = canonicalizeNickname(nickname);
  return { nickname, nicknameCanonical: canonical, nicknameIndexKey: nicknameIndexKey(canonical), socialDiscoveryStatus: "active" };
}

describe("Runner public profile core", () => {
  it("projects the backend-owned profile fields for a signed-in viewer", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, {
      displayName: "Jinseo",
      nickname: "Jinseo_main",
      avatarInitials: "JI",
      locationLabel: "Jurong East, Singapore",
      levelLabel: "Level 8",
      level: 8,
      levelProgressPercent: 97.5,
      totalXp: 780,
      nextLevelXp: 800,
      xpToNextLevel: 20,
      divisionKey: "tier_03",
      divisionLabel: "Silver League",
      longestStreakLabel: "4 days",
      totalDistanceLabel: "69.8 km",
    });
    ports.accounts.set(runner, { subscriptionStatus: "premium" });
    ports.badges.set(runner, ["250K"]);

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

    assert.deepEqual(profile, {
      displayName: "Jinseo_main",
      avatarInitials: "JI",
      avatarUrl: "",
      regionLabel: "Jurong East, Singapore",
      levelLabel: "Level 8",
      level: 8,
      levelProgressPercent: 97.5,
      totalXp: 780,
      nextLevelXp: 800,
      xpToNextLevel: 20,
      isMaxLevel: false,
      divisionKey: "tier_03",
      divisionLabel: "Silver League",
      longestStreakLabel: "4 days",
      totalDistanceLabel: "69.8 km",
      subscriptionStatusLabel: "Premium",
      ownedBadgeTierIds: ["250K"],
      statsHidden: false,
    });
  });

  it("withholds the running record of a runner who keeps it private", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, {
      displayName: "Jinseo",
      nickname: "Jinseo_main",
      avatarInitials: "JI",
      locationLabel: "Jurong East, Singapore",
      levelLabel: "Level 8",
      level: 8,
      levelProgressPercent: 97.5,
      totalXp: 780,
      nextLevelXp: 800,
      xpToNextLevel: 20,
      divisionKey: "tier_03",
      divisionLabel: "Silver League",
      longestStreakLabel: "4 days",
      totalDistanceLabel: "69.8 km",
      publicStatsHidden: true,
    });
    ports.accounts.set(runner, { subscriptionStatus: "premium" });
    ports.badges.set(runner, ["250K"]);

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

    // Identity survives: every one of these already appears on the public
    // board the viewer tapped, so hiding them here would suppress nothing.
    assert.equal(profile.displayName, "Jinseo_main");
    assert.equal(profile.regionLabel, "Jurong East, Singapore");
    assert.equal(profile.levelLabel, "Level 8");
    assert.equal(profile.level, 8);
    assert.equal(profile.divisionLabel, "Silver League");
    assert.equal(profile.subscriptionStatusLabel, "Premium");

    // The record does not. These are asserted on the returned object rather
    // than on what a screen draws, because the screen's blur is cosmetic — the
    // guarantee is that the values never reach the viewer's device at all.
    assert.equal(profile.statsHidden, true);
    assert.equal(profile.levelProgressPercent, 0);
    assert.equal(profile.totalXp, null);
    assert.equal(profile.nextLevelXp, null);
    assert.equal(profile.xpToNextLevel, null);
    assert.equal(profile.isMaxLevel, false);
    assert.equal(profile.longestStreakLabel, "");
    assert.equal(profile.totalDistanceLabel, "");
    assert.deepEqual(profile.ownedBadgeTierIds, []);

    // Not read-then-discard: a hidden profile never pays for the badge read.
    assert.deepEqual(ports.badgeReadCalls, []);
  });

  it("does not report max level for a hidden record", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    // The explicit null is the backend's "max level reached" assertion, which
    // is itself a fact about how far this runner has come.
    ports.profiles.set(runner, { displayName: "Jinseo", xpToNextLevel: null, publicStatsHidden: true });

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

    assert.equal(profile.isMaxLevel, false);
    assert.equal(profile.statsHidden, true);
  });

  it("shows a runner their own record even when they keep it private", async () => {
    const ports = fakePorts();
    ports.profiles.set(runner, {
      displayName: "Jinseo",
      longestStreakLabel: "4 days",
      totalDistanceLabel: "69.8 km",
      totalXp: 780,
      publicStatsHidden: true,
    });
    ports.badges.set(runner, ["250K"]);

    const profile = await getRunnerPublicProfile({ auth: { uid: runner }, data: { uid: runner } }, ports);

    assert.equal(profile.statsHidden, false);
    assert.equal(profile.longestStreakLabel, "4 days");
    assert.equal(profile.totalDistanceLabel, "69.8 km");
    assert.equal(profile.totalXp, 780);
    assert.deepEqual(profile.ownedBadgeTierIds, ["250K"]);
  });

  it("treats a non-boolean privacy field as visible", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    for (const stored of ["true", 1, {}, [], null]) {
      ports.profiles.set(runner, { displayName: "Jinseo", totalDistanceLabel: "69.8 km", publicStatsHidden: stored });

      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

      // Only an explicit `true` hides a record. Anything else is a malformed
      // write, and a malformed write must not silently blank a profile.
      assert.equal(profile.statsHidden, false, `${JSON.stringify(stored)} must read as visible`);
      assert.equal(profile.totalDistanceLabel, "69.8 km");
    }
  });

  it("never leaks the private half of the profile document", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, {
      displayName: "Jinseo",
      avatarInitials: "JI",
      locationLabel: "Jurong East, Singapore",
      fullName: "Jinseo Lee",
      dateOfBirth: "2000-01-01",
      ageYears: 26,
      weightKg: 68.5,
      email: "runner@example.com",
    });

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

    for (const privateKey of ["fullName", "dateOfBirth", "ageYears", "weightKg", "email"]) {
      assert.equal(privateKey in profile, false, `${privateKey} must not be projected`);
    }
    assert.equal(profile.displayName, "Jinseo");
  });

  it("falls back to Basic for a missing or unrecognised subscription status", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East, Singapore" });
    ports.accounts.set(runner, { subscriptionStatus: "PLATINUM" });

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

    assert.equal(profile.subscriptionStatusLabel, "Basic");
  });

  it("reports max level only when the backend published an explicit null", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East", xpToNextLevel: null });
    const atMaxLevel = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);
    assert.equal(atMaxLevel.isMaxLevel, true);
    assert.equal(atMaxLevel.xpToNextLevel, null);

    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    const unpublished = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);
    assert.equal(unpublished.isMaxLevel, false);
  });

  it("clamps a stored progress percent into 0..100", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East", levelProgressPercent: 140 });
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);
    assert.equal(profile.levelProgressPercent, 100);
  });

  it("serves the caller their own entry without reading block edges", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#4", buildId), viewer);
    ports.profiles.set(viewer, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#4") }, ports);
    assert.equal(profile.displayName, "Jinseo");
    assert.equal(ports.blockEdgeCalls.length, 0);
  });

  it("never echoes the resolved uid back to the caller", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports);

    // Echoing it would let a caller walk every rank of every public snapshot
    // and rebuild the uid directory the snapshot deliberately omits.
    assert.equal("uid" in profile, false);
    assert.equal(JSON.stringify(profile).includes(runner), false);
  });

  it("refuses to resolve an entry from a superseded board build", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });

    // The hourly refresh reuses the monthly snapshot id and reassigns rank
    // labels, so a stale row must not resolve to whoever holds #3 now.
    await assertHttpsError(
      () => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3", "build-older") }, ports),
      "not-found",
    );
  });

  it("hides the profile when the viewer blocked the runner", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    ports.blockedByCaller.add(runner);
    await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports), "permission-denied");
  });

  it("hides the profile when the runner blocked the viewer", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    ports.blockedCaller.add(runner);
    await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports), "permission-denied");
  });

  it("hides the profile of a suspended runner", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    ports.accounts.set(runner, { accountStatus: "suspended" });
    await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports), "permission-denied");
  });

  it("rejects an unauthenticated caller", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    await assertHttpsError(() => getRunnerPublicProfile({ data: entry() }, ports), "unauthenticated");
  });

  it("rejects a malformed request payload", async () => {
    const ports = fakePorts();
    for (const data of [
      undefined,
      {},
      { snapshotId, rankLabel: "#3" },
      { snapshotId, rankLabel: "#3", buildId: "", },
      { snapshotId, rankLabel: "#3", buildId, extra: 1 },
      { snapshotId: "leaderboardUserRanks/x", rankLabel: "#3", buildId },
      { snapshotId: "../other", rankLabel: "#3", buildId },
      { snapshotId, rankLabel: 7, buildId },
      // The uid-addressed form is validated too: empty, path-shaped,
      // traversal-shaped, non-string, over-length, and mixed with the
      // leaderboard-entry keys must all fail closed.
      { uid: "" },
      { uid: "a/b" },
      { uid: "../x" },
      { uid: 7 },
      { uid: "a".repeat(129) },
      { uid: runner, snapshotId, rankLabel: "#3", buildId },
    ]) {
      await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data }, ports), "invalid-argument");
    }
  });

  it("reports a runner with no profile document as not found", async () => {
    const ports = fakePorts();
    await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports), "not-found");
  });

  it("resolves a leaderboard entry to its owner without the viewer ever holding a uid", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", nickname: "Jinseo_main", avatarInitials: "JI", locationLabel: "Jurong East, Singapore", level: 8 });
    ports.badges.set(runner, ["10K"]);

    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports);

    assert.equal(profile.displayName, "Jinseo_main");
    assert.deepEqual(profile.ownedBadgeTierIds, ["10K"]);
  });

  it("applies the block rule to a leaderboard entry too", async () => {
    const ports = fakePorts();
    ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
    ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
    ports.blockedCaller.add(runner);
    await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports), "permission-denied");
  });

  it("hides an entry whose rank resolves to no owner", async () => {
    const ports = fakePorts();
    await assertHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#9") }, ports), "not-found");
  });

  describe("uid-addressed runner target", () => {
    it("allows the caller to address their own uid, reading no gate ports at all", async () => {
      const ports = fakePorts();
      ports.profiles.set(viewer, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });

      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: viewer } }, ports);

      assert.equal(profile.displayName, "Jinseo");
      assert.equal(ports.blockEdgeCalls.length, 0);
      assert.equal(ports.socialEdgeCalls.length, 0);
      assert.equal(ports.coMemberCalls.length, 0);
    });

    it("allows a discoverable target without reading the social-edge or co-member ports", async () => {
      const ports = fakePorts();
      ports.profiles.set(runner, {
        displayName: "Jinseo",
        avatarInitials: "JI",
        locationLabel: "Jurong East",
        ...discoverableProfileFields("Jinseo_main"),
      });

      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: runner } }, ports);

      assert.equal(profile.displayName, "Jinseo_main");
      // `socialProfile()` already answered the gate from the profile document
      // already in hand, so the two remaining, extra-read checks must never fire.
      assert.equal(ports.socialEdgeCalls.length, 0);
      assert.equal(ports.coMemberCalls.length, 0);
    });

    it("allows a target the caller already has an accepted friend edge with", async () => {
      const friendUid = "friend-runner";
      const ports = fakePorts();
      ports.profiles.set(friendUid, { displayName: "Friend", avatarInitials: "FR", locationLabel: "Jurong East" });
      ports.socialEdges.add(friendUid);

      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: friendUid } }, ports);

      assert.equal(profile.displayName, "Friend");
      // The friend edge already answered the gate, so co-membership is never checked.
      assert.equal(ports.coMemberCalls.length, 0);
    });

    it("allows a target the caller has only a pending friend request with", async () => {
      const requestedUid = "requested-runner";
      const ports = fakePorts();
      ports.profiles.set(requestedUid, { displayName: "Requested", avatarInitials: "RQ", locationLabel: "Jurong East" });
      // `readSocialEdge` is true for a friend doc OR a friendRequest doc; the
      // fake collapses both into one set because the gate only cares about
      // the boolean, exactly like the real port does.
      ports.socialEdges.add(requestedUid);

      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: requestedUid } }, ports);

      assert.equal(profile.displayName, "Requested");
      assert.equal(ports.coMemberCalls.length, 0);
    });

    it("allows a target the caller shares a challenge roster with", async () => {
      const ports = fakePorts();
      ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
      ports.coMembers.add(runner);

      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: runner } }, ports);

      assert.equal(profile.displayName, "Jinseo");
      // Co-membership is the last and most expensive check, so it is only
      // reached once the cheaper self/discoverable/social-edge checks failed.
      assert.equal(ports.socialEdgeCalls.length, 1);
    });

    it("denies a stranger, a block either way, a suspended account, and a missing profile with the identical not-found error", async () => {
      const stranger = "stranger-runner";

      const strangerPorts = fakePorts();
      strangerPorts.profiles.set(stranger, { displayName: "Stranger", avatarInitials: "ST", locationLabel: "Bedok" });
      const strangerError = await captureHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: stranger } }, strangerPorts));

      const callerBlockedPorts = fakePorts();
      callerBlockedPorts.profiles.set(stranger, { displayName: "Stranger", avatarInitials: "ST", locationLabel: "Bedok" });
      callerBlockedPorts.blockedByCaller.add(stranger);
      const callerBlockedError = await captureHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: stranger } }, callerBlockedPorts));

      const targetBlockedPorts = fakePorts();
      targetBlockedPorts.profiles.set(stranger, { displayName: "Stranger", avatarInitials: "ST", locationLabel: "Bedok" });
      targetBlockedPorts.blockedCaller.add(stranger);
      const targetBlockedError = await captureHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: stranger } }, targetBlockedPorts));

      const suspendedPorts = fakePorts();
      suspendedPorts.profiles.set(stranger, { displayName: "Stranger", avatarInitials: "ST", locationLabel: "Bedok" });
      suspendedPorts.accounts.set(stranger, { accountStatus: "suspended" });
      const suspendedError = await captureHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: stranger } }, suspendedPorts));

      const missingProfilePorts = fakePorts();
      const missingProfileError = await captureHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: stranger } }, missingProfilePorts));

      for (const error of [strangerError, callerBlockedError, targetBlockedError, suspendedError, missingProfileError]) {
        assert.equal(error.code, "not-found");
        assert.equal(error.message, strangerError.message);
      }
      for (const ports of [strangerPorts, callerBlockedPorts, targetBlockedPorts, suspendedPorts, missingProfilePorts]) {
        // A denial must never pay for the badge read.
        assert.equal(ports.badgeReadCalls.length, 0);
        // ...and it must pay for exactly the same gate reads as every other
        // denial. An identical error body is not enough on its own: a caller
        // who can time the call would otherwise still tell "no such runner"
        // from "not allowed to see this runner" by how much work it did.
        assert.equal(ports.socialEdgeCalls.length, 1);
        assert.equal(ports.coMemberCalls.length, 1);
      }
    });

    it("keeps a denial's cost fixed even when the runner is a blocked friend", async () => {
      const blockedFriend = "blocked-friend";
      const ports = fakePorts();
      ports.profiles.set(blockedFriend, { displayName: "Blocked", avatarInitials: "BL", locationLabel: "Bedok" });
      ports.socialEdges.add(blockedFriend);
      ports.blockedCaller.add(blockedFriend);

      const error = await captureHttpsError(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: blockedFriend } }, ports));

      assert.equal(error.code, "not-found");
      // The social edge answers true here, so a short-circuiting gate would
      // have skipped the roster read and made this denial one read cheaper
      // than a stranger's.
      assert.equal(ports.socialEdgeCalls.length, 1);
      assert.equal(ports.coMemberCalls.length, 1);
      assert.equal(ports.badgeReadCalls.length, 0);
    });
  });

  describe("avatarUrl", () => {
    it("surfaces a valid stored avatarUrl", async () => {
      const ports = fakePorts();
      ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
      ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East", avatarUrl: VALID_AVATAR_URL });
      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports, AVATAR_CONTEXT);
      assert.equal(profile.avatarUrl, VALID_AVATAR_URL);
    });

    it("resolves a foreign-bucket avatarUrl to empty rather than relaying it", async () => {
      const ports = fakePorts();
      ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
      ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East", avatarUrl: FOREIGN_AVATAR_URL });
      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports, AVATAR_CONTEXT);
      assert.equal(profile.avatarUrl, "");
    });

    it("resolves a malformed avatarUrl string to empty", async () => {
      const ports = fakePorts();
      ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
      ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East", avatarUrl: "not a url at all" });
      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports, AVATAR_CONTEXT);
      assert.equal(profile.avatarUrl, "");
    });

    it("resolves a profile with no avatar fields to empty, never undefined", async () => {
      const ports = fakePorts();
      ports.rankOwners.set(rankKey(snapshotId, "#3", buildId), runner);
      ports.profiles.set(runner, { displayName: "Jinseo", avatarInitials: "JI", locationLabel: "Jurong East" });
      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry() }, ports, AVATAR_CONTEXT);
      assert.equal(profile.avatarUrl, "");
      assert.equal("avatarUrl" in profile, true);
    });
  });
});

async function assertHttpsError(run: () => Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(run, (error: unknown) => typeof error === "object" && error !== null && "code" in error && error["code"] === code);
}

/** Captures an expected `HttpsError`'s code and message so callers can compare them across scenarios. */
async function captureHttpsError(run: () => Promise<unknown>): Promise<{ readonly code: unknown; readonly message: unknown }> {
  try {
    await run();
  } catch (error: unknown) {
    if (typeof error === "object" && error !== null && "code" in error && "message" in error) {
      return { code: (error as Readonly<Record<string, unknown>>)["code"], message: (error as Readonly<Record<string, unknown>>)["message"] };
    }
    throw error;
  }
  throw new Error("expected the callable to reject");
}

type FakePorts = RunnerPublicProfilePorts & {
  /** snapshotId + rankLabel + buildId -> ownerUid, i.e. the leaderboardUserRanks projection. */
  readonly rankOwners: Map<string, string>;
  readonly profiles: Map<string, Record<string, unknown>>;
  readonly accounts: Map<string, Record<string, unknown>>;
  readonly badges: Map<string, readonly string[]>;
  readonly blockedByCaller: Set<string>;
  readonly blockedCaller: Set<string>;
  readonly blockEdgeCalls: string[];
  /** targetUids for which a friend or friendRequest edge exists from the caller. */
  readonly socialEdges: Set<string>;
  /** targetUids the caller shares a challenge roster with. */
  readonly coMembers: Set<string>;
  readonly socialEdgeCalls: string[];
  readonly coMemberCalls: string[];
  readonly badgeReadCalls: string[];
};

function fakePorts(): FakePorts {
  const rankOwners = new Map<string, string>();
  const profiles = new Map<string, Record<string, unknown>>();
  const accounts = new Map<string, Record<string, unknown>>();
  const badges = new Map<string, readonly string[]>();
  const blockedByCaller = new Set<string>();
  const blockedCaller = new Set<string>();
  const blockEdgeCalls: string[] = [];
  const socialEdges = new Set<string>();
  const coMembers = new Set<string>();
  const socialEdgeCalls: string[] = [];
  const coMemberCalls: string[] = [];
  const badgeReadCalls: string[] = [];
  return {
    rankOwners,
    profiles,
    accounts,
    badges,
    blockedByCaller,
    blockedCaller,
    blockEdgeCalls,
    socialEdges,
    coMembers,
    socialEdgeCalls,
    coMemberCalls,
    badgeReadCalls,
    async readBlockEdges(_callerUid: string, targetUid: string): Promise<BlockEdges> {
      blockEdgeCalls.push(targetUid);
      return { callerBlockedTarget: blockedByCaller.has(targetUid), targetBlockedCaller: blockedCaller.has(targetUid) };
    },
    async readProfile(uid: string) {
      return profiles.get(uid);
    },
    async readAccount(uid: string) {
      return accounts.get(uid);
    },
    async readOwnedBadgeTierIds(uid: string) {
      badgeReadCalls.push(uid);
      return badges.get(uid) ?? [];
    },
    async resolveLeaderboardEntryOwner(snapshot: string, rankLabel: string, build: string) {
      return rankOwners.get(rankKey(snapshot, rankLabel, build));
    },
    async readSocialEdge(_callerUid: string, targetUid: string) {
      socialEdgeCalls.push(targetUid);
      return socialEdges.has(targetUid);
    },
    async isChallengeCoMember(_callerUid: string, targetUid: string) {
      coMemberCalls.push(targetUid);
      return coMembers.has(targetUid);
    },
  };
}
