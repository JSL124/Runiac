// Account deletion: the callable that locks the account out, and the fan-out
// that erases it.
//
// The behavioural contract this pins down:
//
//   inventory — the ordering constraints that silently corrupt state if
//               inverted, and the retain/delete split, asserted as data so a
//               collection added later cannot quietly escape the sweep
//   callable  — lockout, nickname release, idempotent double request, and the
//               confirmation guard
//   fan-out   — every shape of target (uid-keyed doc, subcollection, owner
//               field query, composite document id, collection-group mirror,
//               parent-scan marker, anonymize, Storage prefix, Auth user),
//               plus replay
//   challenge — member leaves, owner transfers ownership, owner cancels when
//               no successor exists
//
// Emulator-backed, in the main `npm test` group (auth + firestore + storage).

import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage, type Storage } from "firebase-admin/storage";

import { runAccountDeletionFanOut } from "../src/account/accountDeletionCore.js";
import { requestAccountDeletionForCallable } from "../src/account/requestAccountDeletion.js";
import { createAccountDeletionCommandHandlers } from "../src/account/accountDeletionCommand.js";
import { ACCOUNT_DELETION_COMMANDS } from "../src/account/accountDeletionCommandTypes.js";
import {
  ACCOUNT_DELETION_STEPS,
  DELETED_USER_SENTINEL,
  RETAINED_COLLECTIONS,
  accountDeletionStepIds,
  accountStoragePrefixes,
} from "../src/account/accountDeletionInventory.js";
import { buildChallengeRulesSnapshot } from "../src/challenge/challengeCatalog.js";
import type { ChallengeTierId } from "../src/challenge/challengeTypes.js";

const PROJECT_ID = "runiac-functions-test";

// Every test gets its own subject uid, and this is not incidental tidiness.
//
// This suite runs in the main group, which starts the FUNCTIONS emulator, so
// `functions/src/index.ts` is live: the moment a test creates
// `accountDeletionCommands/{uid}` — which `requestAccountDeletion` does as its
// last act — the real `accountDeletionCommandCreated` trigger fires and starts
// a genuine fan-out for that uid, in parallel, outside this test's control.
// Deleting the command document in `beforeEach` does not stop an execution that
// has already begun, so with a shared uid that stray fan-out lands in the
// middle of a LATER test and erases the fixtures it just seeded. That produced
// a real, reproduced-once cross-test failure in `challenge exit` before this
// isolation existed. Unique uids make the stray work harmless: it converges on
// an account nobody is looking at any more.
let subjectSerial = 0;
function nextSubject(): string {
  subjectSerial += 1;
  return `delete-subject-${subjectSerial}`;
}

let SUBJECT: string;
const FRIEND = "delete-friend";
const OTHER = "delete-other";

const OPEN_TIER: ChallengeTierId = "10K";
const NOW = Date.UTC(2026, 7, 4, 3, 0, 0);

let firestore: Firestore;
let auth: Auth;
let storage: Storage;

before(() => {
  if (getApps().length === 0) {
    initializeApp({ projectId: PROJECT_ID, storageBucket: `${PROJECT_ID}.appspot.com` });
  }
  firestore = getFirestore();
  auth = getAuth();
  storage = getStorage();
});

beforeEach(async () => {
  SUBJECT = nextSubject();
  await resetFixtures();
});

// ---------------------------------------------------------------------------
// Inventory
// ---------------------------------------------------------------------------

