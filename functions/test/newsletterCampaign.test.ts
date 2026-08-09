import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  handleNewsletterCampaignWrite,
  LEASE_MS,
  type CampaignClaim,
  type CampaignClaimResume,
  type CampaignProgress,
  type CampaignSnapshot,
  type NewsletterCampaignPort,
  type RecipientRecord,
} from "../src/newsletter/newsletterCampaignQueued.js";
import { buildCampaignMail, type MailDocument } from "../src/newsletter/mailRender.js";

type FakeCampaignRecord = {
  status: string;
  subject: string;
  bodyMarkdown: string;
  testRecipients: string[];
  recipientCount?: number;
  deliveredCount?: number;
  failedCount?: number;
  error?: string;
  lastTestSentAt?: string;
  sendCursor?: string | null;
  leaseExpiresAt?: number | null;
};

const START_TIME_MS = 1_000_000_000_000;

describe("newsletterCampaignQueued fan-out", () => {
  it("sends a queued campaign to every confirmed subscriber across multiple pages, ending 'sent' with correct counts", async () => {
    const port = fixture(
      { status: "queued", subject: "Hello", bodyMarkdown: "Hi runners.", testRecipients: [] },
      [recipient("s1"), recipient("s2"), recipient("s3")],
      { pageSize: 2 },
    );

    await handleNewsletterCampaignWrite("camp1", "draft", "queued", port);

    assert.equal(port.campaign.status, "sent");
    assert.equal(port.campaign.recipientCount, 3);
    assert.equal(port.campaign.deliveredCount, 3);
    assert.equal(port.campaign.failedCount, 0);
    assert.equal(port.mails.length, 3);
    assert.equal(port.claimCalls.length, 1);
    assert.deepEqual(port.claimCalls[0], { campaignId: "camp1", mode: "send" });
    // Lease/cursor are cleared once the run reaches a terminal state.
    assert.equal(port.campaign.leaseExpiresAt, null);
    assert.equal(port.campaign.sendCursor, null);

    for (const mail of port.mails) {
      assert.match(mail.message.text, /Unsubscribe from this newsletter/);
      assert.match(mail.message.html, /Unsubscribe from this newsletter/);
      assert.equal(typeof mail.message.headers?.["List-Unsubscribe"], "string");
    }
  });

  it("skips a recipient whose delivery lock already exists (retry-safe: never double-sends)", async () => {
    const port = fixture(
      { status: "queued", subject: "Hello", bodyMarkdown: "Hi.", testRecipients: [] },
      [recipient("s1"), recipient("s2")],
      { pageSize: 10, preLockedKeys: ["camp1:s1"] },
    );

    await handleNewsletterCampaignWrite("camp1", "draft", "queued", port);

    assert.equal(port.mails.length, 1);
    assert.equal(port.mails[0]?.to, "s2@example.com");
    assert.equal(port.campaign.recipientCount, 2);
    assert.equal(port.campaign.deliveredCount, 2);
    assert.equal(port.campaign.failedCount, 0);
    // No new delivery record is written for the already-locked recipient.
    assert.equal(port.deliveryRecords.filter((record) => record.subscriberId === "s1").length, 0);
    assert.equal(port.deliveryRecords.filter((record) => record.subscriberId === "s2").length, 1);
  });

  it("counts a per-recipient send failure without aborting the whole campaign", async () => {
    const port = fixture(
      { status: "queued", subject: "Hello", bodyMarkdown: "Hi.", testRecipients: [] },
      [recipient("s1"), recipient("s2")],
      { pageSize: 10, failEnqueueForEmails: ["s1@example.com"] },
    );

    await handleNewsletterCampaignWrite("camp1", "draft", "queued", port);

    assert.equal(port.campaign.status, "sent");
    assert.equal(port.campaign.recipientCount, 2);
    assert.equal(port.campaign.deliveredCount, 1);
    assert.equal(port.campaign.failedCount, 1);
    const failedRecord = port.deliveryRecords.find((record) => record.subscriberId === "s1");
    assert.equal(failedRecord?.outcome.status, "failed");
  });

  it("ends the campaign 'failed' with an error and partial counts, and rethrows, when the fan-out itself faults", async () => {
    const port = fixture(
      { status: "queued", subject: "Hello", bodyMarkdown: "Hi.", testRecipients: [] },
      [recipient("s1"), recipient("s2"), recipient("s3")],
      { pageSize: 1, throwOnPageIndex: 1 },
    );

    await assert.rejects(handleNewsletterCampaignWrite("camp1", "draft", "queued", port));

    assert.equal(port.campaign.status, "failed");
    assert.equal(typeof port.campaign.error, "string");
    assert.equal(port.campaign.recipientCount, 1);
    assert.equal(port.campaign.deliveredCount, 1);
    // A caught, reported failure is a terminal state too: the lease/cursor
    // are cleared, same as a clean "sent" finish. A future re-queue starts
    // fresh rather than "resuming" a run that already reported itself dead.
    assert.equal(port.campaign.leaseExpiresAt, null);
    assert.equal(port.campaign.sendCursor, null);
  });

  it("ignores writes that are not ENTERING queued or testQueued", async () => {
    const port = fixture({ status: "queued", subject: "s", bodyMarkdown: "b", testRecipients: [] }, []);

    await handleNewsletterCampaignWrite("camp1", "queued", "queued", port); // already queued, not entering
    await handleNewsletterCampaignWrite("camp1", undefined, "draft", port); // entering draft, irrelevant
    await handleNewsletterCampaignWrite("camp1", "sending", undefined, port); // deletion

    assert.equal(port.claimCalls.length, 0);
    assert.equal(port.mails.length, 0);
  });

  it("does not double-send on a redelivered trigger event once the campaign has already moved past 'queued'", async () => {
    const port = fixture(
      { status: "sending", subject: "s", bodyMarkdown: "b", testRecipients: [] },
      [recipient("s1")],
    );

    // A retried event still claims it saw "draft" -> "queued", but the
    // authoritative status is already "sending" (with no lease at all, so
    // NOT reclaimable — this campaign predates the lease mechanism or is
    // still genuinely running) by the time the claim transaction runs.
    await handleNewsletterCampaignWrite("camp1", "draft", "queued", port);

    assert.equal(port.mails.length, 0);
    assert.equal(port.campaign.status, "sending");
  });

  it("live-lease: a 'sending' campaign with a lease still in the future is NOT reclaimed", async () => {
    const port = fixture(
      { status: "sending", subject: "s", bodyMarkdown: "b", testRecipients: [] },
      [recipient("s1")],
    );
    port.campaign.leaseExpiresAt = port.currentTimeMs + LEASE_MS / 2; // still live

    await handleNewsletterCampaignWrite("camp1", "draft", "queued", port);

    assert.equal(port.mails.length, 0);
    assert.equal(port.campaign.status, "sending");
    assert.equal(port.claimCalls.length, 1);
  });

  it("resume: a run that dies mid fan-out leaves the campaign 'sending' with cursor+counts persisted, and a stale-lease reclaim resumes from the cursor without re-mailing the already-processed page, ending 'sent' with correct final counts", async () => {
    const port = fixture(
      { status: "queued", subject: "Hello", bodyMarkdown: "Hi.", testRecipients: [] },
      [recipient("s1"), recipient("s2"), recipient("s3")],
      { pageSize: 1 },
    );

    // --- "First invocation": manually drive exactly what the real fan-out
    // does for page 1, then stop WITHOUT calling finishSend — this models a
    // hard process kill (OOM, timeout, deploy) that happens after page 1's
    // progress is durably persisted but before page 2 is even fetched. A
    // real crash never reaches sendRealCampaign's catch block, so driving
    // the port calls directly (rather than letting a thrown error inside
    // handleNewsletterCampaignWrite reach finishSend) is the accurate way to
    // model it.
    const claim = await port.claimCampaign("camp1", "send");
    assert.notEqual(claim, null);
    const page1 = await port.listConfirmedSubscriberPage(claim!.resume.cursor);
    assert.deepEqual(page1.recipients.map((r) => r.subscriberId), ["s1"]);
    assert.equal(page1.hasMore, true);
    const locked = await port.tryLockDelivery("camp1", "s1");
    assert.equal(locked, true);
    const mailDocId = await port.enqueueMail(
      buildCampaignMail({
        to: "s1@example.com",
        subject: port.campaign.subject,
        bodyMarkdown: port.campaign.bodyMarkdown,
        unsubscribeUrl: "https://runiac.example/unsubscribeNewsletter?s=s1&t=raw-s1",
      }),
    );
    await port.recordDelivery("camp1", "s1", { status: "sent", mailDocId });
    await port.persistProgress("camp1", { cursor: "s1", recipientCount: 1, deliveredCount: 1, failedCount: 0 });

    assert.equal(port.campaign.status, "sending");
    assert.equal(port.campaign.sendCursor, "s1");
    assert.equal(port.campaign.recipientCount, 1);
    assert.equal(port.campaign.deliveredCount, 1);
    assert.equal(port.mails.length, 1);

    // The dead run's lease is still technically live right after persisting
    // — advance the fake clock past it so the next event is a genuine
    // stale-lease reclaim.
    port.currentTimeMs += LEASE_MS + 1;

    // --- "Second invocation": a redelivered instance of the SAME original
    // queue event (Cloud Functions v2 triggers are at-least-once). It
    // reclaims via the stale lease and resumes from the persisted cursor.
    await handleNewsletterCampaignWrite("camp1", "draft", "queued", port);

    assert.equal(port.claimCalls.length, 2);
    assert.equal(port.campaign.status, "sent");
    assert.equal(port.campaign.recipientCount, 3);
    assert.equal(port.campaign.deliveredCount, 3);
    assert.equal(port.campaign.failedCount, 0);
    // s1 was never re-mailed: exactly 3 mails total (1 from the manual
    // "first invocation" step, 2 from the resumed page walk over s2/s3).
    assert.equal(port.mails.length, 3);
    assert.deepEqual(
      port.mails.map((m) => m.to).sort(),
      ["s1@example.com", "s2@example.com", "s3@example.com"],
    );
    // No second delivery record was written for s1.
    assert.equal(port.deliveryRecords.filter((r) => r.subscriberId === "s1").length, 1);
    assert.equal(port.campaign.leaseExpiresAt, null);
    assert.equal(port.campaign.sendCursor, null);
  });

  it("sends a test campaign only to testRecipients, creates NO delivery locks, and returns the campaign to draft", async () => {
    const port = fixture(
      { status: "testQueued", subject: "Preview", bodyMarkdown: "Hi [team](https://runiac.example).", testRecipients: ["admin@runiac.example", "qa@runiac.example"] },
      [recipient("s1"), recipient("s2")],
    );

    await handleNewsletterCampaignWrite("camp1", "draft", "testQueued", port);

    assert.equal(port.mails.length, 2);
    assert.deepEqual(
      port.mails.map((mail) => mail.to).sort(),
      ["admin@runiac.example", "qa@runiac.example"],
    );
    assert.equal(port.deliveryLocks.size, 0);
    assert.equal(port.campaign.status, "draft");
    assert.equal(port.campaign.lastTestSentAt, "server-timestamp");
    for (const mail of port.mails) {
      assert.match(mail.message.html, /Unsubscribe from this newsletter/);
    }
  });

  it("flips a test claim to 'draft' immediately, before any test mail is sent", async () => {
    const port = fixture(
      { status: "testQueued", subject: "Preview", bodyMarkdown: "Hi.", testRecipients: ["admin@runiac.example"] },
      [],
    );

    const claimed = await port.claimCampaign("camp1", "test");

    assert.notEqual(claimed, null);
    // The claim alone — before sendTestCampaign has enqueued anything —
    // already moved the campaign out of "testQueued", making the claim
    // single-winner.
    assert.equal(port.campaign.status, "draft");
    assert.equal(port.mails.length, 0);
  });

  it("does not re-send a test campaign on a redelivered trigger event for the same write", async () => {
    const port = fixture(
      { status: "testQueued", subject: "Preview", bodyMarkdown: "Hi.", testRecipients: ["admin@runiac.example"] },
      [],
    );

    await handleNewsletterCampaignWrite("camp1", "draft", "testQueued", port);
    assert.equal(port.mails.length, 1);
    assert.equal(port.campaign.status, "draft");

    // Cloud Functions triggers are at-least-once: the SAME event (identical
    // before/after status pair) can be redelivered. The enter-transition
    // check alone cannot tell this apart from the first delivery — only the
    // transactional claim (re-reading CURRENT status, now "draft" instead
    // of "testQueued") can refuse it.
    await handleNewsletterCampaignWrite("camp1", "draft", "testQueued", port);

    assert.equal(port.mails.length, 1);
    assert.equal(port.claimCalls.length, 2);
  });
});

