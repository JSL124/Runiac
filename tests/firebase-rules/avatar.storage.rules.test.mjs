import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, updateMetadata, uploadBytes } from 'firebase/storage';

import { assertFeedEmulatorContract } from './feed.emulator.guard.mjs';

const RULES_PATH = new URL('../../storage.rules', import.meta.url);
const PROJECT_ID = 'demo-runiac-feed';
const PNG_BYTES = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const STAGING_PATH = 'avatar-staging/alice/upload-001.png';
const STAGING_METADATA = {
  contentType: 'image/png',
  customMetadata: { ownerUid: 'alice' },
};
const AVATAR_PATH = 'avatars/0123456789abcdef0123456789abcdef.png';

let testEnv;

function storageFor(uid) {
  return testEnv.authenticatedContext(uid).storage();
}

async function seedObject(path, metadata = STAGING_METADATA) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), path), PNG_BYTES, metadata);
  });
}

describe('Avatar Storage Rules', () => {
  before(async () => {
    assertFeedEmulatorContract();
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      storage: {
        host: '127.0.0.1',
        port: 9199,
        rules: readFileSync(RULES_PATH, 'utf8'),
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearStorage();
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  it('allows an owner to create a valid staged avatar PNG', async () => {
    const target = ref(storageFor('alice'), STAGING_PATH);

    await assertSucceeds(uploadBytes(target, PNG_BYTES, STAGING_METADATA));
  });

  it('denies a different user from creating an owner staged avatar PNG', async () => {
    const target = ref(storageFor('bob'), STAGING_PATH);

    await assertFails(uploadBytes(target, PNG_BYTES, STAGING_METADATA));
  });

  it('denies an unauthenticated staged avatar upload', async () => {
    const anon = testEnv.unauthenticatedContext().storage();

    await assertFails(uploadBytes(ref(anon, STAGING_PATH), PNG_BYTES, STAGING_METADATA));
  });

  it('denies an oversized staged avatar upload', async () => {
    const oversized = new Uint8Array(1024 * 1024 + 1);
    oversized.set(PNG_BYTES);

    await assertFails(uploadBytes(ref(storageFor('alice'), STAGING_PATH), oversized, STAGING_METADATA));
  });

  it('denies an empty staged avatar upload', async () => {
    await assertFails(uploadBytes(ref(storageFor('alice'), STAGING_PATH), new Uint8Array(), STAGING_METADATA));
  });

  it('denies a wrong content type for the staged avatar upload', async () => {
    await assertFails(
      uploadBytes(ref(storageFor('alice'), STAGING_PATH), PNG_BYTES, {
        ...STAGING_METADATA,
        contentType: 'image/jpeg',
      }),
    );
  });

  it('denies a non-png filename for the staged avatar upload', async () => {
    await assertFails(
      uploadBytes(ref(storageFor('alice'), 'avatar-staging/alice/upload-001.jpg'), PNG_BYTES, STAGING_METADATA),
    );
  });

  it('denies wrong or extra metadata for the staged avatar upload', async () => {
    await assertFails(
      uploadBytes(ref(storageFor('alice'), STAGING_PATH), PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { ownerUid: 'bob' },
      }),
    );
    await assertFails(
      uploadBytes(ref(storageFor('alice'), STAGING_PATH), PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: {},
      }),
    );
    await assertFails(
      uploadBytes(ref(storageFor('alice'), STAGING_PATH), PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { ownerUid: 'alice', extra: 'x' },
      }),
    );
  });

  it('allows the owner to read and delete their own staged avatar object', async () => {
    await seedObject(STAGING_PATH);

    await assertSucceeds(getBytes(ref(storageFor('alice'), STAGING_PATH)));
    await assertSucceeds(deleteObject(ref(storageFor('alice'), STAGING_PATH)));
  });

  it('denies a non-owner from reading or deleting a staged avatar object', async () => {
    await seedObject(STAGING_PATH);

    await assertFails(getBytes(ref(storageFor('bob'), STAGING_PATH)));
    await assertFails(deleteObject(ref(storageFor('bob'), STAGING_PATH)));
    await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), STAGING_PATH)));
  });

  it('denies every update to a staged avatar object after creation', async () => {
    await seedObject(STAGING_PATH);

    await assertFails(
      updateMetadata(ref(storageFor('alice'), STAGING_PATH), {
        customMetadata: { ownerUid: 'alice', extra: 'x' },
      }),
    );
  });

  it('denies every client read and write under avatars/, including the owner', async () => {
    await seedObject(AVATAR_PATH, { contentType: 'image/png' });

    await assertFails(getBytes(ref(storageFor('alice'), AVATAR_PATH)));
    await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), AVATAR_PATH)));
    await assertFails(uploadBytes(ref(storageFor('alice'), AVATAR_PATH), PNG_BYTES, { contentType: 'image/png' }));
    await assertFails(deleteObject(ref(storageFor('alice'), AVATAR_PATH)));
  });
});
