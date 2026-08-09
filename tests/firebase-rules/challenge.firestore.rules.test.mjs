import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import { dbFor, profileFields, seed, unauthenticatedDb } from './support/firestore_rules_test_support.mjs';

const CHALLENGE_ID = 'challenge-alice-100k';
const TIER_ID = '100K';
const INVITE_ID = 'invite-alice-bob';

// Roster: alice (owner) + bob (member). carol is a non-member outsider.
const instanceDoc = (status = 'ACTIVE') => ({
  challengeId: CHALLENGE_ID,
  ownerUid: 'alice',
  tierId: TIER_ID,
  catalogVersion: 'challenge-distance-v1',
  mode: 'GROUP',
  status,
  rules: {
    tierId: TIER_ID,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Challenging',
    durationDays: 28,
    durationMs: 2419200000,
    maxParticipants: 4,
    maxInvitedFriends: 3,
    targetMeters: 100000,
    personalMinimumMeters: 13000,
  },
  rosterUids: ['alice', 'bob'],
  maxParticipants: 4,
  teamMeters: 42000,
  createdAt: 10,
  startsAt: 11,
  scheduledEndsAt: 99,
});

const participantDoc = (uid, role) => ({
  uid,
  role,
  status: 'ACTIVE',
  creditedMeters: 21000,
  reward: 'PENDING',
  displayNameSnapshot: 'Synthetic Runner',
  avatarInitialsSnapshot: 'SR',
});

const invitationDoc = () => ({
  inviteId: INVITE_ID,
  challengeId: CHALLENGE_ID,
  tierId: TIER_ID,
  ownerUid: 'alice',
  recipientUid: 'bob',
  status: 'PENDING',
  createdAt: 10,
  expiresAt: 100,
});

const slotDoc = (uid, role) => ({
  uid,
  challengeId: CHALLENGE_ID,
  tierId: TIER_ID,
  role,
  reservedAt: 10,
});

const historyDoc = () => ({
  challengeId: CHALLENGE_ID,
  tierId: TIER_ID,
  mode: 'GROUP',
  role: 'owner',
  outcome: 'SUCCEEDED',
  terminalReason: 'TARGET_REACHED',
  teamMeters: 100000,
  personalMeters: 42000,
  targetMeters: 100000,
  personalMinimumMeters: 13000,
  startedAt: 11,
  endedAt: 88,
});

const badgeDoc = () => ({
  tierId: TIER_ID,
  catalogVersion: 'challenge-distance-v1',
  firstEarnedChallengeId: CHALLENGE_ID,
  earnedAt: 88,
});

const grantDoc = () => ({
  challengeId: CHALLENGE_ID,
  uid: 'alice',
  tierId: TIER_ID,
  status: 'ISSUED',
  grantedAt: 88,
});

const holdDoc = () => ({
  uid: 'alice',
  challengeId: CHALLENGE_ID,
  tierId: TIER_ID,
  role: 'owner',
  lapsedAt: 88,
  graceExpiresAt: 99,
});

async function seedActiveChallenge() {
  await seed(`challengeInstances/${CHALLENGE_ID}`, instanceDoc('ACTIVE'));
  await seed(`challengeInstances/${CHALLENGE_ID}/participants/alice`, participantDoc('alice', 'owner'));
  await seed(`challengeInstances/${CHALLENGE_ID}/participants/bob`, participantDoc('bob', 'member'));
  await seed(`challengeInvitations/${INVITE_ID}`, invitationDoc());
  await seed('challengeSlots/alice', slotDoc('alice', 'owner'));
  await seed('challengeSlots/bob', slotDoc('bob', 'member'));
  await seed(`users/alice/challengeHistory/${CHALLENGE_ID}`, historyDoc());
  await seed(`users/alice/challengeBadges/${TIER_ID}`, badgeDoc());
  await seed(`challengeRewardGrants/${CHALLENGE_ID}_alice`, grantDoc());
  await seed('challengePremiumHolds/alice', holdDoc());
}

