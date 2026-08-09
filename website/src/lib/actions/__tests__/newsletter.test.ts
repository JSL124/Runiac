// Unit tests for src/lib/actions/newsletter.ts — the admin-console-facing
// newsletter server actions. Modeled on admin.avatar.test.ts: the Firestore
// layer is mocked out so this file only asserts the action-layer contract
// (validation, requireAdmin()/hasFirebaseEnv() gating, and the two
// invariants the task description calls out explicitly — a test send always
// targets the caller's own email, and a subscriber can never be promoted to
// "confirmed" from here, only deleted).

import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  requireAdminMock,
  hasFirebaseEnvMock,
  createNewsletterCampaignMock,
  updateNewsletterCampaignDraftMock,
  queueNewsletterCampaignTestMock,
  queueNewsletterCampaignSendMock,
  deleteNewsletterSubscriberInDbMock,
  listNewsletterCampaignDeliveriesMock,
} = vi.hoisted(() => ({
  requireAdminMock: vi.fn(),
  hasFirebaseEnvMock: vi.fn(),
  createNewsletterCampaignMock: vi.fn(),
  updateNewsletterCampaignDraftMock: vi.fn(),
  queueNewsletterCampaignTestMock: vi.fn(),
  queueNewsletterCampaignSendMock: vi.fn(),
  deleteNewsletterSubscriberInDbMock: vi.fn(),
  listNewsletterCampaignDeliveriesMock: vi.fn(),
}));

vi.mock("@/lib/actions/require-admin", () => ({
  requireAdmin: requireAdminMock,
}));

vi.mock("@/lib/firebase/config", () => ({
  hasFirebaseEnv: hasFirebaseEnvMock,
}));

vi.mock("@/lib/firebase/firestore", () => ({
  createNewsletterCampaign: createNewsletterCampaignMock,
  updateNewsletterCampaignDraft: updateNewsletterCampaignDraftMock,
  queueNewsletterCampaignTest: queueNewsletterCampaignTestMock,
  queueNewsletterCampaignSend: queueNewsletterCampaignSendMock,
  deleteNewsletterSubscriber: deleteNewsletterSubscriberInDbMock,
  listNewsletterCampaignDeliveries: listNewsletterCampaignDeliveriesMock,
}));

import {
  deleteNewsletterSubscriber,
  saveNewsletterCampaignDraft,
  sendNewsletterCampaign,
  sendTestNewsletterCampaign,
} from "../newsletter";

const ADMIN = { uid: "admin-uid", email: "admin@example.com" };

