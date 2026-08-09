import { beforeEach, describe, expect, it, vi } from "vitest";

// Locks the audit-category derivation against the defect it was written to fix.
//
// toAuditCategory used to compare an entry's `action` against the category
// names themselves ("subscription-change", "rule-activation", "backend-job").
// No writer has ever emitted those strings — they came from the mock dataset
// the console was first built against, while every real writer uses a dotted
// namespace. Four of the six filters could therefore never match, and 144 of
// the 146 rows in the production log collapsed into "admin-action".
//
// The action names below are the real ones, taken from a full read of the
// production adminAuditLogs collection on 2026-08-13, so a regression here
// means the filter has stopped grouping real traffic rather than a fixture.

const { listAuditLogsMock } = vi.hoisted(() => ({
  listAuditLogsMock: vi.fn(),
}));

vi.mock("@/lib/firebase/firestore", () => ({
  listAuditLogs: listAuditLogsMock,
}));

import type { AuditLogRow } from "@/lib/firebase/types";
import type { AuditCategory } from "../types";

import { getLiveAuditLog } from "../live-data";

function auditRow(action: string | null): AuditLogRow {
  return {
    id: `aud-${action ?? "null"}`,
    actor: "admin@example.com",
    action,
    detail: "detail",
    targetType: "user",
    targetId: "usr-1",
    createdAt: "2026-08-13T00:00:00.000Z",
  } as AuditLogRow;
}

async function categoryOf(action: string | null): Promise<AuditCategory> {
  listAuditLogsMock.mockResolvedValue([auditRow(action)]);
  const [entry] = await getLiveAuditLog();
  return entry.category;
}

describe("audit category derivation", () => {
  beforeEach(() => {
    listAuditLogsMock.mockReset();
  });

  it("groups every config publish as a rule activation", async () => {
    // 42 of the 146 production rows. All eight config documents the console
    // can publish, so a new one is classified without editing the mapping.
    for (const action of [
      "config.progression.update",
      "config.leaderboard.update",
      "config.paywall.update",
      "config.featureAccess.update",
      "config.characterAccess.update",
      "config.challengeAccess.update",
      "config.automation.update",
      "config.siteContent.update",
    ]) {
      expect(await categoryOf(action)).toBe("rule-activation");
    }
  });

  it("groups automated work as a backend job", async () => {
    // Written by scheduled functions and one-off backfills, never by a person.
    for (const action of [
      "moderation.stale-reports.escalate",
      "moderation.report-auto-hide.request",
      "user.backfill.create-users-doc",
      "user.backfill.fix-level-xp-consistency",
    ]) {
      expect(await categoryOf(action)).toBe("backend-job");
    }
  });

  it("groups tier movement as a subscription change, however it was triggered", async () => {
    // The expiry sweep runs as "system" but what changed is still the tier,
    // which is what someone filtering this column is looking for.
    expect(await categoryOf("user.subscription.update")).toBe(
      "subscription-change",
    );
    expect(await categoryOf("user.subscription.expire")).toBe(
      "subscription-change",
    );
  });

  it("keeps user.backfill out of subscription-change despite the user. prefix", async () => {
    // Order-dependent: both rules match on a `user.` prefix, and the backfill
    // check has to win.
    expect(await categoryOf("user.backfill.create-users-doc")).toBe(
      "backend-job",
    );
  });

  it("still recognises a role change", async () => {
    expect(await categoryOf("role-change")).toBe("role-change");
  });

  it("leaves genuine admin actions in admin-action", async () => {
    // The catch-all must stay a catch-all: these are real operator decisions,
    // not misfiled automation.
    for (const action of [
      "account-status-change",
      "report-resolution",
      "feedback-triage",
      "error-triage",
      "documents.upload",
      "newsletter.campaign.create",
      "leaderboard.recalculation.request",
      "user.progression.xp.adjust",
      "user.avatar.clear",
      "something.entirely.new",
      null,
    ]) {
      expect(await categoryOf(action)).toBe("admin-action");
    }
  });

  it("does not derive a plan-publish category", async () => {
    // No plan-publication pipeline exists, so a stale document carrying the
    // old action must fall through to the catch-all rather than resurrect a
    // filter option that cannot occur.
    expect(await categoryOf("plan-publish")).toBe("admin-action");
  });
});
