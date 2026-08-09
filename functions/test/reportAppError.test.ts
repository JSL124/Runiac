import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  firebaseReportAppErrorPort,
  reportAppErrorForCallable,
  type ErrorGroupDocument,
  type ExistingErrorGroup,
  type ReportAppErrorPort,
} from "../src/errors/reportAppError.js";
import { deriveSeverity, sanitizeFrames, sanitizeMessage } from "../src/errors/sanitize.js";

const PROJECT_ID = "runiac-functions-test";

const BASE_NOW = new Date("2026-07-19T12:00:00.000Z");

describe("reportAppError callable", () => {
  it("rejects unauthenticated requests", async () => {
    const port = fixture();
    await assert.rejects(
      reportAppErrorForCallable({ data: payload() }, port),
      hasCode("unauthenticated"),
    );
    assert.equal(port.groups.size, 0);
  });

  it("rejects a non-object payload", async () => {
    const port = fixture();
    await assert.rejects(
      reportAppErrorForCallable(authed("uid-a", "not an object"), port),
      hasCode("invalid-argument"),
    );
  });

  it("rejects extra keys in the payload", async () => {
    const port = fixture();
    await assert.rejects(
      reportAppErrorForCallable(authed("uid-a", payload({ extra: "nope" })), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.groups.size, 0);
  });

  for (const forbiddenKey of ["severity", "fingerprint", "occurrences", "affectedUserCount", "status"]) {
    it(`rejects a payload carrying a server-owned "${forbiddenKey}" field`, async () => {
      const port = fixture();
      await assert.rejects(
        reportAppErrorForCallable(authed("uid-a", payload({ [forbiddenKey]: "anything" })), port),
        hasCode("invalid-argument"),
      );
      assert.equal(port.groups.size, 0);
    });
  }

  it("rejects an invalid platform", async () => {
    const port = fixture();
    await assert.rejects(
      reportAppErrorForCallable(authed("uid-a", payload({ platform: "windows" })), port),
      hasCode("invalid-argument"),
    );
  });

  it("rejects a screen name outside the allowlist pattern", async () => {
    const port = fixture();
    await assert.rejects(
      reportAppErrorForCallable(authed("uid-a", payload({ screen: "Run Screen <script>" })), port),
      hasCode("invalid-argument"),
    );
  });

  it("defaults screen to \"unknown\" when omitted", async () => {
    const port = fixture();
    const result = await reportAppErrorForCallable(authed("uid-a", payload({ screen: undefined })), port);
    assert.equal(port.groups.get(result.groupId)?.screen, "unknown");
  });

  it("treats an explicit screen: null exactly like omitted and ingests successfully as \"unknown\"", async () => {
    const port = fixture();
    const result = await reportAppErrorForCallable(authed("uid-a", payload({ screen: null })), port);
    assert.equal(port.groups.get(result.groupId)?.screen, "unknown");
  });

  it("groups identical errors from two different uids into one group with occurrences 2 and affectedUserCount 2", async () => {
    const port = fixture();
    const r1 = await reportAppErrorForCallable(authed("uid-a", payload()), port);
    const r2 = await reportAppErrorForCallable(authed("uid-b", payload()), port);
    assert.equal(r1.groupId, r2.groupId);
    const group = port.groups.get(r1.groupId)!;
    assert.equal(group.occurrences, 2);
    assert.equal(group.affectedUserCount, 2);
  });

  it("counts repeat reports from the same uid as a single affected user", async () => {
    const port = fixture();
    const r1 = await reportAppErrorForCallable(authed("uid-a", payload()), port);
    await reportAppErrorForCallable(authed("uid-a", payload()), port);
    const group = port.groups.get(r1.groupId)!;
    assert.equal(group.occurrences, 2);
    assert.equal(group.affectedUserCount, 1);
  });

  it("preserves firstSeenAt, status, and note on a repeat ingest", async () => {
    const port = fixture();
    const first = await reportAppErrorForCallable(authed("uid-a", payload()), port);
    const firstDoc = port.groups.get(first.groupId)!;
    port.groups.set(first.groupId, { ...firstDoc, status: "resolved", note: "known cause" });

    port.setNow(new Date(BASE_NOW.getTime() + 60_000));
    const second = await reportAppErrorForCallable(authed("uid-b", payload()), port);

    assert.equal(second.groupId, first.groupId);
    const group = port.groups.get(first.groupId)!;
    assert.equal(group.status, "resolved");
    assert.equal(group.note, "known cause");
    assert.equal(group.firstSeenAt, firstDoc.firstSeenAt);
    assert.equal(group.occurrences, 2);
    assert.equal(group.affectedUserCount, 2);
  });

  it("throws resource-exhausted on the 31st report within the rate limit window", async () => {
    const port = fixture();
    for (let i = 0; i < 30; i += 1) {
      await reportAppErrorForCallable(authed("uid-a", payload({ screen: `Screen${i}` })), port);
    }
    await assert.rejects(
      reportAppErrorForCallable(authed("uid-a", payload({ screen: "ScreenOverflow" })), port),
      hasCode("resource-exhausted"),
    );
  });

  it("does not rate limit across different uids", async () => {
    const port = fixture();
    for (let i = 0; i < 30; i += 1) {
      await reportAppErrorForCallable(authed("uid-a", payload({ screen: `Screen${i}` })), port);
    }
    const result = await reportAppErrorForCallable(authed("uid-b", payload()), port);
    assert.ok(result.groupId.length > 0);
  });

  it("escalates severity from high to critical once affectedUserCount reaches 10", async () => {
    const port = fixture();
    let lastGroupId = "";
    for (let i = 0; i < 9; i += 1) {
      const result = await reportAppErrorForCallable(authed(`uid-${i}`, payload({ fatal: true })), port);
      lastGroupId = result.groupId;
    }
    assert.equal(port.groups.get(lastGroupId)?.affectedUserCount, 9);
    assert.equal(port.groups.get(lastGroupId)?.severity, "high");

    const result10 = await reportAppErrorForCallable(authed("uid-9", payload({ fatal: true })), port);
    assert.equal(port.groups.get(result10.groupId)?.affectedUserCount, 10);
    assert.equal(port.groups.get(result10.groupId)?.severity, "critical");
  });

  it("returns the fingerprint as groupId and stores a stackSummary joined from sanitised frames only", async () => {
    const port = fixture();
    const result = await reportAppErrorForCallable(authed("uid-a", payload()), port);
    const group = port.groups.get(result.groupId)!;
    assert.equal(result.groupId.length, 16);
    assert.ok(!group.stackSummary.includes("package:flutter/"));
    assert.ok(group.stackSummary.includes("package:runiac_app/"));
    assert.equal(group.sanitized, true);
  });
});

describe("sanitizeMessage", () => {
  it("redacts an email address, a URL query string, and a 7-digit number", () => {
    const raw =
      "Email jane.doe@example.com failed GET https://api.runiac.app/run?token=abc123 code 1234567 done";
    const result = sanitizeMessage(raw);
    assert.ok(!result.includes("jane.doe@example.com"));
    assert.ok(!result.includes("token=abc123"));
    assert.ok(!result.includes("1234567"));
    assert.equal((result.match(/\[redacted\]/g) ?? []).length, 3);
  });

  it("caps the sanitised message to 200 characters", () => {
    const raw = Array.from({ length: 100 }, () => "hello").join(" ");
    assert.equal(sanitizeMessage(raw).length, 200);
  });

  it("redacts a 32-character hex hash and a 40-character mixed base64-ish token", () => {
    const hex32 = "0123456789abcdef0123456789abcdef";
    const token40 = "aB3".repeat(14).slice(0, 40);
    const raw = `Crash hash ${hex32} with token ${token40} seen`;
    const result = sanitizeMessage(raw);
    assert.ok(!result.includes(hex32));
    assert.ok(!result.includes(token40));
    assert.equal((result.match(/\[redacted\]/g) ?? []).length, 2);
  });

  it("does not redact ordinary snake_case/PascalCase identifiers", () => {
    const raw = "RunSummaryController failed inside run_summary_controller during save";
    const result = sanitizeMessage(raw);
    assert.equal(result, raw);
  });

  it("redacts a latitude/longitude pair", () => {
    // A decimal point splits a coordinate into digit runs of 1-4, so the
    // 5+-digit rule never touched it and precise GPS positions were stored in
    // reports flagged `sanitized: true`.
    for (const coordinate of [
      "1.3521, 103.8198",
      "1.352100,103.819800",
      "(-33.86880; 151.20930)",
    ]) {
      const result = sanitizeMessage(`Route snap failed near ${coordinate} on retry`);
      assert.ok(
        !/\d\.\d{3}/.test(result),
        `${coordinate} survived sanitisation as ${result}`,
      );
      assert.ok(result.includes("[redacted]"));
    }
  });

  it("redacts a labelled coordinate, including a lone one", () => {
    // A single labelled value carries a position just as much as a pair does,
    // and the pair pattern cannot see one that arrives on its own.
    for (const raw of [
      "Snap failed latitude=1.3521 longitude=103.8198 retrying",
      "Snap failed at lat: 1.35210 only",
      "geo lng=103.81980 recorded",
    ]) {
      const result = sanitizeMessage(raw);
      assert.ok(
        !/\d\.\d{3}/.test(result),
        `${raw} survived sanitisation as ${result}`,
      );
    }
  });

  it("leaves an ordinary number pair alone", () => {
    const raw = "Pace drifted from 5.2 to 6.1 over segment 3";
    assert.equal(sanitizeMessage(raw), raw);
  });
});

describe("sanitizeFrames", () => {
  it("drops SDK/plugin frames and keeps only package:runiac_app/ frames, redacted", () => {
    const frames = [
      "package:flutter/src/widgets/framework.dart 300:5",
      "dart:async/zone.dart 10:2",
      "package:runiac_app/features/run/run_screen.dart 42:5",
      "package:cloud_firestore_platform_interface/foo.dart 1:1",
      "package:runiac_app/core/util.dart contact test@example.com",
    ];
    const result = sanitizeFrames(frames);
    assert.deepEqual(result, [
      "package:runiac_app/features/run/run_screen.dart 42:5",
      "package:runiac_app/core/util.dart contact [redacted]",
    ]);
  });

  it("caps retained frames at 8", () => {
    const frames = Array.from({ length: 10 }, (_, i) => `package:runiac_app/frame_${i}.dart`);
    const result = sanitizeFrames(frames);
    assert.equal(result.length, 8);
    assert.deepEqual(result, frames.slice(0, 8));
  });

  it("preserves a realistic Dart stack frame's class, method, and file names intact", () => {
    const frame =
      "#0 RunSummaryController.save (package:runiac_app/features/run/run_summary_controller.dart:42:15)";
    const result = sanitizeFrames([frame]);
    assert.deepEqual(result, [frame]);
  });
});

describe("deriveSeverity", () => {
  it("follows the fatal/occurrences/affectedUserCount ladder", () => {
    assert.equal(deriveSeverity({ fatal: false, occurrences: 1, affectedUserCount: 1 }), "low");
    assert.equal(deriveSeverity({ fatal: false, occurrences: 50, affectedUserCount: 1 }), "medium");
    assert.equal(deriveSeverity({ fatal: true, occurrences: 1, affectedUserCount: 1 }), "high");
    assert.equal(deriveSeverity({ fatal: true, occurrences: 1, affectedUserCount: 10 }), "critical");
  });
});

describe("firebaseReportAppErrorPort rate limit ledger (real Firestore)", () => {
  let firestore: Firestore;

  before(() => {
    if (getApps().length === 0) {
      initializeApp({ projectId: PROJECT_ID });
    }
    firestore = getFirestore();
  });

  it("prunes rate-limit events older than the window and retains in-window events", async () => {
    const uid = `rate-limit-prune-${Date.now()}`;
    const port = firebaseReportAppErrorPort(firestore);
    const windowMs = 10 * 60 * 1000;
    const now = new Date("2026-07-19T12:00:00.000Z");
    const staleAt = new Date(now.getTime() - windowMs - 60_000); // well past the window
    const freshAt = new Date(now.getTime() - 60_000); // still inside the window

    // Record a stale event "in the past" first.
    await port.recordReportEvent(uid, staleAt);
    // Recording a new event at `now` sweeps its own uid's stale backlog: the
    // cutoff (now - windowMs) is well after staleAt, so staleAt is deleted.
    await port.recordReportEvent(uid, now);

    const since = new Date(now.getTime() - windowMs);
    assert.equal(await port.recentReportCount(uid, since), 1);

    // A genuinely in-window event recorded afterwards must survive pruning.
    await port.recordReportEvent(uid, freshAt);
    assert.equal(await port.recentReportCount(uid, since), 2);
  });
});

function payload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const base: Record<string, unknown> = {
    errorType: "NullPointerException",
    message: "Something broke",
    stackFrames: [
      "package:flutter/src/widgets/framework.dart 300:5",
      "package:runiac_app/features/run/run_screen.dart 42:5",
      "package:runiac_app/core/util.dart 5:1",
    ],
    screen: "RunScreen",
    appVersion: "1.2.3",
    osVersion: "iOS 17.2",
    platform: "ios",
    fatal: false,
  };
  const merged: Record<string, unknown> = { ...base, ...overrides };
  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) {
      delete merged[key];
    }
  }
  return merged;
}

