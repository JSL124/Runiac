import { HttpsError } from "firebase-functions/v2/https";
import { isSuspendedAccount } from "../../security/accountStatus.js";
import { socialProfile } from "../../friends/friendsProfiles.js";
import { resolveProfileIdentityDisplay } from "../profileIdentityDisplay.js";
import type { AvatarUrlContext } from "../avatar/avatarPaths.js";
import { NULL_AVATAR_URL_CONTEXT } from "../avatar/avatarUrlContextDefaults.js";

/**
 * The public running-achievement projection of one runner, as shown on the
 * runner profile screen a viewer opens from the leaderboard.
 *
 * Every field here is a value a Cloud Function already computed and wrote to
 * `userProfiles/{uid}` (or a badge document a settled challenge wrote). This
 * projection only relays them: it must never derive a level from XP, a rank
 * from a score, a streak from run dates, or badge ownership from anything
 * other than the durable badge documents.
 *
 * Deliberately excluded — these are the private half of a profile and must
 * not leak through this callable: email, full name, date of birth, age,
 * weight, onboarding answers, plan setup, activity history, and every route
 * or GPS value.
 *
 * A runner may additionally hide their own running record from other viewers
 * (`userProfiles/{uid}.publicStatsHidden`). That preference is honoured HERE,
 * by withholding the values, not by the client declining to draw them: the
 * hidden fields come back at their empty values and `statsHidden` says so.
 * A viewer who reads the raw response learns exactly what the screen shows.
 */
export type RunnerPublicProfile = {
  readonly displayName: string;
  readonly avatarInitials: string;
  // Relayed exactly like every other field here: a value a Cloud Function
  // already wrote to `userProfiles/{uid}` (via setProfileAvatar), passed
  // through resolveProfileAvatarUrl so a foreign, malformed, or missing
  // stored value always serves as "" rather than being relayed as-is.
  readonly avatarUrl: string;
  readonly regionLabel: string;
  readonly levelLabel: string;
  readonly level: number;
  readonly levelProgressPercent: number;
  readonly totalXp: number | null;
  readonly nextLevelXp: number | null;
  readonly xpToNextLevel: number | null;
  readonly isMaxLevel: boolean;
  readonly divisionKey: string;
  readonly divisionLabel: string;
  readonly longestStreakLabel: string;
  readonly totalDistanceLabel: string;
  readonly subscriptionStatusLabel: string;
  readonly ownedBadgeTierIds: readonly string[];
  /**
   * True when this runner keeps their running record private and the viewer is
   * someone else. The record fields above are then at their empty values —
   * this flag exists so the viewer's screen can say "kept private" instead of
   * rendering a runner with no runs.
   */
  readonly statsHidden: boolean;
};

export type RunnerPublicProfileRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

export type BlockEdges = { readonly callerBlockedTarget: boolean; readonly targetBlockedCaller: boolean };