describe("account deletion inventory", () => {
  it("gives every step a unique id", () => {
    const ids = accountDeletionStepIds();
    assert.equal(new Set(ids).size, ids.length);
  });

  it("exits challenges before anything else, so participation state still exists", () => {
    assert.equal(ACCOUNT_DELETION_STEPS[0]?.kind, "challengeExit");
  });

  it("resolves the avatar object before deleting the profile that points at it", () => {
    const ids = accountDeletionStepIds();
    assert.ok(
      ids.indexOf("avatar-objects") < ids.indexOf("user-profile"),
      "the durable avatar path is only discoverable from userProfiles/{uid}",
    );
  });

  it("deletes the Auth user last, so a partial fan-out keeps the uid reserved", () => {
    assert.equal(ACCOUNT_DELETION_STEPS.at(-1)?.kind, "authUser");
    assert.equal(ACCOUNT_DELETION_STEPS.at(-2)?.kind, "storage");
  });

  it("never both erases and retains the same collection", () => {
    const erased = new Set(
      ACCOUNT_DELETION_STEPS.flatMap((step) =>
        "collection" in step ? [step.collection] : [],
      ),
    );
    for (const retained of RETAINED_COLLECTIONS) {
      assert.ok(
        !erased.has(retained.collection),
        `${retained.collection} is listed as retained but also erased`,
      );
    }
  });

  it("gives every retained collection a stated reason", () => {
    for (const retained of RETAINED_COLLECTIONS) {
      assert.ok(retained.reason.length > 40, `${retained.collection} needs a real reason`);
    }
  });

  it("keeps the durable avatar out of the uid-prefixed Storage list", () => {
    // avatars/{32-hex}.png carries no uid, so a prefix sweep can never reach it.
    // If it ever appears here, the resolve step has been made redundant by a
    // change that also broke it.
    assert.ok(accountStoragePrefixes(SUBJECT).every((prefix) => !prefix.startsWith("avatars/")));
    assert.ok(accountStoragePrefixes(SUBJECT).every((prefix) => prefix.includes(SUBJECT)));
  });
});

// ---------------------------------------------------------------------------
// Stage A: the callable
// ---------------------------------------------------------------------------

describe("requestAccountDeletion", () => {
  it("rejects an unauthenticated caller", async () => {
    await assert.rejects(
      () =>
        requestAccountDeletionForCallable(
          { data: { confirmation: "DELETE" } },
          { firestore, auth },
          NOW,
        ),
      /Authentication is required/,
    );
  });

  it("rejects a payload without the exact confirmation token", async () => {
    for (const data of [{}, { confirmation: "delete" }, { confirmation: "DELETE " }]) {
      await assert.rejects(
        () => requestAccountDeletionForCallable({ auth: { uid: SUBJECT }, data }, { firestore, auth }, NOW),
        /confirmation must be the exact word DELETE/,
      );
    }
  });

  it("rejects an unexpected payload field", async () => {
    await assert.rejects(
      () =>
        requestAccountDeletionForCallable(
          { auth: { uid: SUBJECT }, data: { confirmation: "DELETE", uid: OTHER } },
          { firestore, auth },
          NOW,
        ),
      /Account deletion payload/,
    );
  });

  it("locks the account out, frees the nickname, and enqueues the erase", async () => {
    await seedAccount(SUBJECT);

    const result = await requestAccountDeletionForCallable(
      { auth: { uid: SUBJECT }, data: { confirmation: "DELETE" } },
      { firestore, auth },
      NOW,
    );

    assert.equal(result.status, "accepted");

    const user = await firestore.doc(`users/${SUBJECT}`).get();
    assert.equal(user.get("accountStatus"), "deleting");

    // The nickname is the one resource another runner may be waiting on, and
    // the claim is keyed by the nickname rather than the uid — once the profile
    // is gone nothing points at it any more.
    const claim = await firestore.doc(`nicknameClaims/${SUBJECT}`).get();
    assert.equal(claim.exists, false);

    const profile = await firestore.doc(`userProfiles/${SUBJECT}`).get();
    assert.equal(profile.get("socialDiscoveryStatus"), "inactive");

    const command = await firestore.doc(`${ACCOUNT_DELETION_COMMANDS}/${SUBJECT}`).get();
    assert.equal(command.get("status"), "pending");
    assert.deepEqual(command.get("completedSteps"), []);

    const authUser = await auth.getUser(SUBJECT);
    assert.equal(authUser.disabled, true);
  });

  it("leaves another runner's nickname claim alone", async () => {
    await seedAccount(SUBJECT);
    // The claim now belongs to somebody else — a rename race in which this
    // runner's old nickname was already taken over.
    await firestore.doc(`nicknameClaims/${SUBJECT}`).set({
      ownerUid: OTHER,
      nicknameCanonical: SUBJECT,
    });

    await requestAccountDeletionForCallable(
      { auth: { uid: SUBJECT }, data: { confirmation: "DELETE" } },
      { firestore, auth },
      NOW,
    );

    const claim = await firestore.doc(`nicknameClaims/${SUBJECT}`).get();
    assert.equal(claim.get("ownerUid"), OTHER);
  });

  it("is idempotent on a double request", async () => {
    await seedAccount(SUBJECT);

    const first = await requestAccountDeletionForCallable(
      { auth: { uid: SUBJECT }, data: { confirmation: "DELETE" } },
      { firestore, auth },
      NOW,
    );
    const second = await requestAccountDeletionForCallable(
      { auth: { uid: SUBJECT }, data: { confirmation: "DELETE" } },
      { firestore, auth },
      NOW + 1000,
    );

    assert.equal(first.status, "accepted");
    assert.equal(second.status, "already_requested");

    const command = await firestore.doc(`${ACCOUNT_DELETION_COMMANDS}/${SUBJECT}`).get();
    assert.equal(command.get("requestedAt").toMillis(), NOW);
  });
});