function recipient(subscriberId: string): RecipientRecord {
  return { subscriberId, emailLower: `${subscriberId}@example.com`, unsubscribeTokenRaw: `raw-${subscriberId}` };
}

class FakeCampaignPort implements NewsletterCampaignPort {
  readonly campaign: FakeCampaignRecord;
  readonly subscribers: readonly RecipientRecord[];
  readonly pageSize: number;
  readonly deliveryLocks = new Set<string>();
  readonly deliveryRecords: Array<{
    readonly campaignId: string;
    readonly subscriberId: string;
    readonly outcome: { readonly status: "sent" | "failed"; readonly mailDocId?: string; readonly error?: string };
  }> = [];
  readonly mails: MailDocument[] = [];
  readonly claimCalls: Array<{ readonly campaignId: string; readonly mode: "send" | "test" }> = [];
  currentTimeMs = START_TIME_MS;
  private readonly failEnqueueForEmails: ReadonlySet<string>;
  private readonly throwOnPageIndex: number | null;
  private pageCallCount = 0;
  private tokenCounter = 0;

  constructor(
    campaign: FakeCampaignRecord,
    subscribers: readonly RecipientRecord[],
    options: {
      readonly pageSize?: number;
      readonly preLockedKeys?: readonly string[];
      readonly failEnqueueForEmails?: readonly string[];
      readonly throwOnPageIndex?: number;
    } = {},
  ) {
    this.campaign = campaign;
    this.subscribers = subscribers;
    this.pageSize = options.pageSize ?? 200;
    for (const key of options.preLockedKeys ?? []) {
      this.deliveryLocks.add(key);
    }
    this.failEnqueueForEmails = new Set(options.failEnqueueForEmails ?? []);
    this.throwOnPageIndex = options.throwOnPageIndex ?? null;
  }

