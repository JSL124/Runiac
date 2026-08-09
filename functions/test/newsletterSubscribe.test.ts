import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import { sha256Hex, subscriberIdForEmail } from "../src/newsletter/crypto.js";
import {
  subscribeNewsletterForCallable,
  type NewsletterSubscriberSnapshot,
  type SubscribeNewsletterPort,
} from "../src/newsletter/subscribeNewsletter.js";

const BASE_NOW = new Date("2026-07-30T12:00:00.000Z");

describe("subscribeNewsletter callable", () => {
  it("creates a pending subscriber and sends a confirmation mail for a brand-new address", async () => {
    const port = fixture();
    const result = await subscribeNewsletterForCallable(requestFor({ email: "Runner@Example.com  " }), port);

    assert.deepEqual(result, { status: "pending" });
    assert.equal(port.upserts.length, 1);
    const upsert = port.upserts[0];
    assert.ok(upsert !== undefined);
    const { subscriberId, fields } = upsert;
    assert.equal(subscriberId, subscriberIdForEmail("runner@example.com"));
    assert.equal(fields["emailLower"], "runner@example.com");
    assert.equal(fields["status"], "pending");
    assert.equal(fields["source"], "website_hero");
    assert.equal(fields["sendFailureCount"], 0);
    assert.equal(typeof fields["confirmTokenHash"], "string");
    assert.ok(fields["confirmTokenExpiresAt"] instanceof Date);
    assert.equal(typeof fields["unsubscribeTokenHash"], "string");
    assert.equal(typeof fields["unsubscribeTokenRaw"], "string");
    assert.equal(fields["ipHash"], sha256Hex("203.0.113.7"));
    assert.equal(fields["createdAt"], "server-timestamp");

    assert.equal(fields["confirmTokenHash"], sha256Hex("token-1"));
    assert.equal(fields["unsubscribeTokenRaw"], "token-2");
    assert.equal(fields["unsubscribeTokenHash"], sha256Hex("token-2"));

    assert.equal(port.confirmationMails.length, 1);
    assert.deepEqual(port.confirmationMails[0], {
      to: "runner@example.com",
      subscriberId,
      rawToken: "token-1",
    });
  });

  it("returns already-subscribed and sends NO mail when the address is already confirmed", async () => {
    const port = fixture();
    const subscriberId = subscriberIdForEmail("runner@example.com");
    port.subscribers.set(subscriberId, { status: "confirmed" });

    const result = await subscribeNewsletterForCallable(requestFor({ email: "runner@example.com" }), port);

    assert.deepEqual(result, { status: "already-subscribed" });
    assert.equal(port.upserts.length, 0);
    assert.equal(port.confirmationMails.length, 0);
  });

  it("re-arms a fresh pending status for a previously unsubscribed address, and still sends mail", async () => {
    const port = fixture();
    const subscriberId = subscriberIdForEmail("runner@example.com");
    port.subscribers.set(subscriberId, { status: "unsubscribed" });

    const result = await subscribeNewsletterForCallable(requestFor({ email: "runner@example.com" }), port);

    assert.deepEqual(result, { status: "pending" });
    assert.equal(port.upserts.length, 1);
    assert.equal(port.upserts[0]?.fields["status"], "pending");
    assert.equal(port.confirmationMails.length, 1);
  });

  it("re-arms createdAt (the sweep's retention clock) on every re-subscribe of an existing document, not just a brand-new one", async () => {
    // Regression: the daily sweep deletes `pending` docs whose `createdAt`
    // is older than 30 days. If a returner's re-subscribe kept the
    // ORIGINAL createdAt, a fresh 7-day confirm token could be minted onto a
    // record the sweep is about to delete out from under it. createdAt must
    // always mean "start of the current pending window".
    const port = fixture();
    const subscriberId = subscriberIdForEmail("runner@example.com");
    port.subscribers.set(subscriberId, { status: "unsubscribed" });

    await subscribeNewsletterForCallable(requestFor({ email: "runner@example.com" }), port);

    assert.equal(port.upserts.length, 1);
    assert.equal(port.upserts[0]?.fields["createdAt"], "server-timestamp");
  });

  it("reuses the existing unsubscribe token across a re-subscribe, but always re-arms the confirm token", async () => {
    const port = fixture();
    const subscriberId = subscriberIdForEmail("runner@example.com");

    await subscribeNewsletterForCallable(requestFor({ email: "runner@example.com" }), port);
    const firstUnsubscribeHash = port.upserts[0]?.fields["unsubscribeTokenHash"];
    const firstUnsubscribeRaw = port.upserts[0]?.fields["unsubscribeTokenRaw"];
    const firstConfirmHash = port.upserts[0]?.fields["confirmTokenHash"];

    // Simulate the subscriber going unconfirmed again and re-subscribing.
    port.subscribers.set(subscriberId, {
      status: "pending",
      unsubscribeTokenHash: firstUnsubscribeHash as string,
      unsubscribeTokenRaw: firstUnsubscribeRaw as string,
    });
    await subscribeNewsletterForCallable(requestFor({ email: "runner@example.com" }), port);

    assert.equal(port.upserts[1]?.fields["unsubscribeTokenHash"], firstUnsubscribeHash);
    assert.equal(port.upserts[1]?.fields["unsubscribeTokenRaw"], firstUnsubscribeRaw);
    assert.notEqual(port.upserts[1]?.fields["confirmTokenHash"], firstConfirmHash);
    // createdAt (the sweep's retention clock) is re-armed every time, unlike
    // the unsubscribe token.
    assert.equal(port.upserts[1]?.fields["createdAt"], "server-timestamp");
  });

  it("performs no reads or writes at all when the honeypot field is filled", async () => {
    const port = fixture();
    const result = await subscribeNewsletterForCallable(
      requestFor({ email: "runner@example.com", website: "http://spam.example" }),
      port,
    );

    assert.deepEqual(result, { status: "pending" });
    assert.equal(port.upserts.length, 0);
    assert.equal(port.confirmationMails.length, 0);
    assert.equal(port.rateLimitCalls.length, 0);
    assert.equal(port.getSubscriberCalls.length, 0);
  });

  it("rejects once the caller is over the per-IP rate limit", async () => {
    const port = fixture();
    port.rateLimitAllowed = false;

    await assert.rejects(
      subscribeNewsletterForCallable(requestFor({ email: "runner@example.com" }), port),
      hasCode("resource-exhausted"),
    );
    assert.equal(port.upserts.length, 0);
    assert.equal(port.confirmationMails.length, 0);
  });

  it("rejects a payload with unsupported fields", async () => {
    const port = fixture();
    await assert.rejects(
      subscribeNewsletterForCallable(requestFor({ email: "runner@example.com", extra: "nope" }), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.upserts.length, 0);
  });

  it("rejects a non-object payload", async () => {
    const port = fixture();
    await assert.rejects(
      subscribeNewsletterForCallable({ data: "not-an-object" }, port),
      hasCode("invalid-argument"),
    );
  });

  it("rejects an invalid email format", async () => {
    const port = fixture();
    await assert.rejects(
      subscribeNewsletterForCallable(requestFor({ email: "not-an-email" }), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.upserts.length, 0);
  });

  it("rejects an empty email", async () => {
    const port = fixture();
    await assert.rejects(
      subscribeNewsletterForCallable(requestFor({ email: "   " }), port),
      hasCode("invalid-argument"),
    );
  });

  it("rejects an email longer than 254 characters", async () => {
    const port = fixture();
    const longLocalPart = "a".repeat(250);
    await assert.rejects(
      subscribeNewsletterForCallable(requestFor({ email: `${longLocalPart}@example.com` }), port),
      hasCode("invalid-argument"),
    );
    assert.equal(port.upserts.length, 0);
  });

  it("accepts an email at exactly the 254 character boundary", async () => {
    const port = fixture();
    // "b@example.com" is 13 chars; pad the local part so the whole address
    // is exactly 254 characters.
    const domain = "@example.com";
    const email = `${"c".repeat(254 - domain.length)}${domain}`;
    assert.equal(email.length, 254);

    const result = await subscribeNewsletterForCallable(requestFor({ email }), port);
    assert.deepEqual(result, { status: "pending" });
  });

  it("hashes an unknown caller IP defensively rather than throwing", async () => {
    const port = fixture();
    const result = await subscribeNewsletterForCallable({ data: { email: "runner@example.com" } }, port);
    assert.deepEqual(result, { status: "pending" });
    assert.equal(port.upserts[0]?.fields["ipHash"], sha256Hex("unknown-ip"));
  });
});

function requestFor(data: unknown): { readonly rawRequest: { readonly ip: string }; readonly data: unknown } {
  return { rawRequest: { ip: "203.0.113.7" }, data };
}

function hasCode(code: string): (error: unknown) => boolean {
  return (error: unknown) => error instanceof HttpsError && error.code === code;
}

class FakeSubscribePort implements SubscribeNewsletterPort {
  readonly subscribers = new Map<string, NewsletterSubscriberSnapshot>();
  readonly upserts: Array<{ readonly subscriberId: string; readonly fields: Record<string, unknown> }> = [];
  readonly confirmationMails: Array<{ readonly to: string; readonly subscriberId: string; readonly rawToken: string }> = [];
  readonly getSubscriberCalls: string[] = [];
  readonly rateLimitCalls: string[] = [];
  rateLimitAllowed = true;
  private tokenCounter = 0;

  now(): Date {
    return BASE_NOW;
  }

  serverTimestamp(): unknown {
    return "server-timestamp";
  }

  generateToken(): string {
    this.tokenCounter += 1;
    return `token-${this.tokenCounter}`;
  }

  async checkAndConsumeRateLimit(ipHash: string): Promise<boolean> {
    this.rateLimitCalls.push(ipHash);
    return this.rateLimitAllowed;
  }

  async getSubscriber(subscriberId: string): Promise<NewsletterSubscriberSnapshot | null> {
    this.getSubscriberCalls.push(subscriberId);
    return this.subscribers.get(subscriberId) ?? null;
  }

  async upsertSubscriber(subscriberId: string, fields: Readonly<Record<string, unknown>>): Promise<void> {
    this.upserts.push({ subscriberId, fields: { ...fields } });
  }

  async sendConfirmationMail(args: { readonly to: string; readonly subscriberId: string; readonly rawToken: string }): Promise<void> {
    this.confirmationMails.push(args);
  }
}

function fixture(): FakeSubscribePort {
  return new FakeSubscribePort();
}
