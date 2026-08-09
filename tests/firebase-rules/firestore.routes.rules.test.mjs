import { describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

import {
  dbFor,
  seed,
  sharedRouteDraft,
} from './support/firestore_rules_test_support.mjs';

describe('shared route privacy boundaries', () => {
  it('allows owners to create draft route metadata without precise GPS traces', async () => {
    await assertSucceeds(
      setDoc(doc(dbFor('alice'), 'sharedRoutes/route-001'), sharedRouteDraft),
    );
    await assertFails(
      setDoc(doc(dbFor('alice'), 'sharedRoutes/route-002'), {
        ...sharedRouteDraft,
        rawCoordinates: [{ latitude: 1.2345, longitude: 6.789 }],
      }),
    );
    await assertFails(
      setDoc(doc(dbFor('alice'), 'sharedRoutes/route-003'), {
        ...sharedRouteDraft,
        moderationStatus: 'approved',
      }),
    );
    await assertFails(
      setDoc(doc(dbFor('alice'), 'sharedRoutes/route-004'), {
        ...sharedRouteDraft,
        visibilityStatus: 'published',
      }),
    );
  });

  it('enforces private and published shared route read boundaries', async () => {
    await seed('sharedRoutes/private-route', sharedRouteDraft);
    await seed('sharedRoutes/published-route', {
      ...sharedRouteDraft,
      visibilityStatus: 'published',
      moderationStatus: 'approved',
    });

    await assertSucceeds(getDoc(doc(dbFor('alice'), 'sharedRoutes/private-route')));
    await assertFails(getDoc(doc(dbFor('bob'), 'sharedRoutes/private-route')));
    await assertSucceeds(getDoc(doc(dbFor('bob'), 'sharedRoutes/published-route')));
  });

  it('denies owner updates and deletes of an existing draft route, including self-publishing', async () => {
    await seed('sharedRoutes/route-draft', sharedRouteDraft);

    const route = doc(dbFor('alice'), 'sharedRoutes/route-draft');

    // sharedRoutes has no update/delete allow: an owner cannot flip their
    // own draft to published, mutate any other field, or delete the doc.
    await assertFails(updateDoc(route, { visibilityStatus: 'published' }));
    await assertFails(updateDoc(route, { title: 'Renamed Synthetic Loop' }));
    await assertFails(updateDoc(route, { updatedAt: 2 }));
    await assertFails(deleteDoc(route));
  });
});