// ---------------------------------------------------------------------------
// Stage B/C: the fan-out
// ---------------------------------------------------------------------------

describe("account deletion fan-out", () => {
  it("erases every shape of target the runner owns", async () => {
    await seedAccount(SUBJECT);
    await seedOwnedData(SUBJECT);

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    // uid-keyed documents and their subcollections
    for (const path of [
      `users/${SUBJECT}`,
      `userProfiles/${SUBJECT}`,
      `generatedPlans/${SUBJECT}`,
      `planProgress/${SUBJECT}`,
      `notificationPreferences/${SUBJECT}`,
      `challengeSlots/${SUBJECT}`,
      `leaderboardCurrentViews/${SUBJECT}`,
      `users/${SUBJECT}/challengeBadges/10K`,
      `users/${SUBJECT}/challengeState/challengeResultSeen`,
      `notificationInbox/${SUBJECT}/items/n1`,
      `notificationDevices/${SUBJECT}/tokens/t1`,
    ]) {
      assert.equal((await firestore.doc(path).get()).exists, false, `${path} survived`);
    }

    // owner-field queries
    for (const collection of ["activities", "runSummaries", "progressionEvents", "sharedRoutes"]) {
      const remaining = await firestore.collection(collection).where("ownerUid", "==", SUBJECT).get();
      assert.equal(remaining.size, 0, `${collection} survived`);
    }

    // composite document id: agentGuidanceDaily/{uid}_{dayKey}
    assert.equal((await firestore.doc(`agentGuidanceDaily/${SUBJECT}_2026-08-04`).get()).exists, false);

    // both directions of challengeInvitations
    const invitations = await firestore.collection("challengeInvitations").get();
    assert.equal(invitations.size, 0);
  });

  it("removes the mirror rows other runners hold", async () => {
    await seedAccount(SUBJECT);
    await seedSocialMirrors(SUBJECT, FRIEND);

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    // The friend's own copy of the edge must go too, or their Friends list
    // keeps rendering a runner who no longer exists.
    assert.equal((await firestore.doc(`users/${FRIEND}/friends/${SUBJECT}`).get()).exists, false);
    assert.equal((await firestore.doc(`users/${FRIEND}/friendRequests/${SUBJECT}`).get()).exists, false);
    assert.equal((await firestore.doc(`users/${OTHER}/blockedUsers/${SUBJECT}`).get()).exists, false);

    // Engagement left on somebody else's post.
    assert.equal((await firestore.doc(`feedPosts/other-post/likes/${SUBJECT}`).get()).exists, false);
    const comments = await firestore
      .collection("feedPosts/other-post/comments")
      .where("authorUid", "==", SUBJECT)
      .get();
    assert.equal(comments.size, 0);

    // Deleted rather than anonymized: the nickname is inside the rendered prose.
    assert.equal((await firestore.doc(`notificationInbox/${FRIEND}/items/about-subject`).get()).exists, false);

    // The friend's unrelated rows are untouched.
    assert.equal((await firestore.doc(`users/${FRIEND}/friends/${OTHER}`).get()).exists, true);
  });

  it("anonymizes reports and feedback instead of deleting them", async () => {
    await seedAccount(SUBJECT);
    await seedModerationRecords(SUBJECT);

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    const filed = await firestore.doc("reports/filed-by-subject").get();
    assert.equal(filed.exists, true, "deleting an account must not erase a report it filed");
    assert.equal(filed.get("reporterUid"), DELETED_USER_SENTINEL);
    assert.equal(filed.get("reason"), "spam", "only the identity is rewritten");

    const about = await firestore.doc("reports/about-subject").get();
    assert.equal(about.get("targetId"), DELETED_USER_SENTINEL);

    const feedback = await firestore.doc("feedback/from-subject").get();
    assert.equal(feedback.exists, true);
    assert.equal(feedback.get("uid"), DELETED_USER_SENTINEL);
    assert.equal(feedback.get("message"), "the map is slow");
  });

  it("does not rewrite a post report whose targetId merely collides with the uid", async () => {
    await seedAccount(SUBJECT);
    // targetType 'feedPost' means targetId is a POST id. An unconditional
    // rewrite would corrupt this row.
    await firestore.doc("reports/post-report").set({
      reporterUid: OTHER,
      targetType: "feedPost",
      targetId: SUBJECT,
    });

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    const report = await firestore.doc("reports/post-report").get();
    assert.equal(report.get("targetId"), SUBJECT);
  });

  it("deletes the durable avatar object, which no uid prefix can reach", async () => {
    await seedAccount(SUBJECT);
    const objectPath = "avatars/0123456789abcdef0123456789abcdef.png";
    await storage.bucket().file(objectPath).save(Buffer.from("png"));
    await firestore.doc(`userProfiles/${SUBJECT}`).update({ avatarObjectPath: objectPath });
    await storage.bucket().file(`share-cards/${SUBJECT}/activity-card.png`).save(Buffer.from("png"));

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    const [avatarExists] = await storage.bucket().file(objectPath).exists();
    assert.equal(avatarExists, false, "orphaned avatar objects stay publicly readable by URL");
    const [cardExists] = await storage.bucket().file(`share-cards/${SUBJECT}/activity-card.png`).exists();
    assert.equal(cardExists, false);
  });

  it("deletes the Auth user last", async () => {
    await seedAccount(SUBJECT);

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    await assert.rejects(() => auth.getUser(SUBJECT), /no user record/i);
  });

  it("is a no-op when replayed", async () => {
    await seedAccount(SUBJECT);
    await seedOwnedData(SUBJECT);
    await seedModerationRecords(SUBJECT);

    const first = await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);
    // A redelivered trigger runs the whole thing again with no cursor at all,
    // which is the harshest replay: every step re-executes from scratch.
    const second = await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    assert.deepEqual(second.completedSteps, first.completedSteps);
    assert.equal(
      second.outcomes.filter((step) => step.stepId !== "storage" && step.deletedCount > 1).length,
      0,
      "a replay must find nothing left to erase",
    );

    // The anonymized rows must not be double-rewritten into nonsense.
    const filed = await firestore.doc("reports/filed-by-subject").get();
    assert.equal(filed.get("reporterUid"), DELETED_USER_SENTINEL);
  });

  it("resumes from a cursor without redoing completed steps", async () => {
    await seedAccount(SUBJECT);
    await seedOwnedData(SUBJECT);

    const result = await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW, {
      completedSteps: ["challenge-exit", "feed-posts"],
    });

    assert.ok(!result.outcomes.some((step) => step.stepId === "feed-posts"));
    assert.ok(result.completedSteps.includes("feed-posts"));
    // Everything else still ran.
    assert.equal((await firestore.doc(`users/${SUBJECT}`).get()).exists, false);
  });
});

