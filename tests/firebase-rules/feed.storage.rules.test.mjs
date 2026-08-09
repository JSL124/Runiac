import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  deleteObject,
  getBytes,
  ref,
  updateMetadata,
  uploadBytes,
} from 'firebase/storage';

import { assertFeedEmulatorContract } from './feed.emulator.guard.mjs';

const FIREBASE_CONFIG_PATH = new URL('../../firebase.json', import.meta.url);
const RULES_PATH = new URL('../../storage.rules', import.meta.url);
const GUARD_PATH = new URL('./feed.emulator.guard.mjs', import.meta.url);
const PROJECT_ID = 'demo-runiac-feed';
const PNG_BYTES = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const STAGING_PATH = 'feed-thumbnail-staging/alice/activity-001/upload-001.png';
const FINAL_PATH = 'feed-thumbnails/alice/activity-001/route-preview.png';
const STAGING_METADATA = {
  contentType: 'image/png',
  customMetadata: {
    ownerUid: 'alice',
    activityId: 'activity-001',
    uploadId: 'upload-001.png',
  },
};
const VALID_GUARD_ENV = Object.freeze({
  GCLOUD_PROJECT: PROJECT_ID,
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
  FUNCTIONS_EMULATOR_HOST: '127.0.0.1:5001',
  FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:9199',
});

let testEnv;

describe('Feed Storage emulator configuration', () => {
  it('requires an explicit Storage Rules file and loopback emulator port', () => {
    const firebaseConfig = JSON.parse(readFileSync(FIREBASE_CONFIG_PATH, 'utf8'));

    assert.equal(firebaseConfig.storage?.rules, 'storage.rules');
    assert.equal(firebaseConfig.emulators?.storage?.host, '127.0.0.1');
    assert.equal(firebaseConfig.emulators?.storage?.port, 9199);
  });
});

function storageFor(uid) {
  return testEnv.authenticatedContext(uid).storage();
}

function runGuard(env) {
  return spawnSync(process.execPath, [GUARD_PATH.pathname], {
    encoding: 'utf8',
    env,
  });
}

async function seedObject(path) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), path), PNG_BYTES, STAGING_METADATA);
  });
}

describe('Feed emulator guard', () => {
  it('accepts only the explicit demo project and all four loopback hosts', () => {
    const result = runGuard(VALID_GUARD_ENV);

    assert.equal(result.status, 0, result.stderr);
  });

  it('rejects an unapproved project before any fixture can mutate', () => {
    const result = runGuard({ ...VALID_GUARD_ENV, GCLOUD_PROJECT: 'runiac-fypp' });

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /GCLOUD_PROJECT/);
  });

  it('rejects a missing project before any fixture can mutate', () => {
    const env = { ...VALID_GUARD_ENV };
    delete env.GCLOUD_PROJECT;

    const result = runGuard(env);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /GCLOUD_PROJECT/);
  });

  for (const [name, invalidValue] of [
    ['FIREBASE_AUTH_EMULATOR_HOST', undefined],
    ['FIREBASE_AUTH_EMULATOR_HOST', '127.0.0.1:19099'],
    ['FIRESTORE_EMULATOR_HOST', undefined],
    ['FIRESTORE_EMULATOR_HOST', '127.0.0.1:18080'],
    ['FUNCTIONS_EMULATOR_HOST', undefined],
    ['FUNCTIONS_EMULATOR_HOST', '127.0.0.1:15001'],
    ['FIREBASE_STORAGE_EMULATOR_HOST', undefined],
    ['FIREBASE_STORAGE_EMULATOR_HOST', '127.0.0.1:19199'],
    ['FIREBASE_STORAGE_EMULATOR_HOST', 'invalid-host'],
  ]) {
    it(`rejects a missing or mismatched ${name} before any fixture can mutate`, () => {
      const env = { ...VALID_GUARD_ENV };
      if (invalidValue === undefined) {
        delete env[name];
      } else {
        env[name] = invalidValue;
      }

      const result = runGuard(env);

      assert.notEqual(result.status, 0);
      assert.match(result.stderr, new RegExp(name));
    });
  }
});

describe('Feed thumbnail Storage Rules', () => {
  before(async () => {
    assertFeedEmulatorContract();
    const rules = readFileSync(RULES_PATH, 'utf8');
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      storage: { host: '127.0.0.1', port: 9199, rules },
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

  it('allows an owner to create a valid staging PNG', async () => {
    const target = ref(storageFor('alice'), STAGING_PATH);

    await assertSucceeds(uploadBytes(target, PNG_BYTES, STAGING_METADATA));
  });

  it('denies a different user from creating an owner staging PNG', async () => {
    const target = ref(storageFor('bob'), STAGING_PATH);

    await assertFails(uploadBytes(target, PNG_BYTES, STAGING_METADATA));
  });

  it('allows an owner to read a staging PNG', async () => {
    await seedObject(STAGING_PATH);

    await assertSucceeds(getBytes(ref(storageFor('alice'), STAGING_PATH)));
  });

  it('allows an owner to delete a staging PNG', async () => {
    await seedObject(STAGING_PATH);

    await assertSucceeds(deleteObject(ref(storageFor('alice'), STAGING_PATH)));
  });

  it('denies a different user, a friend, and an anonymous client from staging access', async () => {
    await seedObject(STAGING_PATH);

    await assertFails(getBytes(ref(storageFor('bob'), STAGING_PATH)));
    await assertFails(getBytes(ref(storageFor('friend'), STAGING_PATH)));
    await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), STAGING_PATH)));
  });

  it('denies every staging update after creation', async () => {
    await seedObject(STAGING_PATH);

    await assertFails(
      updateMetadata(ref(storageFor('alice'), STAGING_PATH), {
        customMetadata: { ...STAGING_METADATA.customMetadata, activityId: 'activity-002' },
      }),
    );
  });

  it('denies invalid staging paths, metadata, and content types', async () => {
    await assertFails(uploadBytes(ref(storageFor('alice'), 'feed-thumbnail-staging/alice/activity-001/upload-001.jpg'), PNG_BYTES, STAGING_METADATA));
    await assertFails(uploadBytes(ref(storageFor('alice'), STAGING_PATH), PNG_BYTES, { ...STAGING_METADATA, contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(storageFor('alice'), STAGING_PATH), PNG_BYTES, { ...STAGING_METADATA, customMetadata: { ...STAGING_METADATA.customMetadata, ownerUid: 'bob' } }));
  });

  it('denies empty and oversized staging data', async () => {
    await assertFails(uploadBytes(ref(storageFor('alice'), STAGING_PATH), new Uint8Array(), STAGING_METADATA));
    await assertFails(uploadBytes(ref(storageFor('alice'), STAGING_PATH), new Uint8Array(1_048_577), STAGING_METADATA));
  });

  it('denies every client write to the final thumbnail object', async () => {
    await assertFails(uploadBytes(ref(storageFor('alice'), FINAL_PATH), PNG_BYTES, STAGING_METADATA));
  });

  it('allows only the final thumbnail owner to read directly', async () => {
    await seedObject(FINAL_PATH);

    await assertSucceeds(getBytes(ref(storageFor('alice'), FINAL_PATH)));
    await assertFails(getBytes(ref(storageFor('friend'), FINAL_PATH)));
  });
});