describe('trusted Challenge Firestore rules — member reads', () => {
  it('lets every snapshotted roster member read the instance and participants', async () => {
    await seedActiveChallenge();
    const instancePath = `challengeInstances/${CHALLENGE_ID}`;

    for (const memberUid of ['alice', 'bob']) {
      const memberDb = dbFor(memberUid);
      await assertSucceeds(getDoc(doc(memberDb, instancePath)));
      await assertSucceeds(getDoc(doc(memberDb, `${instancePath}/participants/alice`)));
      await assertSucceeds(getDoc(doc(memberDb, `${instancePath}/participants/bob`)));
      await assertSucceeds(
        getDocs(query(collection(memberDb, `${instancePath}/participants`), orderBy(documentId()), limit(20))),
      );
    }
  });

  it('lets the owner read their own slot, history, and badge documents', async () => {
    await seedActiveChallenge();
    const alice = dbFor('alice');

    await assertSucceeds(getDoc(doc(alice, 'challengeSlots/alice')));
    await assertSucceeds(getDoc(doc(alice, `users/alice/challengeHistory/${CHALLENGE_ID}`)));
    await assertSucceeds(getDoc(doc(alice, `users/alice/challengeBadges/${TIER_ID}`)));
    await assertSucceeds(
      getDocs(query(collection(alice, 'users/alice/challengeHistory'), orderBy(documentId()), limit(30))),
    );
    await assertSucceeds(
      getDocs(query(collection(alice, 'users/alice/challengeBadges'), orderBy(documentId()), limit(30))),
    );
  });

  it('lets both the owner and the recipient read an invitation', async () => {
    await seedActiveChallenge();
    const invitePath = `challengeInvitations/${INVITE_ID}`;

    await assertSucceeds(getDoc(doc(dbFor('alice'), invitePath)));
    await assertSucceeds(getDoc(doc(dbFor('bob'), invitePath)));
    await assertSucceeds(
      getDocs(query(
        collection(dbFor('bob'), 'challengeInvitations'),
        where('recipientUid', '==', 'bob'),
        where('status', '==', 'PENDING'),
        orderBy('createdAt', 'desc'),
        limit(20),
      )),
    );
  });
});

describe('trusted Challenge Firestore rules — denied reads', () => {
  it('denies non-members, other users, and anonymous callers on instance and participants', async () => {
    await seedActiveChallenge();
    const instancePath = `challengeInstances/${CHALLENGE_ID}`;
    const carol = dbFor('carol');
    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(carol, instancePath)));
    await assertFails(getDoc(doc(anon, instancePath)));
    await assertFails(getDoc(doc(carol, `${instancePath}/participants/alice`)));
    await assertFails(getDoc(doc(carol, `${instancePath}/participants/bob`)));
  });

  it('denies non-member participant list queries and over-limit member list queries', async () => {
    await seedActiveChallenge();
    const participantsPath = `challengeInstances/${CHALLENGE_ID}/participants`;

    await assertFails(
      getDocs(query(collection(dbFor('carol'), participantsPath), orderBy(documentId()), limit(20))),
    );
    await assertFails(
      getDocs(query(collection(dbFor('alice'), participantsPath), orderBy(documentId()), limit(21))),
    );
    await assertFails(
      getDocs(query(
        collection(dbFor('alice'), 'challengeInstances'),
        where('rosterUids', 'array-contains', 'alice'),
        orderBy('createdAt', 'desc'),
        limit(21),
      )),
    );
  });

  it('denies slot, history, badge, and grant reads to anyone but the owner', async () => {
    await seedActiveChallenge();

    await assertFails(getDoc(doc(dbFor('bob'), 'challengeSlots/alice')));
    await assertFails(getDoc(doc(dbFor('carol'), 'challengeSlots/alice')));
    await assertFails(getDoc(doc(dbFor('bob'), `users/alice/challengeHistory/${CHALLENGE_ID}`)));
    await assertFails(getDoc(doc(dbFor('bob'), `users/alice/challengeBadges/${TIER_ID}`)));
    // Reward grants are server-only: even the owner cannot read them from a client.
    await assertFails(getDoc(doc(dbFor('alice'), `challengeRewardGrants/${CHALLENGE_ID}_alice`)));
    await assertFails(getDoc(doc(dbFor('carol'), `challengeInvitations/${INVITE_ID}`)));
    await assertFails(getDocs(query(collection(dbFor('alice'), 'challengeSlots'), limit(20))));
  });

  it('denies premium-lapse holds to every client, including the runner they belong to', async () => {
    // Stricter than challengeSlots on purpose: a readable hold would expose
    // that a runner's subscription lapsed, and — because the id is the uid — a
    // lobby-mate could probe for it directly. The runner sees their own grace
    // window only through the getActiveChallenge callable.
    await seedActiveChallenge();

    await assertFails(getDoc(doc(dbFor('alice'), 'challengePremiumHolds/alice')));
    await assertFails(getDoc(doc(dbFor('bob'), 'challengePremiumHolds/alice')));
    await assertFails(getDoc(doc(dbFor('carol'), 'challengePremiumHolds/alice')));
    await assertFails(getDocs(query(collection(dbFor('alice'), 'challengePremiumHolds'), limit(20))));
  });
});