// ---------------------------------------------------------------------------
// Challenge exit
// ---------------------------------------------------------------------------

describe("account deletion challenge exit", () => {
  it("removes a member and leaves the challenge running", async () => {
    await seedAccount(SUBJECT);
    await seedChallenge({ ownerUid: FRIEND, memberUids: [SUBJECT] });

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    const instance = await firestore.doc("challengeInstances/c1").get();
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(instance.get("ownerUid"), FRIEND);
    const participant = await firestore.doc(`challengeInstances/c1/participants/${SUBJECT}`).get();
    assert.equal(participant.get("status"), "LEFT");
  });

  it("transfers ownership rather than destroying everyone else's challenge", async () => {
    await seedAccount(SUBJECT);
    await seedChallenge({ ownerUid: SUBJECT, memberUids: [FRIEND, OTHER] });

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    const instance = await firestore.doc("challengeInstances/c1").get();
    assert.equal(instance.get("status"), "ACTIVE", "the remaining members did nothing wrong");
    assert.equal(instance.get("ownerUid"), FRIEND, "earliest-joined remaining member inherits");

    const successor = await firestore.doc(`challengeInstances/c1/participants/${FRIEND}`).get();
    assert.equal(successor.get("role"), "owner");

    const departed = await firestore.doc(`challengeInstances/c1/participants/${SUBJECT}`).get();
    assert.equal(departed.get("status"), "LEFT");
  });

  it("cancels the instance when no successor remains", async () => {
    await seedAccount(SUBJECT);
    await seedChallenge({ ownerUid: SUBJECT, memberUids: [] });

    await runAccountDeletionFanOut({ firestore, storage, auth }, SUBJECT, NOW);

    const instance = await firestore.doc("challengeInstances/c1").get();
    assert.equal(instance.get("status"), "CANCELLED");
    assert.equal(instance.get("terminalReason"), "OWNER_ACCOUNT_DELETED");
  });
});

