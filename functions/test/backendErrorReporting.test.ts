import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  firebaseReportBackendErrorPort,
  reportBackendError,
  type ReportBackendErrorPort,
} from "../src/errors/reportBackendError.js";
import type {
  ErrorGroupDocument,
  ExistingErrorGroup,
  ErrorGroupStore,
  IngestErrorGroupInput,
} from "../src/errors/errorGroupStore.js";
import {
  withCallableErrorReporting,
  withScheduledErrorReporting,
  withTriggerErrorReporting,
} from "../src/errors/withErrorReporting.js";
import { sanitizeFrames } from "../src/errors/sanitize.js";
import { loadFeatureAccessConfig, loadProgressionConfig } from "../src/config/configLoader.js";

const PROJECT_ID = "runiac-functions-test";

// IMPORTANT: this describe block must be the first thing that runs in this
// file/process. It proves the fix for the defect where reportBackendError's
// default parameter (`port = firebaseReportBackendErrorPort()`) was resolved
// at call time, BEFORE the function body's try block — so
// firebaseReportBackendErrorPort()'s getFirestore() throwing "The default
// Firebase app does not exist" (which happens whenever initializeApp() has
// not run yet, exactly the state configLoader.ts can be imported into)
// escaped uncaught and replaced the caller's original error. No other
// describe block in this file may call initializeApp() before this one runs,
// so it is placed immediately after the imports/constants, and none of the
// other tests below run node:test with concurrency, matching this project's
// `--test-concurrency=1` scripts.
describe("reportBackendError / withCallableErrorReporting with NO Firebase app initialised yet", () => {
  it("reportBackendError returns normally (does not throw) when port construction itself fails", async () => {
    assert.equal(getApps().length, 0, "this test must run before any Firebase app is initialised in this process");

    await assert.doesNotReject(
      reportBackendError({
        functionName: "noAppTest-directCall",
        error: new Error("no default app yet"),
        fatal: true,
      }),
      // No port argument at all: this exercises the exact call shape every
      // production call site uses (reportBackendError({...}) with no port),
      // so the default-parameter defect would have surfaced here.
    );
  });

  it("a wrapped callable whose reporter fails at port-construction time still throws its ORIGINAL error unchanged", async () => {
    assert.equal(getApps().length, 0, "this test must still run before any Firebase app is initialised in this process");

    const originalError = new TypeError("original callable failure, no app yet");
    const wrapped = withCallableErrorReporting("noAppTest-wrappedCallable", async (_request: CallableLikeRequest) => {
      throw originalError;
    });

    await assert.rejects(
      wrapped({ data: {} }),
      (error: unknown) =>
        error === originalError &&
        error instanceof TypeError &&
        error.message === "original callable failure, no app yet",
    );
  });
});

