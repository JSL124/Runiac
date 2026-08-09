// Unit tests for the avatar takedown logic in ../firestore.ts:
// clearUserAvatar() (the shared routine) and its wiring into
// setUserAccountStatus()/setUserModeration() (the suspend/ban side effect).
//
// Only the two real dependencies — @/lib/firebase/admin (getAdminDb/
// getAdminAuth) and ./storage (deleteAvatarObject) — are mocked. The real
// firestore.ts module runs unmocked, including its use of the real
// isAvatarObjectPath() validator (via @/lib/avatarPaths) and the real
// FieldValue.delete() sentinel, so this exercises the actual merge/audit
// logic rather than a stand-in for it. getAdminDb() is backed by a small
// in-memory fake Firestore (collection -> doc id -> plain object) that
// understands FieldValue.delete() during a merge write, so field-removal can
// be asserted by reading the doc back rather than by pattern-matching the
// write call's arguments.

import { FieldValue } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  getAdminDbMock,
  getAdminAuthMock,
  updateUserMock,
  revokeRefreshTokensMock,
  deleteAvatarObjectMock,
} = vi.hoisted(() => ({
  getAdminDbMock: vi.fn(),
  getAdminAuthMock: vi.fn(),
  updateUserMock: vi.fn(),
  revokeRefreshTokensMock: vi.fn(),
  deleteAvatarObjectMock: vi.fn(),
}));

vi.mock("../admin", () => ({
  getAdminDb: getAdminDbMock,
  getAdminAuth: getAdminAuthMock,
}));

vi.mock("../storage", () => ({
  deleteAvatarObject: deleteAvatarObjectMock,
}));

import {
  clearUserAvatar,
  setUserAccountStatus,
  setUserModeration,
} from "../firestore";

type FakeDoc = Record<string, unknown>;

function isDeleteSentinel(value: unknown): boolean {
  if (value === null || typeof value !== "object") {
    return false;
  }
  const candidate = value as { isEqual?: (other: FieldValue) => boolean };
  return (
    typeof candidate.isEqual === "function" &&
    FieldValue.delete().isEqual(value as FieldValue)
  );
}

// Minimal fake Firestore: enough of collection().doc().get()/.set({merge})
// and collection("adminAuditLogs").add() for the functions under test, with
// real FieldValue.delete() semantics during a merge (delete the key rather
// than store the sentinel).
function createFakeFirestore() {
  const stores = new Map<string, Map<string, FakeDoc>>();
  const auditLogs: FakeDoc[] = [];

  function storeFor(name: string): Map<string, FakeDoc> {
    let store = stores.get(name);
    if (!store) {
      store = new Map();
      stores.set(name, store);
    }
    return store;
  }

  function applyMerge(existing: FakeDoc, patch: FakeDoc): FakeDoc {
    const next: FakeDoc = { ...existing };
    for (const [key, value] of Object.entries(patch)) {
      if (isDeleteSentinel(value)) {
        delete next[key];
      } else {
        next[key] = value;
      }
    }
    return next;
  }

  const db = {
    collection(name: string) {
      if (name === "adminAuditLogs") {
        return {
          add: async (record: FakeDoc) => {
            auditLogs.push(record);
            return { id: `audit-${auditLogs.length}` };
          },
        };
      }

      return {
        doc(id: string) {
          return {
            get: async () => {
              const data = storeFor(name).get(id);
              return { exists: data !== undefined, data: () => data };
            },
            set: async (data: FakeDoc, options?: { merge?: boolean }) => {
              const store = storeFor(name);
              const existing = store.get(id) ?? {};
              store.set(id, options?.merge ? applyMerge(existing, data) : data);
            },
          };
        },
      };
    },
  } as unknown as Firestore;

  return {
    db,
    auditLogs,
    seed: (collectionName: string, id: string, data: FakeDoc) => {
      storeFor(collectionName).set(id, data);
    },
    read: (collectionName: string, id: string) => storeFor(collectionName).get(id),
  };
}

const VALID_CURRENT_PATH = `avatars/${"1".repeat(32)}.png`;
const VALID_PREVIOUS_PATH = `avatars/${"2".repeat(32)}.png`;
const POISONED_PATH = "project-documents/some-doc/file.pdf";

