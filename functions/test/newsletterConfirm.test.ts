import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { sha256Hex } from "../src/newsletter/crypto.js";
import {
  confirmNewsletterSubscriptionCore,
  decideConfirmOutcome,
  type ConfirmDecision,
  type ConfirmNewsletterPort,
  type ConfirmNewsletterSubscriberSnapshot,
} from "../src/newsletter/confirmNewsletterSubscription.js";

const BASE_NOW = new Date("2026-07-30T12:00:00.000Z");
const RAW_TOKEN = "confirm-raw-token";
const TOKEN_HASH = sha256Hex(RAW_TOKEN);

describe("confirmNewsletterSubscription", () => {
  it("confirms a pending subscriber with a valid, unexpired token", async () => {
    const port = fixture();
    port.subscribers.set("sub1", {
      status: "pending",
      confirmTokenHash: TOKEN_HASH,
      confirmTokenExpiresAtMs: BASE_NOW.getTime() + 1000,
    });

    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "confirmed");
    assert.deepEqual(port.confirmedIds, ["sub1"]);
  });

  it("is idempotent: an already-confirmed subscriber with a still-matching token redirects to success without writing again", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "confirmed", confirmTokenHash: TOKEN_HASH });

    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "confirmed");
    assert.deepEqual(port.confirmedIds, []);
  });

  it("never resurrects an unsubscribed subscriber, even with a still-valid, unexpired token", async () => {
    const port = fixture();
    port.subscribers.set("sub1", {
      status: "unsubscribed",
      confirmTokenHash: TOKEN_HASH,
      confirmTokenExpiresAtMs: BASE_NOW.getTime() + 1000,
    });

    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "invalid");
    assert.deepEqual(port.confirmedIds, []);
  });

  it("rejects an expired confirm token", async () => {
    const port = fixture();
    port.subscribers.set("sub1", {
      status: "pending",
      confirmTokenHash: TOKEN_HASH,
      confirmTokenExpiresAtMs: BASE_NOW.getTime() - 1,
    });

    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "invalid");
    assert.deepEqual(port.confirmedIds, []);
  });

  it("rejects a wrong token", async () => {
    const port = fixture();
    port.subscribers.set("sub1", {
      status: "pending",
      confirmTokenHash: TOKEN_HASH,
      confirmTokenExpiresAtMs: BASE_NOW.getTime() + 1000,
    });

    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: "wrong-token" }, port);

    assert.equal(outcome, "invalid");
    assert.deepEqual(port.confirmedIds, []);
  });

  it("rejects a missing subscriberId or token", async () => {
    const port = fixture();
    assert.equal(await confirmNewsletterSubscriptionCore({ subscriberId: null, token: RAW_TOKEN }, port), "invalid");
    assert.equal(await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: null }, port), "invalid");
  });

  it("rejects an unknown subscriberId", async () => {
    const port = fixture();
    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "missing", token: RAW_TOKEN }, port);
    assert.equal(outcome, "invalid");
  });

  it("rejects a subscriber with no confirm token on file", async () => {
    const port = fixture();
    port.subscribers.set("sub1", { status: "pending" });
    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);
    assert.equal(outcome, "invalid");
  });

  it("race regression: an unsubscribe that lands between an earlier read and the transactional decision is never overwritten", async () => {
    // Models the race the transactional restructure closes. Some earlier
    // read of the subscriber (e.g. what a naive get-then-write confirm flow
    // would have used to decide) sees "pending" with a valid token. Before
    // the confirm's actual transaction runs, a concurrent unsubscribe
    // commits. A real Firestore transaction always re-reads authoritative
    // state at commit time (see runConfirmTransaction's doc comment); the
    // fake port below models that guarantee by having `decide` observe
    // whatever is in `subscribers` at the moment the transaction actually
    // runs, which is the state AFTER the interleaved unsubscribe, not the
    // stale "pending" read that happened first.
    const port = fixture();
    port.subscribers.set("sub1", {
      status: "pending",
      confirmTokenHash: TOKEN_HASH,
      confirmTokenExpiresAtMs: BASE_NOW.getTime() + 1000,
    });

    // Simulate an earlier, now-stale read (not used to decide anything —
    // just proof that "pending" was visible before the race window).
    const staleRead = port.subscribers.get("sub1");
    assert.equal(staleRead?.status, "pending");

    // Simulate the interleaved unsubscribe committing before the confirm
    // transaction's decision runs.
    port.subscribers.set("sub1", { ...staleRead!, status: "unsubscribed" });

    const outcome = await confirmNewsletterSubscriptionCore({ subscriberId: "sub1", token: RAW_TOKEN }, port);

    assert.equal(outcome, "invalid");
    assert.equal(port.subscribers.get("sub1")?.status, "unsubscribed");
    assert.deepEqual(port.confirmedIds, []);
  });
});

describe("decideConfirmOutcome (pure)", () => {
  it("confirms a pending snapshot with a valid, unexpired token", () => {
    const decision = decideConfirmOutcome(
      { status: "pending", confirmTokenHash: TOKEN_HASH, confirmTokenExpiresAtMs: BASE_NOW.getTime() + 1000 },
      RAW_TOKEN,
      BASE_NOW.getTime(),
    );
    assert.deepEqual(decision, { outcome: "confirmed", write: true } satisfies ConfirmDecision);
  });

  it("does not write for an already-confirmed snapshot", () => {
    const decision = decideConfirmOutcome({ status: "confirmed", confirmTokenHash: TOKEN_HASH }, RAW_TOKEN, BASE_NOW.getTime());
    assert.deepEqual(decision, { outcome: "confirmed", write: false } satisfies ConfirmDecision);
  });

  it("never writes for an unsubscribed snapshot", () => {
    const decision = decideConfirmOutcome(
      { status: "unsubscribed", confirmTokenHash: TOKEN_HASH, confirmTokenExpiresAtMs: BASE_NOW.getTime() + 1000 },
      RAW_TOKEN,
      BASE_NOW.getTime(),
    );
    assert.deepEqual(decision, { outcome: "invalid", write: false } satisfies ConfirmDecision);
  });

  it("returns invalid for a null snapshot", () => {
    const decision = decideConfirmOutcome(null, RAW_TOKEN, BASE_NOW.getTime());
    assert.deepEqual(decision, { outcome: "invalid", write: false } satisfies ConfirmDecision);
  });
});

class FakeConfirmPort implements ConfirmNewsletterPort {
  readonly subscribers = new Map<string, ConfirmNewsletterSubscriberSnapshot>();
  readonly confirmedIds: string[] = [];

  now(): Date {
    return BASE_NOW;
  }

  async runConfirmTransaction(
    subscriberId: string,
    decide: (snapshot: ConfirmNewsletterSubscriberSnapshot | null) => ConfirmDecision,
  ) {
    // Synchronous equivalent of a Firestore transaction: read current state,
    // decide, and (conditionally) write, all in one uninterrupted step. JS's
    // single-threaded execution means no other code can run between the
    // read below and the write, which is exactly the atomicity a real
    // Firestore transaction provides.
    const current = this.subscribers.get(subscriberId) ?? null;
    const decision = decide(current);
    if (decision.write) {
      this.confirmedIds.push(subscriberId);
      const existing = this.subscribers.get(subscriberId);
      if (existing !== undefined) {
        this.subscribers.set(subscriberId, { ...existing, status: "confirmed" });
      }
    }
    return decision.outcome;
  }
}

function fixture(): FakeConfirmPort {
  return new FakeConfirmPort();
}
