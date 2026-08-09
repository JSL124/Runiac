import { describe, it } from 'node:test';
import { assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

import {
  dbFor,
  profileFields,
} from './support/firestore_rules_test_support.mjs';

describe('backend-owned read models', () => {
  it('denies client writes to trusted progression and leaderboard fields', async () => {
    const alice = dbFor('alice');

    await assertFails(
      setDoc(doc(alice, 'runSummaries/summary-001'), { ownerUid: 'alice' }),
    );
    await assertFails(
      setDoc(doc(alice, 'progressionEvents/event-001'), { ownerUid: 'alice' }),
    );
    await assertFails(
      setDoc(doc(alice, 'progressionEvents/event-streak-001'), {
        ownerUid: 'alice',
        previousStreak: 1,
        nextStreak: 2,
        previousStreakRunDate: '2026-06-14',
        nextStreakRunDate: '2026-06-15',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'leaderboardSnapshots/weekly-sg'), { rank: 1 }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), { ...profileFields, xp: 10 }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        streak: 2,
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), { ...profileFields, level: 3 }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), { ...profileFields, rank: 4 }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        leaderboardScore: 5,
      }),
    );
  });

});