describe('trusted Challenge Firestore rules — all client writes denied', () => {
  it('rejects every direct client write across challenge/reward/slot/history/badge paths', async () => {
    await seedActiveChallenge();
    const instancePath = `challengeInstances/${CHALLENGE_ID}`;
    const alice = dbFor('alice');
    const bob = dbFor('bob');
    const carol = dbFor('carol');

    // Forged roster / team metres on the instance.
    await assertFails(setDoc(doc(alice, instancePath), instanceDoc('ACTIVE')));
    await assertFails(updateDoc(doc(alice, instancePath), { teamMeters: 100000 }));
    await assertFails(updateDoc(doc(alice, instancePath), { rosterUids: ['alice', 'bob', 'carol'] }));
    await assertFails(updateDoc(doc(alice, instancePath), { status: 'SUCCEEDED' }));
    await assertFails(deleteDoc(doc(alice, instancePath)));
    await assertFails(setDoc(doc(carol, `${instancePath}/participants/carol`), participantDoc('carol', 'member')));

    // Forged credited metres, reward status, and role on a participant doc.
    await assertFails(updateDoc(doc(alice, `${instancePath}/participants/alice`), { creditedMeters: 999999 }));
    await assertFails(updateDoc(doc(bob, `${instancePath}/participants/bob`), { creditedMeters: 999999 }));
    await assertFails(updateDoc(doc(alice, `${instancePath}/participants/alice`), { reward: 'ISSUED' }));
    await assertFails(updateDoc(doc(bob, `${instancePath}/participants/bob`), { role: 'owner' }));
    await assertFails(
      updateDoc(doc(alice, `${instancePath}/participants/alice`), { displayNameSnapshot: 'Forged Name' }),
    );

    // Slot reservation, reward grant, invitation, history, and badge forgery.
    await assertFails(setDoc(doc(alice, 'challengeSlots/alice'), slotDoc('alice', 'owner')));
    await assertFails(deleteDoc(doc(alice, 'challengeSlots/alice')));
    await assertFails(setDoc(doc(alice, `challengeRewardGrants/${CHALLENGE_ID}_alice`), grantDoc()));
    await assertFails(updateDoc(doc(alice, `challengeRewardGrants/${CHALLENGE_ID}_alice`), { status: 'ISSUED' }));
    await assertFails(setDoc(doc(alice, `challengeInvitations/${INVITE_ID}`), invitationDoc()));
    await assertFails(updateDoc(doc(bob, `challengeInvitations/${INVITE_ID}`), { status: 'ACCEPTED' }));
    await assertFails(setDoc(doc(alice, `users/alice/challengeHistory/${CHALLENGE_ID}`), historyDoc()));
    await assertFails(setDoc(doc(alice, `users/alice/challengeBadges/${TIER_ID}`), badgeDoc()));
    await assertFails(deleteDoc(doc(alice, `users/alice/challengeBadges/${TIER_ID}`)));

    // A client must not be able to grant itself an unlimited grace window, nor
    // delete a hold to escape eviction.
    await assertFails(setDoc(doc(alice, 'challengePremiumHolds/alice'), holdDoc()));
    await assertFails(updateDoc(doc(alice, 'challengePremiumHolds/alice'), { graceExpiresAt: 99999999 }));
    await assertFails(deleteDoc(doc(alice, 'challengePremiumHolds/alice')));
  });
});

