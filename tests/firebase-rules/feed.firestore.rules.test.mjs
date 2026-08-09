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
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import { dbFor, profileFields, removeSeed, seed, unauthenticatedDb } from './support/firestore_rules_test_support.mjs';
import './feed.emulator.guard.mjs';

const feedPost = (authorUid, status = 'published', createdAt = 10) => ({
  authorUid,
  activityId: `activity-${authorUid}-${createdAt}`,
  authorDisplayName: 'Synthetic Runner',
  authorAvatarInitials: 'SR',
  authorLevelLabel: 'Level 3',
  completedAt: createdAt,
  distanceMeters: 1800,
  durationSeconds: 1200,
  averagePaceSecondsPerKm: 400,
  thumbnailStoragePath: 'trusted-server-path',
  thumbnailObjectGeneration: '1',
  thumbnailSha256: 'synthetic-hash',
  likeCount: 0,
  commentCount: 0,
  status,
  schemaVersion: 1,
  createdAt,
  updatedAt: createdAt,
});

const friend = (uid) => ({ friendUid: uid, createdAt: 1, updatedAt: 1 });
const block = (uid) => ({ blockedUid: uid, createdAt: 1 });

async function seedFriendship(leftUid, rightUid) {
  await seed(`users/${leftUid}/friends/${rightUid}`, friend(rightUid));
  await seed(`users/${rightUid}/friends/${leftUid}`, friend(leftUid));
}

function feedQuery(db, authorUid, pageLimit = 20) {
  return query(
    collection(db, 'feedPosts'),
    where('authorUid', '==', authorUid),
    where('status', '==', 'published'),
    orderBy('createdAt', 'desc'),
    limit(pageLimit),
  );
}