describe("reportBackendError (fake store, no emulator required)", () => {
  it("writes a functions-sourced document with the backend field mapping", async () => {
    const store = new FakeErrorGroupStore();
    const clock = { now: new Date("2026-07-19T12:00:00.000Z") };
    const port = fakePort(store, clock);

    await reportBackendError(
      { functionName: "unitTest-fieldMapping", error: new TypeError("boom"), uid: "uid-a", fatal: true },
      port,
    );

    const doc = onlyDocument(store);
    assert.equal(doc.source, "functions");
    assert.equal(doc.screen, "unitTest-fieldMapping");
    assert.equal(doc.os, "nodejs22");
    assert.equal(doc.platform, "functions");
    assert.equal(doc.appVersion, process.env["K_REVISION"] ?? "unknown");
    assert.equal(doc.errorType, "TypeError");
    assert.equal(doc.sanitized, true);
    assert.equal(doc.severity, "high");
  });

  it("derives a low severity for a non-fatal single occurrence", async () => {
    const store = new FakeErrorGroupStore();
    const port = fakePort(store, { now: new Date("2026-07-19T12:00:00.000Z") });

    await reportBackendError(
      { functionName: "unitTest-nonFatal", error: new Error("degraded"), fatal: false },
      port,
    );

    assert.equal(onlyDocument(store).severity, "low");
  });

  it("only writes a reporters marker and increments affectedUserCount when a uid is present", async () => {
    const store = new FakeErrorGroupStore();
    const port = fakePort(store, { now: new Date("2026-07-19T12:00:00.000Z") });

    await reportBackendError(
      { functionName: "unitTest-noUid", error: new Error("no uid here"), fatal: true },
      port,
    );
    const noUidDoc = onlyDocument(store);
    assert.equal(noUidDoc.affectedUserCount, 0);
    assert.equal(store.reporterUidsByFingerprint.size, 0);

    await reportBackendError(
      { functionName: "unitTest-withUid", error: new Error("has a uid"), uid: "uid-b", fatal: true },
      port,
    );
    const fingerprintWithUid = [...store.documents.keys()].find(
      (fp) => store.documents.get(fp)?.screen === "unitTest-withUid",
    );
    assert.ok(fingerprintWithUid !== undefined);
    assert.equal(store.documents.get(fingerprintWithUid)?.affectedUserCount, 1);
    assert.ok(store.reporterUidsByFingerprint.get(fingerprintWithUid)?.has("uid-b"));
  });

  it("suppresses an identical fingerprint within 60 seconds and reports again once the window has passed", async () => {
    const store = new FakeErrorGroupStore();
    const clock = { now: new Date("2026-07-19T12:00:00.000Z") };
    const port = fakePort(store, clock);
    const input = {
      functionName: "unitTest-suppression",
      error: new Error("repeated fault"),
      fatal: true,
    } as const;

    await reportBackendError(input, port);
    assert.equal(onlyDocument(store).occurrences, 1);

    clock.now = new Date(clock.now.getTime() + 30_000); // still inside the 60s window
    await reportBackendError(input, port);
    assert.equal(onlyDocument(store).occurrences, 1, "second call within the window must be suppressed");

    clock.now = new Date(clock.now.getTime() + 31_000); // now 61s after the first report
    await reportBackendError(input, port);
    assert.equal(onlyDocument(store).occurrences, 2, "a call after the window must report again");
  });

  it("never throws even when the underlying store rejects", async () => {
    const store = new FakeErrorGroupStore();
    store.failOnNextIngest();
    const port = fakePort(store, { now: new Date("2026-07-19T12:00:00.000Z") });

    await assert.doesNotReject(
      reportBackendError({ functionName: "unitTest-forcedFailure", error: new Error("x"), fatal: true }, port),
    );
    assert.equal(store.documents.size, 0, "the forced failure means no document was actually persisted");
  });
});

describe("sanitizeFrames (functions-bundle frame acceptance)", () => {
  it("retains a Node frame from the compiled functions bundle", () => {
    const frames = [
      "at completeRunForCallable (/workspace/functions/lib/src/run/completeRun.js:56:10)",
      "at Module._compile (node:internal/modules/cjs/loader:1105:14)",
      "at Layer.handle (/workspace/functions/node_modules/express/lib/router/layer.js:95:5)",
    ];
    const result = sanitizeFrames(frames);
    assert.deepEqual(result, [
      "at completeRunForCallable (/workspace/functions/lib/src/run/completeRun.js:56:10)",
    ]);
  });

  it("still keeps mobile package:runiac_app/ frames and still drops SDK frames", () => {
    const frames = [
      "package:flutter/src/widgets/framework.dart 300:5",
      "package:runiac_app/features/run/run_screen.dart 42:5",
    ];
    assert.deepEqual(sanitizeFrames(frames), ["package:runiac_app/features/run/run_screen.dart 42:5"]);
  });
});

