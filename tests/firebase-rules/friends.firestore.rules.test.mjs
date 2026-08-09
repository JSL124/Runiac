import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import { dbFor, profileFields, seed } from './support/firestore_rules_test_support.mjs';

const aliceFriend = {
  friendUid: 'bob',
  uid: 'bob',
  nickname: 'Bøb',
  displayName: 'Bøb',
  avatarInitials: 'BØ',
  listSortKey: 'bøb',
  listSortTieBreaker: 'bob',
  createdAt: 1,
  updatedAt: 1,
};

const incomingRequest = {
  senderUid: 'bob',
  recipientUid: 'alice',
  direction: 'incoming',
  status: 'PENDING',
  uid: 'bob',
  nickname: 'Bøb',
  displayName: 'Bøb',
  avatarInitials: 'BØ',
  listSortKey: 'bøb',
  listSortTieBreaker: 'bob',
  createdAt: 1,
  updatedAt: 1,
};

const outgoingRequest = {
  ...incomingRequest,
  senderUid: 'alice',
  recipientUid: 'carol',
  direction: 'outgoing',
  uid: 'carol',
  nickname: 'Carol',
  displayName: 'Carol',
  avatarInitials: 'CA',
  listSortKey: 'carol',
  listSortTieBreaker: 'carol',
};

const blockedRow = {
  blockedUid: 'bob',
  uid: 'bob',
  nickname: 'Bøb',
  displayName: 'Bøb',
  avatarInitials: 'BØ',
  listSortKey: 'bøb',
  listSortTieBreaker: 'bob',
  createdAt: 1,
};

function orderedOwnerList(db, path, pageLimit = 30) {
  return query(
    collection(db, path),
    orderBy('listSortKey'),
    orderBy('listSortTieBreaker'),
    limit(pageLimit),
  );
}

function orderedRequestList(db, direction, pageLimit = 30) {
  return query(
    collection(db, 'users/alice/friendRequests'),
    where('status', '==', 'PENDING'),
    where('direction', '==', direction),
    orderBy('listSortKey'),
    orderBy('listSortTieBreaker'),
    limit(pageLimit),
  );
}

