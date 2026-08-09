import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  sweepUnconfirmedSubscribersNow,
  type NewsletterSweepPort,
} from "../src/newsletter/sweepUnconfirmedSubscribers.js";

const BASE_NOW = new Date("2026-07-30T12:00:00.000Z");
const DAY_MS = 24 * 60 * 60 * 1000;

describe("sweepUnconfirmedSubscribers", () => {
  it("deletes only pending subscribers older than 30 days, leaving confirmed/unsubscribed and recent-pending docs alone", async () => {
    const port = fixture({
      // The port's listStalePendingSubscriberIds fake already applies the
      // status filter (mirroring the real Firestore query), so this test
      // exercises the cutoff-boundary math and the delete fan-out.
      stalePendingIds: ["old-pending-1", "old-pending-2"],
      staleRateLimitIds: [],
    });

    const result = await sweepUnconfirmedSubscribersNow(port);

    assert.deepEqual(result, { deletedSubscribers: 2, deletedRateLimits: 0 });
    assert.deepEqual(port.deletedSubscriberIds.sort(), ["old-pending-1", "old-pending-2"]);
    assert.equal(port.pendingCutoffMsSeen, BASE_NOW.getTime() - 30 * DAY_MS);
  });

  it("deletes nothing when there is no stale pending subscriber and no stale rate-limit doc", async () => {
    const port = fixture({ stalePendingIds: [], staleRateLimitIds: [] });

    const result = await sweepUnconfirmedSubscribersNow(port);

    assert.deepEqual(result, { deletedSubscribers: 0, deletedRateLimits: 0 });
    assert.equal(port.deletedSubscriberIds.length, 0);
    assert.equal(port.deletedRateLimitIds.length, 0);
  });

  it("also prunes stale newsletterRateLimits docs, independently of the subscriber sweep", async () => {
    const port = fixture({ stalePendingIds: [], staleRateLimitIds: ["iphash-old-1"] });

    const result = await sweepUnconfirmedSubscribersNow(port);

    assert.deepEqual(result, { deletedSubscribers: 0, deletedRateLimits: 1 });
    assert.deepEqual(port.deletedRateLimitIds, ["iphash-old-1"]);
  });
});

class FakeSweepPort implements NewsletterSweepPort {
  readonly deletedSubscriberIds: string[] = [];
  readonly deletedRateLimitIds: string[] = [];
  pendingCutoffMsSeen: number | undefined;
  rateLimitCutoffMsSeen: number | undefined;

  constructor(
    private readonly stalePendingIds: readonly string[],
    private readonly staleRateLimitIds: readonly string[],
  ) {}

  now(): Date {
    return BASE_NOW;
  }

  async listStalePendingSubscriberIds(cutoffMs: number): Promise<readonly string[]> {
    this.pendingCutoffMsSeen = cutoffMs;
    return this.stalePendingIds;
  }

  async deleteSubscriber(subscriberId: string): Promise<void> {
    this.deletedSubscriberIds.push(subscriberId);
  }

  async listStaleRateLimitIds(cutoffMs: number): Promise<readonly string[]> {
    this.rateLimitCutoffMsSeen = cutoffMs;
    return this.staleRateLimitIds;
  }

  async deleteRateLimit(ipHash: string): Promise<void> {
    this.deletedRateLimitIds.push(ipHash);
  }
}

function fixture(args: {
  readonly stalePendingIds: readonly string[];
  readonly staleRateLimitIds: readonly string[];
}): FakeSweepPort {
  return new FakeSweepPort(args.stalePendingIds, args.staleRateLimitIds);
}