// ---------------------------------------------------------------------------
// The trigger
// ---------------------------------------------------------------------------

describe("accountDeletionCommandCreated", () => {
  it("runs the erase and records per-step counts", async () => {
    await seedAccount(SUBJECT);
    await seedOwnedData(SUBJECT);
    await firestore.doc(`${ACCOUNT_DELETION_COMMANDS}/${SUBJECT}`).set({
      uid: SUBJECT,
      status: "pending",
      requestedAt: Timestamp.fromMillis(NOW),
      completedSteps: [],
    });

    const handlers = createAccountDeletionCommandHandlers({
      firestore,
      storage,
      auth,
      now: () => NOW,
    });
    await handlers.onCommandCreated(SUBJECT, { uid: SUBJECT });

    const command = await firestore.doc(`${ACCOUNT_DELETION_COMMANDS}/${SUBJECT}`).get();
    assert.equal(command.get("status"), "completed");
    assert.deepEqual(
      [...(command.get("completedSteps") as string[])].sort(),
      [...accountDeletionStepIds()].sort(),
    );
    // Deliberately NOT asserting a per-step count here. Creating the command
    // document also fires the real trigger in the Functions emulator, so two
    // fan-outs run for this uid concurrently and whichever wins a given step
    // reports the rows while the other reports zero. Both converge on the same
    // end state, which is what the remaining assertions check; the exact
    // counts belong to the direct fan-out tests above, where nothing races.
    assert.ok(command.get("stepCounts") !== undefined);
    assert.equal((await firestore.doc(`users/${SUBJECT}`).get()).exists, false);
  });

  it("does not reprocess a command that already completed", async () => {
    await seedAccount(SUBJECT);
    await firestore.doc(`${ACCOUNT_DELETION_COMMANDS}/${SUBJECT}`).set({
      uid: SUBJECT,
      status: "completed",
      completedSteps: accountDeletionStepIds(),
    });

    const handlers = createAccountDeletionCommandHandlers({ firestore, storage, auth, now: () => NOW });
    await handlers.onCommandCreated(SUBJECT, { uid: SUBJECT });

    // The account documents seeded above are still there, proving the handler
    // returned before running anything.
    assert.equal((await firestore.doc(`users/${SUBJECT}`).get()).exists, true);
  });
});

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

