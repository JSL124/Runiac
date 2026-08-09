// Unit tests for deleteAvatarObject() in ../storage.ts — the dedicated,
// path-validated delete helper the avatar takedown flow uses instead of
// deleteProjectDocumentFile() (which has no shape check at all).
//
// Only the external firebase-admin/storage dependency (and the two small
// config accessors getAdminBucket() calls) are mocked; the real storage.ts
// module runs unmocked, so this exercises the actual isAvatarObjectPath()
// gate rather than a stand-in for it. The critical assertion below is that a
// poisoned path pointing at project-documents/, feed-thumbnails/, or
// share-cards/ never reaches the fake bucket at all — not just that the
// function *reports* a skip.

import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  fileMock,
  bucketMock,
  existsMock,
  deleteMock,
  getAdminAppMock,
  getFirebaseStorageBucketMock,
} = vi.hoisted(() => ({
  fileMock: vi.fn(),
  bucketMock: vi.fn(),
  existsMock: vi.fn(),
  deleteMock: vi.fn(),
  getAdminAppMock: vi.fn(),
  getFirebaseStorageBucketMock: vi.fn(),
}));

vi.mock("@/lib/firebase/admin", () => ({
  getAdminApp: getAdminAppMock,
}));

vi.mock("@/lib/firebase/config", () => ({
  getFirebaseStorageBucket: getFirebaseStorageBucketMock,
}));

vi.mock("firebase-admin/storage", () => ({
  getStorage: () => ({ bucket: bucketMock }),
}));

import { deleteAvatarObject } from "../storage";

const VALID_PATH = `avatars/${"a".repeat(32)}.png`;

describe("deleteAvatarObject", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getAdminAppMock.mockReturnValue({});
    getFirebaseStorageBucketMock.mockReturnValue("test-bucket.appspot.com");
    bucketMock.mockReturnValue({ file: fileMock });
    fileMock.mockReturnValue({ exists: existsMock, delete: deleteMock });
    existsMock.mockResolvedValue([true]);
    deleteMock.mockResolvedValue(undefined);
  });

  it("deletes a valid, existing avatar object", async () => {
    const result = await deleteAvatarObject(VALID_PATH);

    expect(fileMock).toHaveBeenCalledWith(VALID_PATH);
    expect(deleteMock).toHaveBeenCalledWith({ ignoreNotFound: true });
    expect(result).toEqual({ ok: true, existed: true });
  });

  it("reports 'missing' (not an error) when the object no longer exists", async () => {
    existsMock.mockResolvedValue([false]);

    const result = await deleteAvatarObject(VALID_PATH);

    expect(result).toEqual({ ok: true, existed: false });
  });

  it.each([
    "project-documents/some-doc-id/architecture.pdf",
    "feed-thumbnails/some-uid/photo.jpg",
    "share-cards/some-uid/card.png",
    "avatar-staging/some-uid/upload.png",
    "avatars/not-32-hex-chars.png",
    "../../etc/passwd",
  ])(
    "skips a poisoned/mismatched path without ever calling the storage bucket: %s",
    async (poisonedPath) => {
      const result = await deleteAvatarObject(poisonedPath);

      expect(result).toEqual({ ok: false, reason: "invalid-path" });
      // This is the load-bearing assertion: the underlying Storage delete
      // call must never be reached for a path that didn't pass
      // isAvatarObjectPath(), regardless of what it reports back.
      expect(bucketMock).not.toHaveBeenCalled();
      expect(fileMock).not.toHaveBeenCalled();
      expect(deleteMock).not.toHaveBeenCalled();
    },
  );

  it("reports a distinct error outcome when the Storage delete call itself rejects", async () => {
    deleteMock.mockRejectedValue(new Error("simulated Storage outage"));

    const result = await deleteAvatarObject(VALID_PATH);

    expect(result).toEqual({
      ok: false,
      reason: "error",
      error: "simulated Storage outage",
    });
  });
});