function authed(uid: string, data: unknown): { readonly auth: { readonly uid: string }; readonly data: unknown } {
  return { auth: { uid }, data };
}

function hasCode(code: string): (error: unknown) => boolean {
  return (error: unknown) => error instanceof HttpsError && error.code === code;
}

class FakeReportAppErrorPort implements ReportAppErrorPort {
  readonly groups = new Map<string, ErrorGroupDocument>();
  private readonly reporters = new Map<string, Set<string>>();
  private readonly rateLimitEvents: Array<{ readonly uid: string; readonly at: Date }> = [];
  private currentNow = BASE_NOW;

  setNow(next: Date): void {
    this.currentNow = next;
  }

  now(): Date {
    return this.currentNow;
  }

  serverTimestamp(): unknown {
    return this.currentNow;
  }

  async recentReportCount(uid: string, since: Date): Promise<number> {
    return this.rateLimitEvents.filter((event) => event.uid === uid && event.at.getTime() > since.getTime())
      .length;
  }

  async recordReportEvent(uid: string, at: Date): Promise<void> {
    this.rateLimitEvents.push({ uid, at });
  }

  async ingestErrorGroup(input: {
    readonly fingerprint: string;
    readonly uid: string;
    readonly buildDocument: (
      existing: ExistingErrorGroup | undefined,
      isNewReporter: boolean,
    ) => ErrorGroupDocument;
  }): Promise<void> {
    const existing = this.groups.get(input.fingerprint);
    const reporterSet = this.reporters.get(input.fingerprint) ?? new Set<string>();
    const isNewReporter = !reporterSet.has(input.uid);
    const document = input.buildDocument(existing, isNewReporter);
    this.groups.set(input.fingerprint, document);
    reporterSet.add(input.uid);
    this.reporters.set(input.fingerprint, reporterSet);
  }
}

function fixture(): FakeReportAppErrorPort {
  return new FakeReportAppErrorPort();
}
