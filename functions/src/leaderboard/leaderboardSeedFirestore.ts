import { applicationDefault, getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";

export function hasCallableFirebaseCliProperties(
  moduleValue: unknown,
  requiredProperties: readonly string[],
): boolean {
  if (typeof moduleValue !== "object" || moduleValue === null) return false;
  return requiredProperties.every(
    (propertyName) =>
      Reflect.has(moduleValue, propertyName) &&
      typeof Reflect.get(moduleValue, propertyName) === "function",
  );
}

function callFirebaseCliFunction(moduleValue: unknown, propertyName: string): unknown {
  if (typeof moduleValue !== "object" || moduleValue === null) {
    throw new Error(`Firebase CLI module is missing ${propertyName}`);
  }
  const callable = Reflect.get(moduleValue, propertyName);
  if (typeof callable !== "function") {
    throw new Error(`Firebase CLI module has a non-callable ${propertyName}`);
  }
  return Reflect.apply(callable, moduleValue, []);
}

function propertyValue(value: unknown, propertyName: string): unknown {
  if (typeof value !== "object" || value === null || !Reflect.has(value, propertyName)) {
    return undefined;
  }
  return Reflect.get(value, propertyName);
}

export function productionOrEmulatorFirestore(projectId: string): Firestore {
  const isEmulator = process.env["FIRESTORE_EMULATOR_HOST"] !== undefined;
  const appName = `leaderboard-seed:${projectId}`;
  const app = getApps().find((candidate) => candidate.name === appName);
  if (app !== undefined) {
    if (app.options.projectId !== projectId) {
      throw new Error(`Firestore app ${appName} is configured for a different project`);
    }
    return getFirestore(app);
  }
  const initializedApp = initializeApp(
    isEmulator ? { projectId } : { projectId, credential: applicationDefault() },
    appName,
  );
  return getFirestore(initializedApp);
}

export async function configureFirebaseCliApplicationDefault(): Promise<
  () => Promise<void>
> {
  if (process.env["FIRESTORE_EMULATOR_HOST"] !== undefined) {
    return async () => {};
  }
  const require = createRequire(import.meta.url);
  const authModule: unknown = require("firebase-tools/lib/auth.js");
  if (!hasCallableFirebaseCliProperties(authModule, ["getGlobalDefaultAccount"])) {
    throw new Error("Firebase CLI auth module has an incompatible shape");
  }
  const apiModule: unknown = require("firebase-tools/lib/api.js");
  if (!hasCallableFirebaseCliProperties(apiModule, ["clientId", "clientSecret"])) {
    throw new Error("Firebase CLI API module has an incompatible shape");
  }
  const refreshToken = propertyValue(
    propertyValue(callFirebaseCliFunction(authModule, "getGlobalDefaultAccount"), "tokens"),
    "refresh_token",
  );
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    throw new Error("no Firebase CLI login found; run firebase login first");
  }
  const clientId = callFirebaseCliFunction(apiModule, "clientId");
  const clientSecret = callFirebaseCliFunction(apiModule, "clientSecret");
  if (typeof clientId !== "string" || clientId.length === 0 || typeof clientSecret !== "string" || clientSecret.length === 0) {
    throw new Error("Firebase CLI API module returned invalid OAuth credentials");
  }
  const directory = await mkdtemp(join(tmpdir(), "runiac-firebase-adc-"));
  const credentialFile = join(directory, "application_default_credentials.json");
  await writeFile(
    credentialFile,
    JSON.stringify({
      type: "authorized_user",
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
    }),
    { encoding: "utf8", mode: 0o600 },
  );
  const previousCredentialPath = process.env["GOOGLE_APPLICATION_CREDENTIALS"];
  process.env["GOOGLE_APPLICATION_CREDENTIALS"] = credentialFile;
  return async () => {
    if (previousCredentialPath === undefined) {
      delete process.env["GOOGLE_APPLICATION_CREDENTIALS"];
    } else {
      process.env["GOOGLE_APPLICATION_CREDENTIALS"] = previousCredentialPath;
    }
    await rm(directory, { recursive: true, force: true });
  };
}