async function resetFixtures(): Promise<void> {
  await Promise.all([
    firestore.recursiveDelete(firestore.collection("challengeInstances")),
    deleteCollection("challengeSlots"),
    deleteCollection("challengeInvitations"),
    deleteCollection("activities"),
    deleteCollection("runSummaries"),
    deleteCollection("progressionEvents"),
    deleteCollection("sharedRoutes"),
    deleteCollection("agentGuidanceDaily"),
    deleteCollection("reports"),
    deleteCollection("feedback"),
    deleteCollection("nicknameClaims"),
    deleteCollection(ACCOUNT_DELETION_COMMANDS),
    firestore.recursiveDelete(firestore.collection("feedPosts")),
  ]);

  await Promise.all(
    uidsInPlay().map(async (uid) => {
      await firestore.recursiveDelete(firestore.doc(`users/${uid}`));
      await firestore.recursiveDelete(firestore.doc(`notificationInbox/${uid}`));
      await firestore.recursiveDelete(firestore.doc(`notificationDevices/${uid}`));
      await Promise.all(
        [
          `userProfiles/${uid}`,
          `generatedPlans/${uid}`,
          `planProgress/${uid}`,
          `notificationPreferences/${uid}`,
          `leaderboardCurrentViews/${uid}`,
        ].map((path) => firestore.doc(path).delete()),
      );
      await deleteAuthUserIfPresent(uid);
    }),
  );

  for (const prefix of uidsInPlay().flatMap((uid) => accountStoragePrefixes(uid))) {
    await storage.bucket().deleteFiles({ prefix, force: true });
  }
}

async function seedAccount(uid: string): Promise<void> {
  await auth.createUser({ uid });
  await firestore.doc(`users/${uid}`).set({ uid, subscriptionStatus: "basic" });
  await firestore.doc(`userProfiles/${uid}`).set({
    uid,
    nickname: "SubjectNick",
    nicknameCanonical: uid,
    nicknameIndexKey: uid,
    socialDiscoveryStatus: "active",
  });
  await firestore.doc(`nicknameClaims/${SUBJECT}`).set({
    ownerUid: uid,
    nicknameCanonical: uid,
  });
}

async function seedOwnedData(uid: string): Promise<void> {
  await Promise.all([
    firestore.doc(`generatedPlans/${uid}`).set({ ownerUid: uid }),
    firestore.doc(`planProgress/${uid}`).set({ ownerUid: uid }),
    firestore.doc(`notificationPreferences/${uid}`).set({ ownerUid: uid }),
    firestore.doc(`challengeSlots/${uid}`).set({ uid }),
    firestore.doc(`leaderboardCurrentViews/${uid}`).set({ ownerUid: uid }),
    firestore.doc(`users/${uid}/challengeBadges/10K`).set({ tierId: "10K" }),
    firestore
      .doc(`users/${uid}/challengeState/challengeResultSeen`)
      .set({ lastSeenResultEndedAtMs: 1 }),
    firestore.doc(`notificationInbox/${uid}/items/n1`).set({ ownerUid: uid }),
    firestore.doc(`notificationDevices/${uid}/tokens/t1`).set({ enabled: true }),
    firestore.collection("activities").doc("a1").set({ ownerUid: uid, status: "validated" }),
    firestore.collection("runSummaries").doc("s1").set({ ownerUid: uid }),
    firestore.collection("progressionEvents").doc("p1").set({ ownerUid: uid }),
    firestore.collection("sharedRoutes").doc("r1").set({ ownerUid: uid }),
    firestore.doc(`agentGuidanceDaily/${uid}_2026-08-04`).set({ count: 1 }),
    firestore.collection("challengeInvitations").doc("i1").set({ ownerUid: uid, challengeId: "c1" }),
    firestore.collection("challengeInvitations").doc("i2").set({ recipientUid: uid, challengeId: "c1" }),
  ]);
}