describe('Friends Firestore Rules', () => {
  it('allows the initial non-nickname profile create but denies client identity and discovery mutations', async () => {
    const profile = doc(dbFor('alice'), 'userProfiles/alice');

    await assertSucceeds(setDoc(profile, profileFields));
    await assertFails(updateDoc(profile, { displayName: 'Alice' }));
    await assertFails(updateDoc(profile, { avatarInitials: 'AL' }));
    await assertFails(updateDoc(profile, { nickname: 'Alice' }));
    await assertFails(updateDoc(profile, { nicknameIndexKey: 'n1_not_allowed' }));
    await assertFails(updateDoc(profile, { socialDiscoveryStatus: 'active' }));
    await assertFails(updateDoc(profile, { socialListSortKey: 'alice' }));
  });

  it('allows exact owner list query shapes with limit 30 and denies unbounded, oversized, and cross-user lists', async () => {
    await seed('users/alice/friends/bob', aliceFriend);
    await seed('users/alice/friendRequests/bob', incomingRequest);
    await seed('users/alice/friendRequests/carol', outgoingRequest);
    await seed('users/alice/blockedUsers/bob', blockedRow);
    const alice = dbFor('alice');
    const bob = dbFor('bob');

    await assertSucceeds(getDoc(doc(alice, 'users/alice/friends/bob')));
    await assertSucceeds(getDoc(doc(alice, 'users/alice/friendRequests/bob')));
    await assertSucceeds(getDoc(doc(alice, 'users/alice/blockedUsers/bob')));
    await assertSucceeds(getDocs(orderedOwnerList(alice, 'users/alice/friends')));
    await assertSucceeds(getDocs(orderedRequestList(alice, 'incoming')));
    await assertSucceeds(getDocs(orderedRequestList(alice, 'outgoing')));
    await assertSucceeds(getDocs(orderedOwnerList(alice, 'users/alice/blockedUsers')));

    await assertFails(getDocs(collection(alice, 'users/alice/friends')));
    await assertFails(getDocs(collection(alice, 'users/alice/blockedUsers')));
    await assertFails(getDocs(query(
      collection(alice, 'users/alice/friendRequests'),
      where('status', '==', 'PENDING'),
      where('direction', '==', 'incoming'),
      orderBy('listSortKey'),
      orderBy('listSortTieBreaker'),
    )));
    await assertFails(getDocs(orderedOwnerList(alice, 'users/alice/friends', 31)));
    await assertFails(getDocs(orderedRequestList(alice, 'incoming', 31)));
    await assertFails(getDocs(orderedOwnerList(alice, 'users/alice/blockedUsers', 31)));
    await assertFails(getDoc(doc(bob, 'users/alice/friends/bob')));
    await assertFails(getDocs(orderedOwnerList(bob, 'users/alice/friends')));
    await assertFails(getDocs(orderedRequestList(bob, 'incoming')));
    await assertFails(getDocs(orderedOwnerList(bob, 'users/alice/blockedUsers')));
  });

  it('denies every direct Friends, Requests, Blocked, and nickname-claim mutation', async () => {
    const alice = dbFor('alice');
    const rows = [
      [doc(alice, 'users/alice/friends/bob'), aliceFriend],
      [doc(alice, 'users/alice/friendRequests/bob'), incomingRequest],
      [doc(alice, 'users/alice/blockedUsers/bob'), blockedRow],
    ];
    await seed('users/alice/friends/bob', aliceFriend);
    await seed('users/alice/friendRequests/bob', incomingRequest);
    await seed('users/alice/blockedUsers/bob', blockedRow);
    await seed('nicknameClaims/n1_safe', {
      ownerUid: 'alice',
      nicknameCanonical: 'alice',
      nicknameIndexKey: 'n1_safe',
    });

    for (const [reference, data] of rows) {
      await assertFails(setDoc(reference, data));
      await assertFails(updateDoc(reference, { updatedAt: 2 }));
      await assertFails(deleteDoc(reference));
    }
    await assertFails(getDoc(doc(alice, 'nicknameClaims/n1_safe')));
    await assertFails(getDocs(collection(alice, 'nicknameClaims')));
    await assertFails(setDoc(doc(alice, 'nicknameClaims/n1_new'), {
      ownerUid: 'alice',
      nicknameCanonical: 'alice',
      nicknameIndexKey: 'n1_new',
    }));
    await assertFails(updateDoc(doc(alice, 'nicknameClaims/n1_safe'), { ownerUid: 'bob' }));
    await assertFails(deleteDoc(doc(alice, 'nicknameClaims/n1_safe')));
  });

  it('declares the required composite owner-list indexes', () => {
    const indexes = JSON.parse(readFileSync(new URL('../../firestore.indexes.json', import.meta.url), 'utf8'));
    const signature = (index) => [
      index.collectionGroup,
      ...index.fields.map((field) => `${field.fieldPath}:${field.order ?? field.arrayConfig}`),
    ].join('|');
    const actual = new Set(indexes.indexes.map(signature));

    assert.equal(actual.has('friends|listSortKey:ASCENDING|listSortTieBreaker:ASCENDING'), true);
    assert.equal(actual.has('blockedUsers|listSortKey:ASCENDING|listSortTieBreaker:ASCENDING'), true);
    assert.equal(
      actual.has('friendRequests|status:ASCENDING|direction:ASCENDING|listSortKey:ASCENDING|listSortTieBreaker:ASCENDING'),
      true,
    );

    const collectionGroupUidIndexes = new Set(
      indexes.fieldOverrides
        .filter((override) => override.fieldPath === 'uid')
        .flatMap((override) => override.indexes.map((index) =>
          `${override.collectionGroup}|${index.order}|${index.queryScope}`)),
    );
    assert.deepEqual(collectionGroupUidIndexes, new Set([
      'friends|ASCENDING|COLLECTION_GROUP',
      'friendRequests|ASCENDING|COLLECTION_GROUP',
      'blockedUsers|ASCENDING|COLLECTION_GROUP',
    ]));
  });
});