function commentData(body) {
  return {
    authorUid: 'bob',
    authorDisplayName: 'Synthetic Runner',
    authorAvatarInitials: 'SR',
    authorLevelLabel: 'Level 3',
    body,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

describe('trusted Feed Firestore rules', () => {
  it('allows own and reciprocal-friend single-author published pages without access-call exhaustion', async () => {
    await seed('feedPosts/alice-newer', feedPost('alice', 'published', 20));
    await seed('feedPosts/alice-older', feedPost('alice', 'published', 10));
    await seedFriendship('alice', 'bob');

    const bobPage = await assertSucceeds(getDocs(feedQuery(dbFor('bob'), 'alice')));
    assert.equal(bobPage.size, 2);
    await assertSucceeds(getDocs(feedQuery(dbFor('alice'), 'alice')));
  });

  it('denies missing/revoked relationships, anonymous callers, either block direction, and inactive posts', async () => {
    await seed('feedPosts/alice-published', feedPost('alice'));
    await seed('feedPosts/alice-draft', feedPost('alice', 'draft'));
    await seed('feedPosts/alice-deleting', feedPost('alice', 'deleting'));
    await seed('feedPosts/alice-deleted', feedPost('alice', 'deleted'));
    const post = 'feedPosts/alice-published';

    await assertFails(getDoc(doc(dbFor('bob'), post)));
    await assertFails(getDoc(doc(unauthenticatedDb(), post)));
    await assertFails(getDoc(doc(dbFor('alice'), 'feedPosts/alice-draft')));
    await assertFails(getDoc(doc(dbFor('alice'), 'feedPosts/alice-deleting')));
    await assertFails(getDoc(doc(dbFor('alice'), 'feedPosts/alice-deleted')));

    await seedFriendship('alice', 'bob');
    await seed('users/bob/blockedUsers/alice', block('alice'));
    await assertFails(getDoc(doc(dbFor('bob'), post)));
  });

  it('denies the reverse block direction and a formerly trusted relationship with a missing reciprocal document', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    await seed('users/bob/friends/alice', friend('alice'));
    await assertFails(getDoc(doc(dbFor('bob'), 'feedPosts/alice-post')));

    await seedFriendship('alice', 'bob');
    await seed('users/alice/blockedUsers/bob', block('bob'));
    await assertFails(getDoc(doc(dbFor('bob'), 'feedPosts/alice-post')));
  });

  it('allows a friend Feed read before the block transaction state and denies it immediately after', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    await seedFriendship('alice', 'bob');
    const bobPost = doc(dbFor('bob'), 'feedPosts/alice-post');

    await assertSucceeds(getDoc(bobPost));
    await seed('users/alice/blockedUsers/bob', block('bob'));
    await removeSeed('users/alice/friends/bob');
    await removeSeed('users/bob/friends/alice');
    await assertFails(getDoc(bobPost));
  });

  it('requires a bounded single-author published query shape', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    await seed('feedPosts/carol-post', feedPost('carol'));
    await seedFriendship('alice', 'bob');
    await seedFriendship('carol', 'bob');
    await seed('users/carol/blockedUsers/bob', block('bob'));
    const bob = dbFor('bob');

    await assertFails(getDocs(query(collection(bob, 'feedPosts'), where('status', '==', 'published'), limit(20))));
    await assertFails(getDocs(feedQuery(bob, 'alice', 21)));
    await assertFails(getDocs(feedQuery(bob, 'carol')));
    await assertFails(getDocs(query(
      collection(bob, 'feedPosts'),
      where('authorUid', 'in', ['alice', 'carol']),
      where('status', '==', 'published'),
      orderBy('createdAt', 'desc'),
      limit(20),
    )));
  });

  it('keeps trusted friend and block documents owner-readable and client-write denied', async () => {
    await seedFriendship('alice', 'bob');
    await seed('users/alice/blockedUsers/carol', { ...block('carol'), reasonCode: 'safety' });
    const alice = dbFor('alice');
    const friendDoc = doc(alice, 'users/alice/friends/bob');
    const blockDoc = doc(alice, 'users/alice/blockedUsers/carol');

    await assertSucceeds(getDoc(friendDoc));
    await assertSucceeds(getDocs(query(collection(alice, 'users/alice/friends'), orderBy(documentId()), limit(30))));
    await assertFails(getDocs(query(collection(alice, 'users/alice/friends'), orderBy(documentId()), limit(31))));
    await assertSucceeds(getDoc(blockDoc));
    await assertSucceeds(getDocs(query(collection(alice, 'users/alice/blockedUsers'), orderBy(documentId()), limit(30))));
    await assertFails(getDocs(query(collection(alice, 'users/alice/blockedUsers'), orderBy(documentId()), limit(31))));
    await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/friends/bob')));
    await assertFails(setDoc(friendDoc, friend('bob')));
    await assertFails(updateDoc(friendDoc, { updatedAt: 2 }));
    await assertFails(deleteDoc(friendDoc));
    await assertFails(setDoc(blockDoc, block('carol')));
    await assertFails(updateDoc(blockDoc, { reasonCode: 'changed' }));
    await assertFails(deleteDoc(blockDoc));
  });

  it('allows only an accessible caller to create/delete their exact deterministic like without count writes', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    await seedFriendship('alice', 'bob');
    const bob = dbFor('bob');
    const like = doc(bob, 'feedPosts/alice-post/likes/bob');

    await assertSucceeds(setDoc(like, { userUid: 'bob', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(like, { createdAt: serverTimestamp() }));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/likes/bob-extra'), { userUid: 'bob-extra', createdAt: serverTimestamp(), count: 1 }));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/likes/other'), { userUid: 'bob', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(bob, 'feedPosts/alice-post'), { likeCount: 1 }));
    await assertSucceeds(deleteDoc(like));
  });

  it('enforces comment snapshot, time, body, and author-only mutation contracts', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    await seedFriendship('alice', 'bob');
    await seed('userProfiles/bob', {
      ...profileFields,
      displayName: 'Synthetic Runner',
      avatarInitials: 'SR',
      levelLabel: 'Level 3',
    });
    const bob = dbFor('bob');
    const comment = doc(bob, 'feedPosts/alice-post/comments/comment-001');

    await assertSucceeds(setDoc(comment, commentData('Nice steady run.')));
    await assertSucceeds(getDocs(query(collection(bob, 'feedPosts/alice-post/comments'), orderBy('createdAt', 'desc'), limit(20))));
    await assertFails(getDocs(query(collection(bob, 'feedPosts/alice-post/comments'), orderBy('createdAt', 'desc'), limit(21))));
    await assertSucceeds(updateDoc(comment, { body: 'Updated note.', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/blank'), commentData(' ')));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/untrimmed'), commentData(' trailing')));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/long'), commentData('x'.repeat(501))));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/forged-time'), { ...commentData('Wrong timestamp.'), createdAt: 1 }));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/forged-profile'), { ...commentData('Wrong snapshot.'), authorDisplayName: 'Forged' }));
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/forged-level'), { ...commentData('Wrong level.'), authorLevelLabel: 'Level 99' }));
    await assertFails(updateDoc(comment, { authorDisplayName: 'Forged' }));
    await assertFails(updateDoc(comment, { authorLevelLabel: 'Level 99' }));
    await assertFails(updateDoc(doc(dbFor('alice'), 'feedPosts/alice-post/comments/comment-001'), { body: 'Forged', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(dbFor('alice'), 'feedPosts/alice-post/comments/comment-001')));
    await assertSucceeds(deleteDoc(comment));
  });

  it('denies feed comment create/update from a suspended commenter, but not an unsuspended one or one with no accountStatus field', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    await seedFriendship('alice', 'bob');
    await seed('userProfiles/bob', {
      ...profileFields,
      displayName: 'Synthetic Runner',
      avatarInitials: 'SR',
      levelLabel: 'Level 3',
    });
    const bob = dbFor('bob');

    // Suspended: both create and update are denied. Defence-in-depth behind
    // the admin console's Auth-layer disable (see accountStatus.ts /
    // isNotSuspended() in firestore.rules) — it only matters for an
    // already-issued, unexpired ID token.
    await seed('users/bob', { accountStatus: 'suspended' });
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/suspended-create'), commentData('Should be denied.')));
    await seed('feedPosts/alice-post/comments/suspended-update', commentData('Seeded directly.'));
    await assertFails(updateDoc(doc(bob, 'feedPosts/alice-post/comments/suspended-update'), { body: 'Should be denied.', updatedAt: serverTimestamp() }));

    // Banned is the other blocking value.
    await seed('users/bob', { accountStatus: 'banned' });
    await assertFails(setDoc(doc(bob, 'feedPosts/alice-post/comments/banned-create'), commentData('Should be denied.')));

    // Explicitly unsuspended: unaffected.
    await seed('users/bob', { accountStatus: 'active' });
    await assertSucceeds(setDoc(doc(bob, 'feedPosts/alice-post/comments/active-create'), commentData('Should succeed.')));

    // No accountStatus field at all, and no users/{uid} doc at all: both must
    // keep today's behaviour, unaffected by this rule.
    await removeSeed('users/bob');
    await assertSucceeds(setDoc(doc(bob, 'feedPosts/alice-post/comments/no-doc-create'), commentData('Should succeed.')));
  });

  it('keeps hidden markers private/backend-only and rejects direct Feed reports while preserving generic reports', async () => {
    await seed('users/bob/hiddenFeedPosts/alice-post', { postId: 'alice-post', createdAt: 1 });
    const bob = dbFor('bob');
    const marker = doc(bob, 'users/bob/hiddenFeedPosts/alice-post');

    await assertSucceeds(getDoc(marker));
    await assertSucceeds(getDocs(query(collection(bob, 'users/bob/hiddenFeedPosts'), orderBy(documentId()), limit(30))));
    await assertFails(getDocs(query(collection(bob, 'users/bob/hiddenFeedPosts'), orderBy(documentId()), limit(31))));
    await assertFails(getDoc(doc(dbFor('alice'), 'users/bob/hiddenFeedPosts/alice-post')));
    await assertFails(setDoc(marker, { postId: 'alice-post', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(marker, { postId: 'other-post' }));
    await assertFails(deleteDoc(marker));
    await assertFails(setDoc(doc(bob, 'reports/feed-report'), {
      reporterUid: 'bob', targetType: 'feedPost', targetId: 'alice-post', reason: 'feed_inappropriate', description: '', createdAt: serverTimestamp(),
    }));
    await assertSucceeds(setDoc(doc(bob, 'reports/generic-report'), {
      reporterUid: 'bob', targetType: 'profile', targetId: 'generic', reason: 'other', description: '', createdAt: serverTimestamp(),
    }));
  });

  it('denies direct client feedPost creation and author-side deletion of a published post', async () => {
    await seed('feedPosts/alice-post', feedPost('alice'));
    const alice = dbFor('alice');

    // feedPosts documents are backend-created only: even a fully well-formed
    // post authored as the caller cannot be created client-side.
    await assertFails(setDoc(doc(alice, 'feedPosts/alice-forged'), feedPost('alice')));
    // Deletion goes through the backend lifecycle (status transitions), not
    // a direct client delete — even by the post's own author.
    await assertFails(deleteDoc(doc(alice, 'feedPosts/alice-post')));
  });
});