async function seedSocialMirrors(uid: string, friendUid: string): Promise<void> {
  await Promise.all([
    firestore.doc(`users/${friendUid}/friends/${uid}`).set({ uid, nickname: "SubjectNick" }),
    firestore.doc(`users/${friendUid}/friends/${OTHER}`).set({ uid: OTHER, nickname: "Other" }),
    firestore.doc(`users/${friendUid}/friendRequests/${uid}`).set({ uid }),
    firestore.doc(`users/${OTHER}/blockedUsers/${uid}`).set({ uid }),
    firestore.doc("feedPosts/other-post").set({ authorUid: OTHER, status: "published" }),
    firestore.doc(`feedPosts/other-post/likes/${uid}`).set({ userUid: uid }),
    firestore.doc("feedPosts/other-post/comments/c1").set({ authorUid: uid, body: "nice run" }),
    firestore.doc(`notificationInbox/${friendUid}/items/about-subject`).set({
      ownerUid: friendUid,
      title: "SubjectNick liked your run",
      data: { actorUid: uid },
    }),
  ]);
}

async function seedModerationRecords(uid: string): Promise<void> {
  await Promise.all([
    firestore.doc("reports/filed-by-subject").set({
      reporterUid: uid,
      targetType: "feedPost",
      targetId: "some-post",
      reason: "spam",
    }),
    firestore.doc("reports/about-subject").set({
      reporterUid: OTHER,
      targetType: "user",
      targetId: uid,
    }),
    firestore.doc("feedback/from-subject").set({ uid, message: "the map is slow" }),
  ]);
}

async function seedChallenge(input: {
  readonly ownerUid: string;
  readonly memberUids: readonly string[];
}): Promise<void> {
  const rules = buildChallengeRulesSnapshot(OPEN_TIER);
  const roster = [input.ownerUid, ...input.memberUids];

  await firestore.doc("challengeInstances/c1").set({
    challengeId: "c1",
    ownerUid: input.ownerUid,
    tierId: OPEN_TIER,
    status: "ACTIVE",
    rosterUids: roster,
    teamMeters: 0,
    rules,
  });

  await Promise.all(
    roster.map(async (uid, index) => {
      await firestore.doc(`challengeInstances/c1/participants/${uid}`).set({
        uid,
        role: index === 0 ? "owner" : "member",
        status: "ACTIVE",
        contributedMeters: 0,
      });
      await firestore.doc(`challengeSlots/${uid}`).set({
        uid,
        challengeId: "c1",
        role: index === 0 ? "owner" : "member",
      });
      await firestore.doc(`users/${uid}`).set({ uid, subscriptionStatus: "basic" }, { merge: true });
    }),
  );
}

// The uids this test could have written to. SUBJECT is fresh every test, so
// most of this is a no-op; FRIEND and OTHER are shared and genuinely need it.
function uidsInPlay(): readonly string[] {
  return [SUBJECT, FRIEND, OTHER];
}

async function deleteCollection(name: string): Promise<void> {
  await firestore.recursiveDelete(firestore.collection(name));
}

async function deleteAuthUserIfPresent(uid: string): Promise<void> {
  try {
    await auth.deleteUser(uid);
  } catch {
    // Not present. The fixtures are shared across tests that delete it.
  }
}