  now(): number {
    return this.currentTimeMs;
  }

  generateToken(): string {
    this.tokenCounter += 1;
    return `test-token-${this.tokenCounter}`;
  }

  async claimCampaign(campaignId: string, mode: "send" | "test"): Promise<CampaignClaim | null> {
    this.claimCalls.push({ campaignId, mode });
    const snapshot: CampaignSnapshot = {
      subject: this.campaign.subject,
      bodyMarkdown: this.campaign.bodyMarkdown,
      testRecipients: this.campaign.testRecipients,
    };

    if (mode === "test") {
      if (this.campaign.status !== "testQueued") {
        return null;
      }
      // Mirrors the production port: the claim is single-winner, so the
      // status write happens here, inside the "transaction", before any
      // mail is sent. A test claim goes straight to "draft" (its terminal
      // state) rather than staying "testQueued".
      this.campaign.status = "draft";
      return { snapshot, resume: { cursor: null, recipientCount: 0, deliveredCount: 0, failedCount: 0 } };
    }

    // "send" mode: mirrors the production port's fresh-queue-or-stale-lease
    // claimability check.
    const leaseExpiresAt = this.campaign.leaseExpiresAt ?? undefined;
    const nowMs = this.now();
    const isFreshQueue = this.campaign.status === "queued";
    const isStaleLeaseReclaim = this.campaign.status === "sending" && leaseExpiresAt !== undefined && leaseExpiresAt < nowMs;
    if (!isFreshQueue && !isStaleLeaseReclaim) {
      return null;
    }

    const resume: CampaignClaimResume = {
      cursor: this.campaign.sendCursor ?? null,
      recipientCount: this.campaign.recipientCount ?? 0,
      deliveredCount: this.campaign.deliveredCount ?? 0,
      failedCount: this.campaign.failedCount ?? 0,
    };
    this.campaign.status = "sending";
    this.campaign.leaseExpiresAt = nowMs + LEASE_MS;
    return { snapshot, resume };
  }