describe("clearUserAvatar", () => {
  let fake: ReturnType<typeof createFakeFirestore>;

  beforeEach(() => {
    vi.clearAllMocks();
    fake = createFakeFirestore();
    getAdminDbMock.mockReturnValue(fake.db);
    deleteAvatarObjectMock.mockResolvedValue({ ok: true, existed: true });
  });

  it("deletes both object paths and clears all four fields", async () => {
    fake.seed("userProfiles", "u1", {
      avatarUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/avatars%2F1.png?alt=media&token=t",
      avatarObjectPath: VALID_CURRENT_PATH,
      avatarPreviousObjectPath: VALID_PREVIOUS_PATH,
      avatarUpdatedAt: "2026-07-01T00:00:00.000Z",
      displayName: "Test Runner",
    });

    const result = await clearUserAvatar(
      "u1",
      "admin@example.com",
      "policy violation",
      "user.avatar.clear",
    );

    expect(deleteAvatarObjectMock).toHaveBeenCalledWith(VALID_CURRENT_PATH);
    expect(deleteAvatarObjectMock).toHaveBeenCalledWith(VALID_PREVIOUS_PATH);
    expect(deleteAvatarObjectMock).toHaveBeenCalledTimes(2);
    expect(result).toEqual({
      hadAvatar: true,
      currentPathOutcome: "deleted",
      previousPathOutcome: "deleted",
    });

    const stored = fake.read("userProfiles", "u1");
    expect(stored?.avatarUrl).toBeUndefined();
    expect(stored?.avatarObjectPath).toBeUndefined();
    expect(stored?.avatarPreviousObjectPath).toBeUndefined();
    expect(stored?.avatarUpdatedAt).toBeUndefined();
    // An untouched field on the same document survives the merge.
    expect(stored?.displayName).toBe("Test Runner");

    expect(fake.auditLogs).toHaveLength(1);
    expect(fake.auditLogs[0]).toMatchObject({
      actor: "admin@example.com",
      action: "user.avatar.clear",
      targetType: "user",
      targetId: "u1",
    });
  });

  it("works when only a current path exists (no previous generation)", async () => {
    fake.seed("userProfiles", "u2", { avatarObjectPath: VALID_CURRENT_PATH });

    const result = await clearUserAvatar(
      "u2",
      "admin@example.com",
      "reason",
      "user.avatar.clear",
    );

    expect(deleteAvatarObjectMock).toHaveBeenCalledTimes(1);
    expect(deleteAvatarObjectMock).toHaveBeenCalledWith(VALID_CURRENT_PATH);
    expect(result).toEqual({
      hadAvatar: true,
      currentPathOutcome: "deleted",
      previousPathOutcome: null,
    });
    expect(fake.read("userProfiles", "u2")?.avatarObjectPath).toBeUndefined();
  });

  it("is a safe no-op that still audits when there is no avatar at all", async () => {
    fake.seed("userProfiles", "u3", { displayName: "No Photo" });

    const result = await clearUserAvatar(
      "u3",
      "admin@example.com",
      "reason",
      "user.avatar.clear",
    );

    expect(deleteAvatarObjectMock).not.toHaveBeenCalled();
    expect(result).toEqual({
      hadAvatar: false,
      currentPathOutcome: null,
      previousPathOutcome: null,
    });
    expect(fake.auditLogs).toHaveLength(1);
    // The write still runs (harmlessly) even though nothing needed clearing.
    expect(fake.read("userProfiles", "u3")?.displayName).toBe("No Photo");
  });

  it("skips a poisoned avatarObjectPath without ever calling the storage helper, still clears the field, and audits the skip", async () => {
    fake.seed("userProfiles", "u4", { avatarObjectPath: POISONED_PATH });

    const result = await clearUserAvatar(
      "u4",
      "admin@example.com",
      "cleanup",
      "user.avatar.clear",
    );

    // Load-bearing: the poisoned path must never reach deleteAvatarObject().
    expect(deleteAvatarObjectMock).not.toHaveBeenCalled();
    expect(result.currentPathOutcome).toBe("skipped-invalid");

    // The field is still cleared even though the object delete was skipped.
    expect(fake.read("userProfiles", "u4")?.avatarObjectPath).toBeUndefined();

    // The skip is visible in the audit trail, not silently dropped.
    expect(String(fake.auditLogs[0]?.detail)).toMatch(/SKIPPED/);
  });

  it("rejects poisoned paths under any of the other reserved bucket prefixes", async () => {
    for (const [id, poisoned] of [
      ["u4a", "feed-thumbnails/some-uid/photo.jpg"],
      ["u4b", "share-cards/some-uid/card.png"],
    ] as const) {
      fake.seed("userProfiles", id, { avatarObjectPath: poisoned });

      const result = await clearUserAvatar(
        id,
        "admin@example.com",
        "cleanup",
        "user.avatar.clear",
      );

      expect(result.currentPathOutcome).toBe("skipped-invalid");
    }

    expect(deleteAvatarObjectMock).not.toHaveBeenCalled();
  });
});

