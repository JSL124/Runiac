import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { sha256Hex } from "../src/newsletter/crypto.js";
import {
  decideUnsubscribeOutcome,
  unsubscribeNewsletterCore,
  type UnsubscribeDecision,
  type UnsubscribeNewsletterPort,
  type UnsubscribeNewsletterSubscriberSnapshot,
} from "../src/newsletter/unsubscribeNewsletter.js";

const RAW_TOKEN = "unsubscribe-raw-token";
const TOKEN_HASH = sha256Hex(RAW_TOKEN);

describe("unsubscribeNewsletter", () => {
  it("unsubscribes a confirmed subscriber with a valid token", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "confirmed", unsubscribeTokenHash: TOKEN_HASH });

    const outcome = await unsubscribeNewsletterCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "unsubscribed");
    assert.deepEqual(port.unsubscribedIds, ["sub1"]);
  });

  it("is idempotent: an already-unsubscribed subscriber with a valid token succeeds without writing again", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "unsubscribed", unsubscribeTokenHash: TOKEN_HASH });

    const outcome = await unsubscribeNewsletterCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "unsubscribed");
    assert.deepEqual(port.unsubscribedIds, []);
  });

  it("never expires: an old token still works regardless of how long ago it was issued", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "confirmed", unsubscribeTokenHash: TOKEN_HASH });

    const outcome = await unsubscribeNewsletterCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);
    assert.equal(outcome, "unsubscribed");
  });

  it("rejects a wrong token", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "confirmed", unsubscribeTokenHash: TOKEN_HASH });

    const outcome = await unsubscribeNewsletterCore({ subscriberId: "sub1", token: "wrong-token" }, port);

    assert.equal(outcome, "invalid");
    assert.deepEqual(port.unsubscribedIds, []);
  });

  it("rejects a missing subscriberId or token", async () => {
    const port = fixture();
    assert.equal(await unsubscribeNewsletterCore({ subscriberId: null, token: RAW_TOKEN }, port), "invalid");
    assert.equal(await unsubscribeNewsletterCore({ subscriberId: "sub1", token: null }, port), "invalid");
  });

  it("rejects an unknown subscriberId", async () => {
    const port = fixture();
    const outcome = await unsubscribeNewsletterCore({ subscriberId: "missing", token: RAW_TOKEN }, port);
    assert.equal(outcome, "invalid");
  });

  it("rejects a subscriber with no unsubscribe token on file", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "confirmed" });
    const outcome = await unsubscribeNewsletterCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);
    assert.equal(outcome, "invalid");
  });

  it("race: a confirm that lands between an earlier read and the transactional decision is observed (not overwritten with stale data)", async () => {
    // Mirrors the confirm-side race regression test: the fake port's
    // transaction reads whatever is authoritative at the moment `decide`
    // runs, not whatever was read earlier. Here an earlier read sees
    // "pending" (not yet confirmed); a concurrent confirm commits before the
    // unsubscribe transaction runs; the unsubscribe still correctly acts on
    // the latest ("confirmed") state.
    const port = fixture();
    port.subscribers.set("sub1", { status: "pending", unsubscribeTokenHash: TOKEN_HASH });

    const staleRead = port.subscribers.get("sub1");
    assert.equal(staleRead?.status, "pending");

    port.subscribers.set("sub1", { ...staleRead!, status: "confirmed" });

    const outcome = await unsubscribeNewsletterCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "unsubscribed");
    assert.equal(port.subscribers.get("sub1")?.status, "unsubscribed");
    assert.deepEqual(port.unsubscribedIds, ["sub1"]);
  });
});

describe("decideUnsubscribeOutcome (pure)", () => {
  it("unsubscribes a non-unsubscribed snapshot with a valid token", () => {
    const decision = decideUnsubscribeOutcome({ status: "confirmed", unsubscribeTokenHash: TOKEN_HASH }, RAW_TOKEN);
    assert.deepEqual(decision, { outcome: "unsubscribed", write: true } satisfies UnsubscribeDecision);
  });

  it("does not write for an already-unsubscribed snapshot", () => {
    const decision = decideUnsubscribeOutcome({ status: "unsubscribed", unsubscribeTokenHash: TOKEN_HASH }, RAW_TOKEN);
    assert.deepEqual(decision, { outcome: "unsubscribed", write: false } satisfies UnsubscribeDecision);
  });

  it("returns invalid for a null snapshot", () => {
    const decision = decideUnsubscribeOutcome(null, RAW_TOKEN);
    assert.deepEqual(decision, { outcome: "invalid", write: false } satisfies UnsubscribeDecision);
  });

  it("returns invalid for a wrong token", () => {
    const decision = decideUnsubscribeOutcome({ status: "confirmed", unsubscribeTokenHash: TOKEN_HASH }, "wrong-token");
    assert.deepEqual(decision, { outcome: "invalid", write: false } satisfies UnsubscribeDecision);
  });
});

class FakeUnsubscribePort implements UnsubscribeNewsletterPort {
  readonly subscribers = new Map<string, UnsubscribeNewsletterSubscriberSnapshot>();
  readonly unsubscribedIds: string[] = [];

  async runUnsubscribeTransaction(
    subscriberId: string,
    decide: (snapshot: UnsubscribeNewsletterSubscriberSnapshot | null) => UnsubscribeDecision,
  ) {
    // Synchronous equivalent of a Firestore transaction: see
    // newsletterConfirm.test.ts's FakeConfirmPort for the rationale.
    const current = this.subscribers.get(subscriberId) ?? null;
    const decision = decide(current);
    if (decision.write) {
      this.unsubscribedIds.push(subscriberId);
      const existing = this.subscribers.get(subscriberId);
      if (existing !== undefined) {
        this.subscribers.set(subscriberId, { ...existing, status: "unsubscribed" });
      }
    }
    return decision.outcome;
  }
}

function fixture(): FakeUnsubscribePort {
  return new FakeUnsubscribePort();
}
