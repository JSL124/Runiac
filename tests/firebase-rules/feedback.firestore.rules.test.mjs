import { describe, it } from 'node:test';
import { assertFails } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';

import { dbFor, seed, seedUser, unauthenticatedDb } from './support/firestore_rules_test_support.mjs';

const feedbackDoc = {
  uid: 'alice',
  message: 'The pace chart is confusing on the run summary screen.',
  category: 'bug',
  createdAt: 1,
};

describe('backend-owned feedback collection', () => {
  it('denies an authenticated client every direct read/write on feedback docs, including their own', async () => {
    await seedUser('alice', 'basic');
    await seed('feedback/fb1', feedbackDoc);

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'feedback/fb1')));
    await assertFails(getDocs(collection(alice, 'feedback')));
    await assertFails(setDoc(doc(alice, 'feedback/fb2'), feedbackDoc));
    await assertFails(updateDoc(doc(alice, 'feedback/fb1'), { message: 'edited' }));
    await assertFails(deleteDoc(doc(alice, 'feedback/fb1')));
  });

  it('denies an unauthenticated client every direct read/write on feedback docs', async () => {
    await seed('feedback/fb1', feedbackDoc);

    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(anon, 'feedback/fb1')));
    await assertFails(getDocs(collection(anon, 'feedback')));
    await assertFails(setDoc(doc(anon, 'feedback/fb2'), feedbackDoc));
    await assertFails(updateDoc(doc(anon, 'feedback/fb1'), { message: 'edited' }));
    await assertFails(deleteDoc(doc(anon, 'feedback/fb1')));
  });
});