  async listConfirmedSubscriberPage(
    afterSubscriberId: string | null,
  ): Promise<{ readonly recipients: readonly RecipientRecord[]; readonly hasMore: boolean }> {
    if (this.throwOnPageIndex !== null && this.pageCallCount === this.throwOnPageIndex) {
      this.pageCallCount += 1;
      throw new Error("simulated pagination failure");
    }
    this.pageCallCount += 1;

    const startIndex =
      afterSubscriberId === null ? 0 : this.subscribers.findIndex((s) => s.subscriberId === afterSubscriberId) + 1;
    const recipients = this.subscribers.slice(startIndex, startIndex + this.pageSize);
    const hasMore = startIndex + this.pageSize < this.subscribers.length;
    return { recipients, hasMore };
  }

  async tryLockDelivery(campaignId: string, subscriberId: string): Promise<boolean> {
    const key = `${campaignId}:${subscriberId}`;
    if (this.deliveryLocks.has(key)) {
      return false;
    }
    this.deliveryLocks.add(key);
    return true;
  }

  async recordDelivery(
    campaignId: string,
    subscriberId: string,
    outcome: { readonly status: "sent" | "failed"; readonly mailDocId?: string; readonly error?: string },
  ): Promise<void> {
    this.deliveryRecords.push({ campaignId, subscriberId, outcome });
  }