describe('trusted Challenge Firestore rules — result ceremony seen-marker', () => {
  const seenPath = 'users/alice/challengeState/challengeResultSeen';

  it('lets the owner create, advance, and read their own marker', async () => {
    const alice = dbFor('alice');

    await assertSucceeds(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 1000 }));
    await assertSucceeds(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 2000 }));
    // Re-writing the same high-water mark is the ordinary idempotent replay.
    await assertSucceeds(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 2000 }));

    const snapshot = await getDoc(doc(alice, seenPath));
    assert.equal(snapshot.data().lastSeenResultEndedAtMs, 2000);
  });

  it('refuses to rewind the marker, which would re-arm a ceremony', async () => {
    const alice = dbFor('alice');
    await assertSucceeds(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 2000 }));

    await assertFails(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 1999 }));
    await assertFails(updateDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 0 }));
  });

  it('accepts nothing but the one integer field, at the one document id', async () => {
    const alice = dbFor('alice');

    // No smuggling extra state into the one client-writable path under users/.
    await assertFails(
      setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 1000, outcome: 'SUCCEEDED' }),
    );
    await assertFails(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: '1000' }));
    await assertFails(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 0 }));
    await assertFails(setDoc(doc(alice, 'users/alice/challengeState/anythingElse'), {
      lastSeenResultEndedAtMs: 1000,
    }));
  });

  it('keeps the marker private to its owner and undeletable', async () => {
    const alice = dbFor('alice');
    await assertSucceeds(setDoc(doc(alice, seenPath), { lastSeenResultEndedAtMs: 1000 }));

    await assertFails(getDoc(doc(dbFor('bob'), seenPath)));
    await assertFails(setDoc(doc(dbFor('bob'), seenPath), { lastSeenResultEndedAtMs: 1 }));
    await assertFails(getDoc(doc(unauthenticatedDb(), seenPath)));
    await assertFails(deleteDoc(doc(alice, seenPath)));
    await assertFails(
      getDocs(query(collection(alice, 'users/alice/challengeState'), orderBy(documentId()), limit(30))),
    );
  });
});

describe('trusted Challenge Firestore rules — no broadened profile/activity access', () => {
  it('does not grant any cross-user profile or activity read through challenge membership', async () => {
    await seedActiveChallenge();
    await seed('userProfiles/alice', profileFields);
    await seed('activities/activity-alice-001', {
      ownerUid: 'alice',
      status: 'validated',
      distanceMeters: 5000,
      endedAt: 20,
    });

    // bob is a roster co-member of alice, but challenge rules must not expose
    // alice's profile or activity documents.
    await assertFails(getDoc(doc(dbFor('bob'), 'userProfiles/alice')));
    await assertFails(getDoc(doc(dbFor('bob'), 'activities/activity-alice-001')));
    await assertFails(getDoc(doc(dbFor('carol'), 'userProfiles/alice')));
  });
});
