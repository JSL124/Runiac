import { pathToFileURL } from 'node:url';

const EXPECTED_ENVIRONMENT = Object.freeze({
  GCLOUD_PROJECT: 'demo-runiac-feed',
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
  FUNCTIONS_EMULATOR_HOST: '127.0.0.1:5001',
  FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:9199',
});

export function assertFeedEmulatorContract(environment = process.env) {
  const invalidEntries = Object.entries(EXPECTED_ENVIRONMENT).filter(
    ([name, expected]) => environment[name] !== expected,
  );

  if (invalidEntries.length > 0) {
    const details = invalidEntries
      .map(([name, expected]) => `${name} must equal ${expected}`)
      .join('; ');
    throw new Error(`Feed emulator guard rejected the environment: ${details}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    assertFeedEmulatorContract();
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Feed emulator guard failed.');
    process.exitCode = 1;
  }
}