describe("suspension/ban wiring clears the avatar", () => {
  let fake: ReturnType<typeof createFakeFirestore>;

  beforeEach(() => {
    vi.clearAllMocks();
    fake = createFakeFirestore();
    getAdminDbMock.mockReturnValue(fake.db);
    getAdminAuthMock.mockReturnValue({
      updateUser: updateUserMock,
      revokeRefreshTokens: revokeRefreshTokensMock,
    });
    updateUserMock.mockResolvedValue(undefined);
    revokeRefreshTokensMock.mockResolvedValue(undefined);
    deleteAvatarObjectMock.mockResolvedValue({ ok: true, existed: true });
  });

  it("setUserAccountStatus clears the avatar when the status transitions to suspended", async () => {
    fake.seed("userProfiles", "u5", { avatarObjectPath: VALID_CURRENT_PATH });

    await setUserAccountStatus("u5", "suspended", "admin@example.com");

    expect(deleteAvatarObjectMock).toHaveBeenCalledWith(VALID_CURRENT_PATH);
    expect(fake.read("users", "u5")?.accountStatus).toBe("suspended");
    expect(fake.read("userProfiles", "u5")?.avatarObjectPath).toBeUndefined();
    expect(
      fake.auditLogs.some((entry) => entry.action === "user.avatar.clearOnLockout"),
    ).toBe(true);
  });

  it("setUserAccountStatus does not touch the avatar when restoring to active", async () => {
    fake.seed("userProfiles", "u6", { avatarObjectPath: VALID_CURRENT_PATH });

    await setUserAccountStatus("u6", "active", "admin@example.com");

    expect(deleteAvatarObjectMock).not.toHaveBeenCalled();
    expect(fake.read("userProfiles", "u6")?.avatarObjectPath).toBe(VALID_CURRENT_PATH);
  });

  it("an avatar-clear failure does not abort the suspension", async () => {
    fake.seed("userProfiles", "u7", { avatarObjectPath: VALID_CURRENT_PATH });
    deleteAvatarObjectMock.mockResolvedValue({
      ok: false,
      reason: "error",
      error: "Storage outage",
    });

    await expect(
      setUserAccountStatus("u7", "banned", "admin@example.com"),
    ).resolves.toBeUndefined();

    expect(fake.read("users", "u7")?.accountStatus).toBe("banned");
    expect(
      fake.auditLogs.some(
        (entry) => entry.action === "user.avatar.clearOnLockout.failed",
      ),
    ).toBe(true);
  });

  it("setUserModeration clears the avatar on a suspend action", async () => {
    fake.seed("userProfiles", "u8", { avatarObjectPath: VALID_CURRENT_PATH });

    await setUserModeration(
      "u8",
      "suspend",
      "admin@example.com",
      "reported abuse",
      { accountStatus: null },
    );

    expect(deleteAvatarObjectMock).toHaveBeenCalledWith(VALID_CURRENT_PATH);
    expect(fake.read("users", "u8")?.accountStatus).toBe("suspended");
    expect(fake.read("userProfiles", "u8")?.avatarObjectPath).toBeUndefined();
  });

  it("setUserModeration does not touch the avatar on a warn action", async () => {
    fake.seed("userProfiles", "u9", { avatarObjectPath: VALID_CURRENT_PATH });

    await setUserModeration(
      "u9",
      "warn",
      "admin@example.com",
      "minor issue",
      { accountStatus: null },
    );

    expect(deleteAvatarObjectMock).not.toHaveBeenCalled();
  });
});