export interface RunnerPublicProfilePorts {
  /**
   * Block edges in both directions. A block either way hides the profile, the
   * same symmetry the Feed relationship check applies.
   */
  readBlockEdges(callerUid: string, targetUid: string): Promise<BlockEdges>;
  readProfile(uid: string): Promise<Readonly<Record<string, unknown>> | undefined>;
  readAccount(uid: string): Promise<Readonly<Record<string, unknown>> | undefined>;
  /** Document ids of `users/{uid}/challengeBadges`, i.e. the earned tier ids. */
  readOwnedBadgeTierIds(uid: string): Promise<readonly string[]>;
  /**
   * The uid behind one leaderboard entry, addressed the only way a viewer can
   * address it: by the snapshot it appears in, its rank within that snapshot,
   * and the aggregation build that produced both. `undefined` when no single
   * rank projection matches all three.
   *
   * This exists because `leaderboardSnapshots` is readable by every signed-in
   * user and therefore carries NO uid — publishing one there would hand out a
   * uid directory. The reverse mapping stays server-side, in the
   * backend-written `leaderboardUserRanks` projection, and the uid never
   * travels back to the caller either.
   *
   * [buildId] is what makes the entry immutable. `refreshLeaderboardSnapshots`
   * reuses one monthly `snapshotId` and reassigns rank labels on every run, so
   * a rank alone would resolve to whoever holds that position NOW — not the
   * runner the viewer tapped. The writer stamps the same build id on the
   * snapshot the viewer read and on every rank projection from that run, so
   * requiring them to agree pins the lookup to the board that was on screen.
   */
  resolveLeaderboardEntryOwner(snapshotId: string, rankLabel: string, buildId: string): Promise<string | undefined>;
  /**
   * True when caller and target already have a social edge, in either
   * direction: an accepted friendship (`users/{caller}/friends/{target}`) or
   * a friend request the caller sent (`users/{caller}/friendRequests/{target}`).
   * Deliberately narrower than `friendLevels`' `hasSocialEdge`, which also ORs
   * in `blockedUsers` — folding that in here would let "I blocked them" grant
   * a view instead of denying one.
   */
  readSocialEdge(callerUid: string, targetUid: string): Promise<boolean>;
  /**
   * True when caller and target are both on the roster of the challenge the
   * caller currently holds a lobby slot in. Reads the caller's
   * `challengeSlots` document for the `challengeId` it points at, then checks
   * `rosterUids` on that `challengeInstances` document.
   */
  isChallengeCoMember(callerUid: string, targetUid: string): Promise<boolean>;
}

const UNAVAILABLE_MESSAGE = "This runner profile is not available.";

