import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

import { dbFor, seed, seedUser, unauthenticatedDb } from './support/firestore_rules_test_support.mjs';

// Two rules-level guarantees for account deletion.
//
//   1. accountDeletionCommands is invisible and unwritable to every client,
//      including the runner whose deletion it records. It carries a resume
//      cursor and a status; a client that could write it could forge a
//      completed erase, or point one at somebody else's uid.
//   2. accountStatus 'deleting' blocks the same client writes 'suspended' and
//      'banned' do. This is defence-in-depth only — requestAccountDeletion
//      already revoked the refresh tokens and disabled the Auth user — and it
//      exists to close the window in which an ID token minted just before that
//      is still unexpired.

const COMMAND_PATH = 'accountDeletionCommands/alice';

describe('accountDeletionCommands', () => {
  it('denies every client read', async () => {
    await seed(COMMAND_PATH, { uid: 'alice', status: 'pending', completedSteps: [] });

    await assertFails(getDoc(doc(dbFor('alice'), COMMAND_PATH)));
    await assertFails(getDoc(doc(dbFor('bob'), COMMAND_PATH)));
    await assertFails(getDoc(doc(unauthenticatedDb(), COMMAND_PATH)));
  });

  it('denies a runner enqueueing their own deletion directly', async () => {
    // The only supported entry point is the requestAccountDeletion callable,
    // which also locks the account out. A client-created command would start an
    // erase against an account that can still sign in and keep writing.
    await assertFails(
      setDoc(doc(dbFor('alice'), COMMAND_PATH), { uid: 'alice', status: 'pending' }),
    );
  });

  it('denies pointing a deletion at another uid', async () => {
    await assertFails(
      setDoc(doc(dbFor('bob'), COMMAND_PATH), { uid: 'alice', status: 'pending' }),
    );
  });

  it('denies tampering with an in-flight erase', async () => {
    await seed(COMMAND_PATH, { uid: 'alice', status: 'erasing', completedSteps: [] });

    // Forging completion would make the fan-out skip every remaining step.
    await assertFails(
      updateDoc(doc(dbFor('alice'), COMMAND_PATH), { status: 'completed' }),
    );
    await assertFails(deleteDoc(doc(dbFor('alice'), COMMAND_PATH)));
  });
});

describe("accountStatus 'deleting'", () => {
  it('blocks the writes a suspended account is blocked from', async () => {
    await seedUser('alice', 'basic');
    await seed('users/deleting-runner', {
      subscriptionStatus: 'basic',
      userRole: 'Basic User',
      accountStatus: 'deleting',
    });
    await seed('feedPosts/post-1', {
      authorUid: 'alice',
      status: 'published',
      createdAt: 1,
    });

    // Filing a report is the canonical isNotSuspended()-gated create.
    await assertFails(
      setDoc(doc(dbFor('deleting-runner'), 'reports/deleting-runner_alice'), {
        reporterUid: 'deleting-runner',
        targetType: 'user',
        targetId: 'alice',
        reason: 'spam',
        createdAt: 1,
      }),
    );
  });

  it('still allows a healthy account through the same path', async () => {
    // Guards against the rule being tightened into a blanket denial: the
    // 'deleting' value must be what blocks, not the check itself.
    await seedUser('carol', 'basic');
    await seedUser('dave', 'basic');

    const result = await assertSucceeds(
      setDoc(doc(dbFor('carol'), 'reports/carol_dave'), {
        reporterUid: 'carol',
        targetType: 'user',
        targetId: 'dave',
        reason: 'spam',
        createdAt: 1,
      }),
    );
    assert.equal(result, undefined);
  });
});