describe(
  "withCallableErrorReporting / withScheduledErrorReporting / withTriggerErrorReporting (real Firestore)",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: PROJECT_ID });
      }
      firestore = getFirestore();
    });

    beforeEach(async () => {
      await firestore.recursiveDelete(firestore.collection("errorGroups"));
    });

    it("reports a TypeError thrown inside a callable and rethrows it unchanged", async () => {
      const functionName = "wrapperTest-typeErrorCallable";
      const wrapped = withCallableErrorReporting(functionName, async (_request: CallableLikeRequest) => {
        throw new TypeError("boom-typeerror");
      });

      await assert.rejects(
        wrapped({ data: {} }),
        (error: unknown) => error instanceof TypeError && error.message === "boom-typeerror",
      );

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 1);
      assert.equal(snapshot.docs[0]?.get("source"), "functions");
    });

    it("does NOT report an HttpsError(invalid-argument) but still rethrows it unchanged", async () => {
      const functionName = "wrapperTest-invalidArgument";
      const wrapped = withCallableErrorReporting(functionName, async (_request: CallableLikeRequest) => {
        throw new HttpsError("invalid-argument", "bad payload");
      });

      await assert.rejects(
        wrapped({ data: {} }),
        (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument",
      );

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 0);
    });

    it("DOES report an HttpsError(internal) and rethrows it unchanged", async () => {
      const functionName = "wrapperTest-internalError";
      const wrapped = withCallableErrorReporting(functionName, async (_request: CallableLikeRequest) => {
        throw new HttpsError("internal", "backend blew up");
      });

      await assert.rejects(
        wrapped({ data: {} }),
        (error: unknown) => error instanceof HttpsError && error.code === "internal",
      );

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 1);
    });

    it("creates a reporters/{uid} marker and affectedUserCount 1 for a callable failure with a uid", async () => {
      const functionName = "wrapperTest-withUidMarker";
      const wrapped = withCallableErrorReporting(functionName, async (_request: CallableLikeRequest) => {
        throw new Error("callable fault with a caller");
      });

      await assert.rejects(wrapped({ auth: { uid: "caller-uid-1" }, data: {} }));

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 1);
      const groupDoc = snapshot.docs[0];
      assert.ok(groupDoc !== undefined);
      assert.equal(groupDoc.get("affectedUserCount"), 1);
      const reporterDoc = await groupDoc.ref.collection("reporters").doc("caller-uid-1").get();
      assert.equal(reporterDoc.exists, true);
    });

    it("reports a scheduled-job failure with affectedUserCount 0 and no reporters marker", async () => {
      const functionName = "wrapperTest-scheduledFailure";
      const wrapped = withScheduledErrorReporting(functionName, async () => {
        throw new Error("scheduled job fault");
      });

      await assert.rejects(wrapped(undefined));

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 1);
      const groupDoc = snapshot.docs[0];
      assert.ok(groupDoc !== undefined);
      assert.equal(groupDoc.get("affectedUserCount"), 0);
      const reportersSnapshot = await groupDoc.ref.collection("reporters").get();
      assert.equal(reportersSnapshot.empty, true);
    });

    it("reports a Firestore trigger failure with affectedUserCount 0 and no reporters marker", async () => {
      const functionName = "wrapperTest-triggerFailure";
      const wrapped = withTriggerErrorReporting(functionName, async () => {
        throw new Error("trigger fault");
      });

      await assert.rejects(wrapped(undefined));

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 1);
      assert.equal(snapshot.docs[0]?.get("affectedUserCount"), 0);
    });

    it("reports the same fingerprint only once across two calls within the suppression window", async () => {
      const functionName = "wrapperTest-suppressedDuplicate";
      const wrapped = withCallableErrorReporting(functionName, async (_request: CallableLikeRequest) => {
        throw new Error("duplicate fault");
      });

      await assert.rejects(wrapped({ data: {} }));
      await assert.rejects(wrapped({ data: {} }));

      const snapshot = await firestore.collection("errorGroups").where("screen", "==", functionName).get();
      assert.equal(snapshot.size, 1);
      assert.equal(snapshot.docs[0]?.get("occurrences"), 1);
    });

    it("a forced failure inside reportBackendError does not change what the wrapped callable throws", async () => {
      // Exercises the real default port (real Firestore) with a uid far
      // past Firestore's document-id length limit, forcing the reporters/{uid}
      // ingest write itself to fail. The wrapper's own try/catch around
      // reportIfReportable must still leave the ORIGINAL callable error
      // completely unaffected — reportBackendError must swallow its own
      // failure rather than let it surface in place of the real fault.
      const functionName = "wrapperTest-reportingFailureIsolated";
      const originalError = new Error("original callable failure");
      const oversizedUid = "u".repeat(2000);
      const wrapped = withCallableErrorReporting(functionName, async (_request: CallableLikeRequest) => {
        throw originalError;
      });

      await assert.rejects(
        wrapped({ auth: { uid: oversizedUid }, data: {} }),
        (error: unknown) => error === originalError,
      );
    });
  },
);

