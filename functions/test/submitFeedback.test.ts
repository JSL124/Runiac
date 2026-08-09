import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import { submitFeedbackForCallable, type FeedbackRecord, type SubmitFeedbackPort } from "../src/feedback/submitFeedback.js";

const BASE_NOW = new Date("2026-07-19T12:00:00.000Z");

describe("submitFeedback callable", () => {
  it("rejects unauthenticated requests", async () => {
    const port = fixture();
    await assert.rejects(
      submitFeedbackForCallable({ data: { category: "bug", message: "It crashed" } }, port),
      hasCode("unauthenticated"),
    );
    assert.equal(port.records.length, 0);
  });

  it("rejects a non-object payload", async () => {
    const port = fixture();
    await assert.rejects(
      submitFeedbackForCallable(authed("not an object"), port),
      hasCode("invalid-argument"),
    );
  });

  it("rejects extra keys in the payload", async () => {
    const port = fixture();
    await assert.rejects(
      submitFeedbackForCallable(authed({ category: "bug", message: "hi", extra: "nope" }), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.records.length, 0);
  });

  it("rejects an unsupported category", async () => {
    const port = fixture();
    await assert.rejects(
      submitFeedbackForCallable(authed({ category: "urgent", message: "hi" }), port),
      hasCode("invalid-argument"),
    );
  });

  it("rejects an empty or whitespace-only message", async () => {
    const port = fixture();
    await assert.rejects(
      submitFeedbackForCallable(authed({ category: "bug", message: "" }), port),
      hasCode("invalid-argument"),
    );
    await assert.rejects(
      submitFeedbackForCallable(authed({ category: "bug", message: "   \n\t  " }), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.records.length, 0);
  });

  it("rejects a message longer than 2000 characters", async () => {
    const port = fixture();
    await assert.rejects(
      submitFeedbackForCallable(authed({ category: "bug", message: "a".repeat(2001) }), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.records.length, 0);
  });

  it("accepts a message at exactly the 2000 character boundary", async () => {
    const port = fixture();
    const result = await submitFeedbackForCallable(authed({ category: "bug", message: "a".repeat(2000) }), port);
    assert.equal(result.feedbackId, "feedback-1");
  });

  it("writes a feedback doc with server-owned defaults and a truncated, whitespace-collapsed summary", async () => {
    const port = fixture();
    const longMessage = `  The   run  \n\n tracker\tfroze   ${"x".repeat(200)} after I tapped stop.  `;
    const result = await submitFeedbackForCallable(authed({ category: "bug", message: longMessage }), port);

    assert.equal(result.feedbackId, "feedback-1");
    assert.equal(port.records.length, 1);
    const record = port.records[0]!;
    assert.equal(record.uid, "feedback-runner");
    assert.equal(record.category, "bug");
    assert.equal(record.message, longMessage.trim());
    assert.equal(record.summary, longMessage.replace(/\s+/g, " ").trim().slice(0, 120));
    assert.equal(record.summary.length, 120);
    assert.equal(record.severity, "low");
    assert.equal(record.status, "new");
    assert.equal(record.duplicateCount, 1);
    assert.equal(record.note, "");
    assert.equal(record.receivedAt, "server-timestamp");
  });

  it("accepts every supported category", async () => {
    const port = fixture();
    for (const category of ["bug", "plan issue", "billing", "other"]) {
      await submitFeedbackForCallable(authed({ category, message: `feedback about ${category}` }), port);
    }
    assert.equal(port.records.length, 4);
    assert.deepEqual(port.records.map((record) => record.category), ["bug", "plan issue", "billing", "other"]);
  });

  it("rejects submission once the caller has 5 recent submissions", async () => {
    const port = fixture();
    port.recentCount = 5;
    await assert.rejects(
      submitFeedbackForCallable(authed({ category: "bug", message: "one more" }), port),
      hasCode("resource-exhausted"),
    );
    assert.equal(port.records.length, 0);
  });

  it("allows submission when the caller has fewer than 5 recent submissions", async () => {
    const port = fixture();
    port.recentCount = 4;
    const result = await submitFeedbackForCallable(authed({ category: "bug", message: "still ok" }), port);
    assert.equal(result.feedbackId, "feedback-1");
    assert.equal(port.records.length, 1);
  });

  it("queries the rate limit window relative to the injected clock", async () => {
    const port = fixture();
    await submitFeedbackForCallable(authed({ category: "bug", message: "hello" }), port);
    assert.equal(port.lastSinceQueried?.getTime(), BASE_NOW.getTime() - 10 * 60 * 1000);
  });
});

function authed(data: unknown): { readonly auth: { readonly uid: string }; readonly data: unknown } {
  return { auth: { uid: "feedback-runner" }, data };
}

function hasCode(code: string): (error: unknown) => boolean {
  return (error: unknown) => error instanceof HttpsError && error.code === code;
}

class FakeFeedbackPort implements SubmitFeedbackPort {
  readonly records: FeedbackRecord[] = [];
  recentCount = 0;
  lastSinceQueried: Date | undefined;
  private nextId = 1;

  now(): Date {
    return BASE_NOW;
  }

  serverTimestamp(): unknown {
    return "server-timestamp";
  }

  async recentFeedbackCount(_uid: string, since: Date): Promise<number> {
    this.lastSinceQueried = since;
    return this.recentCount;
  }

  async addFeedback(record: FeedbackRecord): Promise<string> {
    this.records.push(record);
    const id = `feedback-${this.nextId}`;
    this.nextId += 1;
    return id;
  }
}

function fixture(): FakeFeedbackPort {
  return new FakeFeedbackPort();
}