  async enqueueMail(mail: MailDocument): Promise<string> {
    if (this.failEnqueueForEmails.has(mail.to)) {
      throw new Error(`simulated send failure for ${mail.to}`);
    }
    this.mails.push(mail);
    return `mail-${this.mails.length}`;
  }

  async persistProgress(campaignId: string, progress: CampaignProgress): Promise<void> {
    this.campaign.sendCursor = progress.cursor;
    this.campaign.recipientCount = progress.recipientCount;
    this.campaign.deliveredCount = progress.deliveredCount;
    this.campaign.failedCount = progress.failedCount;
    this.campaign.leaseExpiresAt = this.now() + LEASE_MS;
  }

  async finishSend(
    campaignId: string,
    result: {
      readonly status: "sent" | "failed";
      readonly recipientCount: number;
      readonly deliveredCount: number;
      readonly failedCount: number;
      readonly error?: string;
    },
  ): Promise<void> {
    this.campaign.status = result.status;
    this.campaign.recipientCount = result.recipientCount;
    this.campaign.deliveredCount = result.deliveredCount;
    this.campaign.failedCount = result.failedCount;
    // Terminal state: clear the lease/cursor, mirroring the production port.
    this.campaign.leaseExpiresAt = null;
    this.campaign.sendCursor = null;
    if (result.error !== undefined) {
      this.campaign.error = result.error;
    }
  }

  async finishTest(_campaignId: string): Promise<void> {
    // status is intentionally NOT written here — claimCampaign already
    // moved it to "draft" as part of claiming, matching the production port.
    this.campaign.lastTestSentAt = "server-timestamp";
  }
}

function fixture(
  campaign: FakeCampaignRecord,
  subscribers: readonly RecipientRecord[],
  options?: {
    readonly pageSize?: number;
    readonly preLockedKeys?: readonly string[];
    readonly failEnqueueForEmails?: readonly string[];
    readonly throwOnPageIndex?: number;
  },
): FakeCampaignPort {
  return new FakeCampaignPort(campaign, subscribers, options);
}
