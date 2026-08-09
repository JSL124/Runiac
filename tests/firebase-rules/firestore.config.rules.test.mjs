import { describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

import {
  dbFor,
  seed,
  seedUser,
  unauthenticatedDb,
} from './support/firestore_rules_test_support.mjs';

describe('backend-owned admin config collections', () => {
  it('denies an authenticated non-admin client read/write access to config docs', async () => {
    await seedUser('alice', 'basic');
    await seed('config/progression', { minLevel: 1 });
    await seed('config/leaderboard', { minRunsToQualify: 1 });

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'config/progression')));
    await assertFails(
      setDoc(doc(alice, 'config/progression'), { minLevel: 99 }),
    );

    await assertFails(getDoc(doc(alice, 'config/leaderboard')));
    await assertFails(
      setDoc(doc(alice, 'config/leaderboard'), { minRunsToQualify: 0 }),
    );
  });

  it('allows a signed-in client to read the display-only config docs but never write them', async () => {
    await seedUser('alice', 'basic');
    await seed('config/paywall', { title: 'Premium', enabled: true });
    await seed('config/featureAccess', {
      features: { advancedAnalysis: { minimumTier: 'premium', enabled: true } },
    });
    await seed('config/characterAccess', {
      premiumOnlyCharacters: ['cap', 'purple'],
      version: 1,
    });

    const alice = dbFor('alice');

    await assertSucceeds(getDoc(doc(alice, 'config/paywall')));
    await assertFails(
      setDoc(doc(alice, 'config/paywall'), { title: 'Hacked' }),
    );

    await assertSucceeds(getDoc(doc(alice, 'config/featureAccess')));
    await assertFails(
      setDoc(doc(alice, 'config/featureAccess'), { features: {} }),
    );

    await assertSucceeds(getDoc(doc(alice, 'config/characterAccess')));
    await assertFails(
      setDoc(doc(alice, 'config/characterAccess'), { premiumOnlyCharacters: [] }),
    );
  });

  it('denies an unauthenticated client read access to the display-only config docs', async () => {
    await seed('config/paywall', { title: 'Premium', enabled: true });
    await seed('config/featureAccess', { features: {} });
    await seed('config/characterAccess', { premiumOnlyCharacters: [], version: 1 });

    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(anon, 'config/paywall')));
    await assertFails(getDoc(doc(anon, 'config/featureAccess')));
    await assertFails(getDoc(doc(anon, 'config/characterAccess')));
  });

  it('denies an authenticated non-admin client read/write access to badgeConfigs', async () => {
    await seedUser('alice', 'basic');
    await seed('badgeConfigs/distance_10k', {
      badgeId: 'distance_10k',
      title: '10K Distance Badge',
    });

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'badgeConfigs/distance_10k')));
    await assertFails(
      setDoc(doc(alice, 'badgeConfigs/distance_10k'), { title: 'Hacked' }),
    );
  });
});