describe("newsletter admin actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    requireAdminMock.mockResolvedValue({ ok: true, admin: ADMIN });
    hasFirebaseEnvMock.mockReturnValue(true);
    createNewsletterCampaignMock.mockResolvedValue("camp-new");
    updateNewsletterCampaignDraftMock.mockResolvedValue(undefined);
    queueNewsletterCampaignTestMock.mockResolvedValue(undefined);
    queueNewsletterCampaignSendMock.mockResolvedValue(undefined);
    deleteNewsletterSubscriberInDbMock.mockResolvedValue(undefined);
    listNewsletterCampaignDeliveriesMock.mockResolvedValue([]);
  });

  describe("saveNewsletterCampaignDraft", () => {
    it("rejects an empty subject without calling the backend or requireAdmin", async () => {
      const result = await saveNewsletterCampaignDraft(null, "   ", "body");

      expect(result).toEqual({
        ok: false,
        error: "Subject must be between 1 and 200 characters.",
      });
      expect(requireAdminMock).not.toHaveBeenCalled();
      expect(createNewsletterCampaignMock).not.toHaveBeenCalled();
    });

    it("rejects a subject over 200 characters", async () => {
      const result = await saveNewsletterCampaignDraft(null, "a".repeat(201), "body");

      expect(result.ok).toBe(false);
      expect(createNewsletterCampaignMock).not.toHaveBeenCalled();
    });

    it("rejects an empty body", async () => {
      const result = await saveNewsletterCampaignDraft(null, "Subject", "   ");

      expect(result).toEqual({
        ok: false,
        error: "The campaign body cannot be empty.",
      });
      expect(createNewsletterCampaignMock).not.toHaveBeenCalled();
    });

    it("rejects a non-admin caller without touching the backend", async () => {
      requireAdminMock.mockResolvedValue({
        ok: false,
        error: "You are not authorized to perform this action.",
      });

      const result = await saveNewsletterCampaignDraft(null, "Subject", "Body");

      expect(result).toEqual({
        ok: false,
        error: "You are not authorized to perform this action.",
      });
      expect(createNewsletterCampaignMock).not.toHaveBeenCalled();
    });

    it("skips the backend and reports live:false when Firebase is not configured", async () => {
      hasFirebaseEnvMock.mockReturnValue(false);

      const result = await saveNewsletterCampaignDraft(null, "Subject", "Body");

      expect(result).toEqual({ ok: true, live: false, campaignId: undefined });
      expect(createNewsletterCampaignMock).not.toHaveBeenCalled();
    });

    it("creates a new campaign when no campaignId is given", async () => {
      const result = await saveNewsletterCampaignDraft(null, "  Subject  ", "  Body  ");

      expect(createNewsletterCampaignMock).toHaveBeenCalledWith(
        "Subject",
        "Body",
        ADMIN.email,
      );
      expect(result).toEqual({ ok: true, live: true, campaignId: "camp-new" });
    });

    it("edits an existing draft when campaignId is given", async () => {
      const result = await saveNewsletterCampaignDraft("camp-1", "Subject", "Body");

      expect(updateNewsletterCampaignDraftMock).toHaveBeenCalledWith(
        "camp-1",
        "Subject",
        "Body",
        ADMIN.email,
      );
      expect(createNewsletterCampaignMock).not.toHaveBeenCalled();
      expect(result).toEqual({ ok: true, live: true, campaignId: "camp-1" });
    });

    it("surfaces the backend's rejection message (e.g. campaign no longer a draft)", async () => {
      updateNewsletterCampaignDraftMock.mockRejectedValue(
        new Error("Only a draft campaign can be edited."),
      );

      const result = await saveNewsletterCampaignDraft("camp-1", "Subject", "Body");

      expect(result).toEqual({
        ok: false,
        error: "Only a draft campaign can be edited.",
      });
    });
  });

  describe("sendTestNewsletterCampaign", () => {
    it("rejects a missing campaign id without calling the backend", async () => {
      const result = await sendTestNewsletterCampaign("");

      expect(result).toEqual({ ok: false, error: "Missing campaign id." });
      expect(requireAdminMock).not.toHaveBeenCalled();
    });

    // The whole point of this action: the test recipient is derived from the
    // authenticated admin identity, never from a client-supplied argument —
    // there is no address parameter on this function's signature at all.
    it("queues the test using only the caller's own admin email as the recipient", async () => {
      const result = await sendTestNewsletterCampaign("camp-1");

      expect(queueNewsletterCampaignTestMock).toHaveBeenCalledWith(
        "camp-1",
        ADMIN.email,
      );
      expect(result).toEqual({ ok: true, live: true });
    });

    it("reports a failure result when the backend rejects the test send", async () => {
      queueNewsletterCampaignTestMock.mockRejectedValue(
        new Error("Only a draft campaign can be sent as a test."),
      );

      const result = await sendTestNewsletterCampaign("camp-1");

      expect(result).toEqual({
        ok: false,
        error: "Only a draft campaign can be sent as a test.",
      });
    });
  });

  describe("sendNewsletterCampaign", () => {
    it("rejects a missing campaign id", async () => {
      const result = await sendNewsletterCampaign("");
      expect(result).toEqual({ ok: false, error: "Missing campaign id." });
    });

    it("queues the real send", async () => {
      const result = await sendNewsletterCampaign("camp-1");

      expect(queueNewsletterCampaignSendMock).toHaveBeenCalledWith(
        "camp-1",
        ADMIN.email,
      );
      expect(result).toEqual({ ok: true, live: true });
    });

    it("cannot queue the same campaign twice — surfaces the backend's guard", async () => {
      queueNewsletterCampaignSendMock.mockRejectedValue(
        new Error(
          "This campaign has already been queued or sent and cannot be sent again.",
        ),
      );

      const result = await sendNewsletterCampaign("camp-1");

      expect(result.ok).toBe(false);
    });
  });

  describe("deleteNewsletterSubscriber", () => {
    it("rejects a missing subscriber id", async () => {
      const result = await deleteNewsletterSubscriber("");
      expect(result).toEqual({ ok: false, error: "Missing subscriber id." });
      expect(deleteNewsletterSubscriberInDbMock).not.toHaveBeenCalled();
    });

    it("rejects a non-admin caller", async () => {
      requireAdminMock.mockResolvedValue({
        ok: false,
        error: "You are not authorized to perform this action.",
      });

      const result = await deleteNewsletterSubscriber("sub-1");

      expect(result.ok).toBe(false);
      expect(deleteNewsletterSubscriberInDbMock).not.toHaveBeenCalled();
    });

    it("deletes on success", async () => {
      const result = await deleteNewsletterSubscriber("sub-1");

      expect(deleteNewsletterSubscriberInDbMock).toHaveBeenCalledWith(
        "sub-1",
        ADMIN.email,
      );
      expect(result).toEqual({ ok: true, live: true });
    });

    // There is deliberately no sibling "setSubscriberStatus" / "confirm"
    // action exported from this module at all — this test documents that
    // invariant so a future addition has to consciously break it.
    it("exposes no subscriber-status-promotion action", async () => {
      const newsletterActions = await import("../newsletter");
      expect(
        Object.keys(newsletterActions).some((name) =>
          /confirm|promote|setStatus/i.test(name),
        ),
      ).toBe(false);
    });
  });
});
