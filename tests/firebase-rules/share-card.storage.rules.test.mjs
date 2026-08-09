import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';
import { deleteDoc, doc, setDoc } from 'firebase/firestore';

import { assertFeedEmulatorContract } from './feed.emulator.guard.mjs';

const STORAGE_RULES_PATH = new URL('../../storage.rules', import.meta.url);
const FIRESTORE_RULES_PATH = new URL('../../firestore.rules', import.meta.url);
const PROJECT_ID = 'demo-runiac-feed';
const PNG_BYTES = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const PNG_METADATA = { contentType: 'image/png' };
const CARD_PATH = 'share-cards/alice/rank-card.png';
const ACTIVITY_CARD_PATH = 'share-cards/alice/activity-card.png';
const FEATURE_ACCESS_PATH = 'config/featureAccess';

let testEnv;

function storageFor(uid) {
  return testEnv.authenticatedContext(uid).storage();
}

async function seedObject(path) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), path), PNG_BYTES, PNG_METADATA);
  });
}

// Bypasses both storage.rules and firestore.rules so tests can arrange
// Firestore fixtures the storage rule's cross-service firestore.get()/
// firestore.exists() calls will read, independent of firestore.rules'
// own write rules for config/ and users/.
async function seedFirestore(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function clearFeatureAccessConfig() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), FEATURE_ACCESS_PATH));
  });
}

async function seedShareCardsFeatureAccess(entry) {
  await seedFirestore(FEATURE_ACCESS_PATH, { features: { shareCards: entry }, version: 1 });
}

async function seedUser(uid, subscriptionStatus) {
  await seedFirestore(`users/${uid}`, { subscriptionStatus, userRole: 'Basic User' });
}

describe('Share card Storage Rules', () => {
  before(async () => {
    assertFeedEmulatorContract();
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      storage: {
        host: '127.0.0.1',
        port: 9199,
        rules: readFileSync(STORAGE_RULES_PATH, 'utf8'),
      },
      firestore: {
        host: '127.0.0.1',
        port: 8080,
        rules: readFileSync(FIRESTORE_RULES_PATH, 'utf8'),
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearStorage();
    await testEnv.clearFirestore();
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  it('allows the owner to upload a valid PNG card', async () => {
    await assertSucceeds(
      uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
    );
  });

  it('denies uploading to another user path', async () => {
    await assertFails(
      uploadBytes(
        ref(storageFor('mallory'), CARD_PATH),
        PNG_BYTES,
        PNG_METADATA,
      ),
    );
  });

  it('denies an unauthenticated upload', async () => {
    const anon = testEnv.unauthenticatedContext().storage();
    await assertFails(
      uploadBytes(ref(anon, CARD_PATH), PNG_BYTES, PNG_METADATA),
    );
  });

  it('rejects a non-PNG content type', async () => {
    await assertFails(
      uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, {
        contentType: 'image/jpeg',
      }),
    );
  });

  it('rejects an oversized upload', async () => {
    const oversized = new Uint8Array(4 * 1024 * 1024 + 1);
    oversized.set(PNG_BYTES);
    await assertFails(
      uploadBytes(ref(storageFor('alice'), CARD_PATH), oversized, PNG_METADATA),
    );
  });

  it('rejects a non-png filename', async () => {
    await assertFails(
      uploadBytes(
        ref(storageFor('alice'), 'share-cards/alice/rank-card.gif'),
        PNG_BYTES,
        PNG_METADATA,
      ),
    );
  });

  it('lets the owner read but denies a non-owner', async () => {
    await seedObject(CARD_PATH);
    await assertSucceeds(getBytes(ref(storageFor('alice'), CARD_PATH)));
    await assertFails(getBytes(ref(storageFor('mallory'), CARD_PATH)));
  });

  it('allows the owner to upload and read a run-activity card', async () => {
    await assertSucceeds(
      uploadBytes(
        ref(storageFor('alice'), ACTIVITY_CARD_PATH),
        PNG_BYTES,
        PNG_METADATA,
      ),
    );
    await assertSucceeds(getBytes(ref(storageFor('alice'), ACTIVITY_CARD_PATH)));
  });

  describe('config-driven premium gating (mirrors isPremiumGatedFeature)', () => {
    it('fails open when config/featureAccess does not exist: a Basic user can still upload', async () => {
      await clearFeatureAccessConfig();

      await assertSucceeds(
        uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
      );
    });

    it('allows a Basic user to upload when shareCards.minimumTier is "basic"', async () => {
      await seedShareCardsFeatureAccess({ minimumTier: 'basic', enabled: true });

      await assertSucceeds(
        uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
      );
    });

    it('denies a Basic user from uploading when shareCards.minimumTier is "premium"', async () => {
      await seedShareCardsFeatureAccess({ minimumTier: 'premium', enabled: true });
      await seedUser('alice', 'basic');

      await assertFails(
        uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
      );
    });

    it('allows a Premium user ("premium") to upload when shareCards.minimumTier is "premium"', async () => {
      await seedShareCardsFeatureAccess({ minimumTier: 'premium', enabled: true });
      await seedUser('alice', 'premium');

      await assertSucceeds(
        uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
      );
    });

    it('allows a Premium user ("Premium", capitalized) to upload when shareCards.minimumTier is "premium"', async () => {
      await seedShareCardsFeatureAccess({ minimumTier: 'premium', enabled: true });
      await seedUser('alice', 'Premium');

      await assertSucceeds(
        uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
      );
    });

    it('releases the gate when enabled: false, even with minimumTier: "premium": a Basic user can upload', async () => {
      await seedShareCardsFeatureAccess({ minimumTier: 'premium', enabled: false });
      await seedUser('alice', 'basic');

      await assertSucceeds(
        uploadBytes(ref(storageFor('alice'), CARD_PATH), PNG_BYTES, PNG_METADATA),
      );
    });
  });
});