describe(
  "configLoader backend error reporting (real Firestore)",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: PROJECT_ID });
      }
      firestore = getFirestore();
    });

    beforeEach(async () => {
      await firestore.recursiveDelete(firestore.collection("errorGroups"));
      await firestore.doc("config/progression").delete();
      await firestore.doc("config/featureAccess").delete();
    });

    it("reports a non-fatal source:functions group when config/progression fails validation", async () => {
      await firestore.doc("config/progression").set({ premiumEarnsXp: "false" });

      await loadProgressionConfig(firestore);

      const snapshot = await firestore
        .collection("errorGroups")
        .where("screen", "==", "loadProgressionConfig")
        .get();
      assert.equal(snapshot.size, 1);
      const doc = snapshot.docs[0];
      assert.ok(doc !== undefined);
      assert.equal(doc.get("source"), "functions");
      assert.equal(doc.get("severity"), "low");
    });

    it("reports nothing when config/featureAccess is simply missing", async () => {
      // No config/featureAccess doc exists after beforeEach's delete: this is
      // the designed default state, not a fault.
      await loadFeatureAccessConfig(firestore);

      const snapshot = await firestore
        .collection("errorGroups")
        .where("screen", "==", "loadFeatureAccessConfig")
        .get();
      assert.equal(snapshot.size, 0);
    });
  },
);

type CallableLikeRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

function fakePort(store: FakeErrorGroupStore, clock: { now: Date }): ReportBackendErrorPort {
  return {
    now: () => clock.now,
    serverTimestamp: () => clock.now,
    store,
  };
}

function onlyDocument(store: FakeErrorGroupStore): ErrorGroupDocument {
  assert.equal(store.documents.size, 1, "expected exactly one persisted document");
  const [document] = store.documents.values();
  assert.ok(document !== undefined);
  return document;
}

class FakeErrorGroupStore implements ErrorGroupStore {
  readonly documents = new Map<string, ErrorGroupDocument>();
  readonly reporterUidsByFingerprint = new Map<string, Set<string>>();
  private forceNextFailure = false;

  failOnNextIngest(): void {
    this.forceNextFailure = true;
  }

  async ingestErrorGroup(input: IngestErrorGroupInput): Promise<void> {
    if (this.forceNextFailure) {
      this.forceNextFailure = false;
      throw new Error("forced ingest failure");
    }
    const existing: ExistingErrorGroup | undefined = this.documents.get(input.fingerprint);
    const reporterSet = this.reporterUidsByFingerprint.get(input.fingerprint) ?? new Set<string>();
    const isNewReporter = input.uid !== undefined && !reporterSet.has(input.uid);
    const document = input.buildDocument(existing, isNewReporter);
    this.documents.set(input.fingerprint, document);
    if (input.uid !== undefined && isNewReporter) {
      reporterSet.add(input.uid);
      this.reporterUidsByFingerprint.set(input.fingerprint, reporterSet);
    }
  }
}

// Referenced only to keep firebaseReportBackendErrorPort's export exercised
// by the type system (the default-port path is covered end-to-end by the
// wrapper describe block above via getFirestore()).
void firebaseReportBackendErrorPort;
