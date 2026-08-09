import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import type { FeedFixtureScenario } from "./emulatorFixtures.js";
import { syntheticFeedFixture } from "./fixtureDefinitions.js";

const fixtures = {
  author: syntheticFeedFixture.author,
  friend: syntheticFeedFixture.acceptedFriend,
  nonFriend: syntheticFeedFixture.nonFriend,
} as const;
const activityId = "feed-fixture-activity";

export async function applySyntheticFeedFixture(scenario: FeedFixtureScenario): Promise<void> {
  if (getApps().length === 0) initializeApp({ projectId: "demo-runiac-feed" });
  const auth = getAuth();
  const firestore = getFirestore();
  switch (scenario) {
    case "reset":
      await resetFixture(auth, firestore);
      return;
    case "baseline":
      await ensureBaseline(auth, firestore);
      return;
    case "unfriend":
      await ensureBaseline(auth, firestore);
      await Promise.all([firestore.doc(`users/${fixtures.author.uid}/friends/${fixtures.friend.uid}`).delete(), firestore.doc(`users/${fixtures.friend.uid}/friends/${fixtures.author.uid}`).delete()]);
      return;
    case "block-viewer":
      await ensureBaseline(auth, firestore);
      await firestore.doc(`users/${fixtures.friend.uid}/blockedUsers/${fixtures.author.uid}`).set(block(fixtures.author.uid));
      return;
    case "block-author":
      await ensureBaseline(auth, firestore);
      await firestore.doc(`users/${fixtures.author.uid}/blockedUsers/${fixtures.friend.uid}`).set(block(fixtures.friend.uid));
      return;
    case "delete-activity":
      await ensureBaseline(auth, firestore);
      await firestore.doc(`activities/${activityId}`).delete();
      return;
    default:
      return assertNever(scenario);
  }
}

async function resetFixture(auth: ReturnType<typeof getAuth>, firestore: ReturnType<typeof getFirestore>): Promise<void> {
  await clearRelationshipFixtureDocuments(firestore);
  await Promise.all(Object.values(fixtures).map(async (fixture) => {
    await firestore.doc(`users/${fixture.uid}`).delete();
    await firestore.doc(`userProfiles/${fixture.uid}`).delete();
    try { await auth.deleteUser(fixture.uid); } catch (error: unknown) { if (!isAuthMissingUser(error)) throw error; }
  }));
  await firestore.doc(`activities/${activityId}`).delete();
}

async function ensureBaseline(auth: ReturnType<typeof getAuth>, firestore: ReturnType<typeof getFirestore>): Promise<void> {
  await clearRelationshipFixtureDocuments(firestore);
  await Promise.all(Object.values(fixtures).map(async (fixture) => {
    try { await auth.getUser(fixture.uid); } catch (error: unknown) { if (isAuthMissingUser(error)) await auth.createUser({ uid: fixture.uid, displayName: fixture.displayName, email: fixture.email, emailVerified: true }); else throw error; }
    await firestore.doc(`users/${fixture.uid}`).set({ displayName: fixture.displayName });
    await firestore.doc(`userProfiles/${fixture.uid}`).set({ displayName: fixture.displayName, avatarInitials: fixture.avatarInitials });
  }));
  const createdAt = "2026-07-11T00:00:00.000Z";
  await Promise.all([
    firestore.doc(`users/${fixtures.author.uid}/friends/${fixtures.friend.uid}`).set(friendship(fixtures.friend.uid, createdAt)),
    firestore.doc(`users/${fixtures.friend.uid}/friends/${fixtures.author.uid}`).set(friendship(fixtures.author.uid, createdAt)),
    firestore.doc(`activities/${activityId}`).set({ ownerUid: fixtures.author.uid, status: "validated", validationStatus: "validated", endedAt: createdAt, distanceMeters: 1000, durationSeconds: 600, averagePaceSecondsPerKm: 600 }),
  ]);
}
async function clearRelationshipFixtureDocuments(firestore: ReturnType<typeof getFirestore>): Promise<void> {
  const authorUid = fixtures.author.uid;
  const friendUid = fixtures.friend.uid;
  await Promise.all([
    firestore.doc(`users/${authorUid}/friends/${friendUid}`).delete(),
    firestore.doc(`users/${friendUid}/friends/${authorUid}`).delete(),
    firestore.doc(`users/${authorUid}/blockedUsers/${friendUid}`).delete(),
    firestore.doc(`users/${friendUid}/blockedUsers/${authorUid}`).delete(),
  ]);
}
function friendship(friendUid: string, createdAt: string): { readonly friendUid: string; readonly createdAt: string; readonly updatedAt: string } { return { friendUid, createdAt, updatedAt: createdAt }; }
function block(blockedUid: string): { readonly blockedUid: string; readonly createdAt: string } { return { blockedUid, createdAt: "2026-07-11T00:00:00.000Z" }; }
function isAuthMissingUser(error: unknown): boolean { return typeof error === "object" && error !== null && "code" in error && error["code"] === "auth/user-not-found"; }
function assertNever(value: never): never { throw new Error(`Unexpected fixture scenario: ${String(value)}`); }