export async function getRunnerPublicProfile(
  request: RunnerPublicProfileRequest,
  ports: RunnerPublicProfilePorts,
  // Injected by the callable layer (see profile/avatar/context.ts) rather than
  // read from firebase-admin here — this file, like every other core.ts, stays
  // free of firebase-admin imports and process.env reads. Defaults to a
  // context that can never match a real avatar URL, so a caller that omits it
  // still fails closed to avatarUrl: "".
  avatarContext: AvatarUrlContext = NULL_AVATAR_URL_CONTEXT,
): Promise<RunnerPublicProfile> {
  const callerUid = request.auth?.uid;
  if (callerUid === undefined || callerUid.length === 0) throw new HttpsError("unauthenticated", "Authentication is required.");
  const target = parseTarget(request.data);
  if (target === undefined) throw new HttpsError("invalid-argument", "Invalid runner profile request.");

  const targetUid =
    target.kind === "leaderboardEntry"
      ? await ports.resolveLeaderboardEntryOwner(target.snapshotId, target.rankLabel, target.buildId)
      : target.uid;
  // An entry that resolves to no owner, to more than one, or to a rank the
  // board has since reassigned is treated exactly like a runner who does not
  // exist: the viewer learns nothing either way, and never a wrong runner.
  if (targetUid === undefined || targetUid.length === 0) throw new HttpsError("not-found", UNAVAILABLE_MESSAGE);

  // The uid-addressed form has no board to fall back on if the caller
  // shouldn't see this runner, so every denial on this path — a block edge,
  // a suspension, or the visibility gate below — must read identically to
  // "this runner does not exist". The leaderboard path keeps its existing
  // `permission-denied` for a block/suspension: the entry itself already
  // proved the runner exists (it is on a public board), so that code carries
  // no new information.
  const denyCode = target.kind === "runner" ? "not-found" : "permission-denied";

  const gated = target.kind === "runner" && targetUid !== callerUid;

  let blocked = false;
  if (targetUid !== callerUid) {
    const edges = await ports.readBlockEdges(callerUid, targetUid);
    blocked = edges.callerBlockedTarget || edges.targetBlockedCaller;
    // On the gated path a block is settled below, with the same reads every
    // other denial performs; the leaderboard path can bail out immediately
    // because its entry already proved the runner exists.
    if (blocked && !gated) throw new HttpsError(denyCode, UNAVAILABLE_MESSAGE);
  }

  const [profile, account] = await Promise.all([ports.readProfile(targetUid), ports.readAccount(targetUid)]);
  // A suspended or banned runner's profile stops being viewable at all, so a
  // moderation action removes them from every viewer's reach, not just from
  // the leaderboard.
  const settledAgainst = blocked || profile === undefined || isSuspendedAccount(account);
  if (settledAgainst && !gated) {
    throw new HttpsError(profile === undefined ? "not-found" : denyCode, UNAVAILABLE_MESSAGE);
  }

  // The uid-addressed form is the one a viewer can point at any uid they
  // hold, so it alone needs an authorization gate: a leaderboard entry only
  // ever resolves to a runner who is already showing on a public board.
  //
  // Every denial here costs the same four reads in the same order — block
  // edges, profile and account, social edge, challenge roster. Returning the
  // identical `not-found` body is not enough on its own: an early bail-out
  // would still let a caller time the call and tell "no such runner" from
  // "not allowed to see this runner", which is the existence oracle the
  // single error code exists to close. Only the ALLOW path short-circuits,
  // so a runner opening a friend's profile still pays for as little as it
  // takes to say yes.
  if (gated) {
    if (settledAgainst) {
      // Both reads run unconditionally — not short-circuited on the first
      // true — because an already-settled denial must cost exactly what a
      // gate denial costs. Letting a blocked runner who happens to be a
      // friend skip the second read would reopen the timing gap by one read.
      await ports.readSocialEdge(callerUid, targetUid);
      await ports.isChallengeCoMember(callerUid, targetUid);
      throw new HttpsError("not-found", UNAVAILABLE_MESSAGE);
    }
    let allowed = profile !== undefined && socialProfile(targetUid, profile) !== undefined;
    if (!allowed) allowed = await ports.readSocialEdge(callerUid, targetUid);
    if (!allowed) allowed = await ports.isChallengeCoMember(callerUid, targetUid);
    if (!allowed) throw new HttpsError("not-found", UNAVAILABLE_MESSAGE);
  }

  if (profile === undefined) throw new HttpsError("not-found", UNAVAILABLE_MESSAGE);

  // The runner's own "keep my record private" preference. It never applies to
  // the runner themselves: this callable also serves a runner who addresses
  // their own uid, and hiding their record from their own screen would be a
  // bug, not privacy. Anything other than an explicit `true` reads as visible,
  // so an absent or malformed field can never silently blank a profile.
  const statsHidden = targetUid !== callerUid && profile["publicStatsHidden"] === true;
  // Not read-then-discard: a hidden profile must not spend a Firestore read on
  // badge documents it will never relay.
  const ownedBadgeTierIds = statsHidden ? [] : await ports.readOwnedBadgeTierIds(targetUid);
  // Resolved through the shared reader so this projection and the Feed author
  // overlay apply the identical nickname-wins rule and avatarUrl sanitisation
  // to the same stored fields.
  const identity = resolveProfileIdentityDisplay(profile, avatarContext);
  // The resolved uid stays here. Echoing it back would let any signed-in
  // caller walk every rank of every public snapshot and rebuild the uid
  // directory this whole design exists to avoid.
  // Identity — name, avatar, region, level badge, division, tier — is NOT
  // covered by the privacy switch. Every one of those values already appears
  // on `leaderboardSnapshots`, which any signed-in user can read, so
  // withholding them here would suppress nothing while breaking the header of
  // a screen the viewer reached by tapping that very row. What the switch
  // covers is the running record underneath: XP progress, streak, distance,
  // and earned badges.
  return {
    displayName: identity.displayName,
    avatarInitials: identity.avatarInitials,
    avatarUrl: identity.avatarUrl,
    regionLabel: trimmedString(profile["locationLabel"]),
    levelLabel: trimmedString(profile["levelLabel"]),
    level: nonNegativeInteger(profile["level"]),
    levelProgressPercent: statsHidden ? 0 : clampedPercent(profile["levelProgressPercent"]),
    totalXp: statsHidden ? null : nonNegativeIntegerOrNull(profile["totalXp"]),
    nextLevelXp: statsHidden ? null : nonNegativeIntegerOrNull(profile["nextLevelXp"]),
    xpToNextLevel: statsHidden ? null : nonNegativeIntegerOrNull(profile["xpToNextLevel"]),
    // Max level is asserted by the backend writing an explicit null, exactly
    // the signal the runner's own progress read model uses. An absent field
    // means "not published yet", never "max level". A hidden record reports
    // false rather than relaying the assertion, which is itself a fact about
    // how far the runner has come.
    isMaxLevel: !statsHidden && "xpToNextLevel" in profile && profile["xpToNextLevel"] === null,
    divisionKey: trimmedString(profile["divisionKey"]),
    divisionLabel: trimmedString(profile["divisionLabel"]),
    longestStreakLabel: statsHidden ? "" : trimmedString(profile["longestStreakLabel"]),
    totalDistanceLabel: statsHidden ? "" : trimmedString(profile["totalDistanceLabel"]),
    subscriptionStatusLabel: subscriptionStatusLabel(account),
    ownedBadgeTierIds,
    statsHidden,
  };
}

