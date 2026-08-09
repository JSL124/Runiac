// Unit tests for the clearUserAvatar() server action in ../admin.ts —
// the admin-console-facing "takedown" control. Modeled on the
// requireAdmin()/hasFirebaseEnv()/reason-validation contract every sibling
// action in that file follows (setUserXp, setUserSubscription, ...).
//
// The heavier avatar-clearing logic itself (deleting both Storage
// generations, clearing the four Firestore fields, handling a poisoned
// path) is exercised separately in
// src/lib/firebase/__tests__/firestore.avatar.test.ts against the real
// src/lib/firebase/firestore.ts implementation. Here, that implementation
// is mocked out (clearUserAvatar as clearUserAvatarInDb) so this file only
// asserts the action-layer contract: reason/auth/live-mode gating, and that
// a successful takedown triggers the same best-effort leaderboard refresh
// setUserSubscription()/the progression actions do.

import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  requireAdminMock,
  hasFirebaseEnvMock,
  clearUserAvatarInDbMock,
  requestLeaderboardRecalculationInDbMock,
} = vi.hoisted(() => ({
  requireAdminMock: vi.fn(),
  hasFirebaseEnvMock: vi.fn(),
  clearUserAvatarInDbMock: vi.fn(),
  requestLeaderboardRecalculationInDbMock: vi.fn(),
}));

vi.mock("@/lib/actions/require-admin", () => ({
  requireAdmin: requireAdminMock,
}));

vi.mock("@/lib/firebase/config", () => ({
  hasFirebaseEnv: hasFirebaseEnvMock,
}));

vi.mock("@/lib/firebase/firestore", async () => {
  const actual = await vi.importActual<typeof import("@/lib/firebase/firestore")>(
    "@/lib/firebase/firestore",
  );
  return {
    ...actual,
    clearUserAvatar: clearUserAvatarInDbMock,
    requestLeaderboardRecalculation: requestLeaderboardRecalculationInDbMock,
  };
});

import { clearUserAvatar } from "../admin";

describe("clearUserAvatar (admin action)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    requireAdminMock.mockResolvedValue({
      ok: true,
      admin: { uid: "admin-uid", email: "admin@example.com" },
    });
    hasFirebaseEnvMock.mockReturnValue(true);
    clearUserAvatarInDbMock.mockResolvedValue({
      hadAvatar: true,
      currentPathOutcome: "deleted",
      previousPathOutcome: null,
    });
    requestLeaderboardRecalculationInDbMock.mockResolvedValue("command-1");
  });

  it("rejects an empty reason without calling the backend at all", async () => {
    const result = await clearUserAvatar("u1", "   ");

    expect(result).toEqual({
      ok: false,
      error: "A reason is required for this action.",
    });
    expect(requireAdminMock).not.toHaveBeenCalled();
    expect(clearUserAvatarInDbMock).not.toHaveBeenCalled();
  });

  it("rejects a missing uid", async () => {
    const result = await clearUserAvatar("", "policy violation");

    expect(result).toEqual({ ok: false, error: "Missing user id." });
    expect(clearUserAvatarInDbMock).not.toHaveBeenCalled();
  });

  it("rejects a non-admin caller without touching the backend", async () => {
    requireAdminMock.mockResolvedValue({
      ok: false,
      error: "You are not authorized to perform this action.",
    });

    const result = await clearUserAvatar("u1", "policy violation");

    expect(result).toEqual({
      ok: false,
      error: "You are not authorized to perform this action.",
    });
    expect(clearUserAvatarInDbMock).not.toHaveBeenCalled();
  });

  it("skips the backend and reports live:false when Firebase is not configured", async () => {
    hasFirebaseEnvMock.mockReturnValue(false);

    const result = await clearUserAvatar("u1", "policy violation");

    expect(result).toEqual({ ok: true, live: false });
    expect(clearUserAvatarInDbMock).not.toHaveBeenCalled();
  });

  it("on success, calls through with the trimmed reason and a stable audit action name, then refreshes the leaderboard", async () => {
    const result = await clearUserAvatar("u1", "  policy violation  ");

    expect(clearUserAvatarInDbMock).toHaveBeenCalledWith(
      "u1",
      "admin@example.com",
      "policy violation",
      "user.avatar.clear",
    );
    expect(requestLeaderboardRecalculationInDbMock).toHaveBeenCalled();
    expect(result).toEqual({ ok: true, live: true });
  });

  it("reports a failure result when the backend mutation throws, without crashing", async () => {
    clearUserAvatarInDbMock.mockRejectedValue(new Error("Firestore write failed"));

    const result = await clearUserAvatar("u1", "policy violation");

    expect(result).toEqual({
      ok: false,
      error: "The backend rejected this avatar takedown. Try again.",
    });
  });

  it("does not fail the action when the follow-up leaderboard refresh itself fails", async () => {
    requestLeaderboardRecalculationInDbMock.mockRejectedValue(
      new Error("recalculation command write failed"),
    );

    const result = await clearUserAvatar("u1", "policy violation");

    expect(result).toEqual({ ok: true, live: true });
  });
});