/**
 * Relays the trusted Basic/Premium tier. An unknown or missing value resolves
 * to Basic so an unrecognised value is never shown as Premium.
 */
function subscriptionStatusLabel(account: Readonly<Record<string, unknown>> | undefined): string {
  const status = account?.["subscriptionStatus"];
  return typeof status === "string" && status.trim().toLowerCase() === "premium" ? "Premium" : "Basic";
}

/**
 * The two ways a viewer may address a runner.
 *
 * `leaderboardEntry` is the original form: the leaderboard entry the viewer
 * tapped, pinned to the aggregation build that produced it. It needs no
 * authorization gate beyond the block/suspension checks — resolving it at
 * all already proves the runner is showing on a board every signed-in user
 * can read.
 *
 * `runner` is a direct uid, for the screens outside the leaderboard (feed,
 * friends, challenge) that hold only a uid and never a board entry. Because
 * a caller could hold any uid obtained elsewhere, this form is gated by the
 * visibility check in `getRunnerPublicProfile` before anything is returned.
 */
type RunnerTarget =
  | { readonly kind: "leaderboardEntry"; readonly snapshotId: string; readonly rankLabel: string; readonly buildId: string }
  | { readonly kind: "runner"; readonly uid: string };

function parseTarget(raw: unknown): RunnerTarget | undefined {
  if (!isRecord(raw)) return undefined;
  const keys = Object.keys(raw).sort();
  if (keys.length === 1 && keys[0] === "uid") {
    const uid = safeIdentifier(raw["uid"], 128);
    return uid === undefined ? undefined : { kind: "runner", uid };
  }
  if (keys.length !== 3 || keys[0] !== "buildId" || keys[1] !== "rankLabel" || keys[2] !== "snapshotId") return undefined;
  const snapshotId = safeIdentifier(raw["snapshotId"], 256);
  const rankLabel = safeIdentifier(raw["rankLabel"], 16);
  const buildId = safeIdentifier(raw["buildId"], 128);
  if (snapshotId === undefined || rankLabel === undefined || buildId === undefined) return undefined;
  return { kind: "leaderboardEntry", snapshotId, rankLabel, buildId };
}

function safeIdentifier(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) return undefined;
  if (value.includes("/") || value.includes("..") || /[\u0000-\u001F\u007F]/u.test(value)) return undefined;
  return value;
}

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function nonNegativeInteger(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : 0;
}

function nonNegativeIntegerOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

function clampedPercent(value: unknown): number {
  const percent = typeof value === "number" && Number.isFinite(value) ? value : 0;
  return Math.min(100, Math.max(0, percent));
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
