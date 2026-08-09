import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  AVATAR_REPLACE_COOLDOWN_MS,
  AVATAR_REPLACE_COOLDOWN_REASON,
  clearProfileAvatar,
  setProfileAvatar,
  type ProfileAvatarPorts,
  type ProfileAvatarProfileSnapshot,
  type ProfileAvatarStoredObject,
  type ProfileAvatarTransactionPort,
} from "../src/profile/avatar/core.js";
import { isAvatarObjectPath, newAvatarObjectPath } from "../src/profile/avatar/avatarPaths.js";

const uid = "alice";
const stagingPath = "avatar-staging/alice/upload-a.png";

describe("Profile avatar core", () => {
  it("rejects an unauthenticated request", async () => {
    const ports = fakePorts();
    await rejects(() => setProfileAvatar({ data: request() }, ports), "unauthenticated");
    await rejects(() => clearProfileAvatar({ data: undefined }, ports), "unauthenticated");
  });

  it("rejects a staging path owned by another uid", async () => {
    const ports = fakePorts();
    await rejects(
      () => setProfileAvatar({ auth: { uid }, data: { stagingPath: "avatar-staging/other/upload-a.png" } }, ports),
      "invalid-argument",
    );
  });

  it("rejects a staging path with a bad shape or traversal", async () => {
    const ports = fakePorts();
    for (const badPath of [
      "avatar-staging/alice/../upload-a.png",
      "avatar-staging/alice/nested/upload-a.png",
      "avatar-staging/alice/upload-a.jpg",
      "feed-thumbnail-staging/alice/upload-a.png",
    ]) {
      await rejects(() => setProfileAvatar({ auth: { uid }, data: { stagingPath: badPath } }, ports), "invalid-argument");
    }
  });

  it("rejects an unsupported or malformed payload shape", async () => {
    const ports = fakePorts();
    for (const data of [undefined, {}, { stagingPath, extra: true }, { stagingPath: 42 }, { stagingPath: "" }]) {
      await rejects(() => setProfileAvatar({ auth: { uid }, data }, ports), "invalid-argument");
    }
  });

  it("rejects wrong content type, wrong metadata keys, wrong metadata.ownerUid, and bad PNG bytes", async () => {
    const ports = fakePorts();
    for (const object of [
      stored({ contentType: "image/jpeg" }),
      stored({ metadata: {} }),
      stored({ metadata: { ownerUid: uid, extra: "x" } }),
      stored({ metadata: { ownerUid: "other" } }),
      stored({ bytes: png(255, 255) }),
      stored({ bytes: png(512, 512) }),
    ]) {
      ports.staging.set(stagingPath, object);
      await rejects(() => setProfileAvatar({ auth: { uid }, data: request() }, ports), "failed-precondition");
      assert.equal(ports.avatars.size, 0, "no object may be promoted for an unsafe staged upload");
    }
  });

  it("accepts Firebase-managed staging download-token metadata", async () => {
    const ports = fakePorts();
    ports.staging.set(stagingPath, stored({ metadata: { ownerUid: uid, firebaseStorageDownloadTokens: "managed-token" } }));
    const result = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    assert.match(result.avatarUrl, /^https:\/\//);
  });

  it("rejects a suspended account, promotes nothing durable, and never touches Storage", async () => {
    const ports = fakePorts();
    ports.suspended = true;
    await rejects(() => setProfileAvatar({ auth: { uid }, data: request() }, ports), "permission-denied");
    assert.equal(ports.profile?.avatarObjectPath, undefined);
    assert.equal(ports.copyCreateOnlyCallCount, 0, "the cheap pre-check must reject before the expensive Storage copy runs");
    await rejects(() => clearProfileAvatar({ auth: { uid }, data: undefined }, ports), "permission-denied");
  });

  it("rejects when the profile document does not exist, and never touches Storage", async () => {
    const ports = fakePorts();
    ports.profile = { exists: false, avatarObjectPath: undefined, avatarPreviousObjectPath: undefined, avatarUpdatedAtMs: undefined };
    await rejects(() => setProfileAvatar({ auth: { uid }, data: request() }, ports), "failed-precondition");
    assert.equal(ports.copyCreateOnlyCallCount, 0, "the cheap pre-check must reject before the expensive Storage copy runs");
    await rejects(() => clearProfileAvatar({ auth: { uid }, data: undefined }, ports), "failed-precondition");
  });

  it("enforces the replace cooldown and allows the replace once the window has passed", async () => {
    const ports = fakePorts();
    const firstUpload = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    assert.match(firstUpload.avatarUrl, /^https:\/\//);
    const updatedAtMs = ports.profile?.avatarUpdatedAtMs;
    assert.notEqual(updatedAtMs, undefined);

    ports.staging.set(stagingPath, stored());
    ports.nowMs = (updatedAtMs ?? 0) + AVATAR_REPLACE_COOLDOWN_MS - 1;
    const copyCountBeforeCooldownAttempt = ports.copyCreateOnlyCallCount;
    await rejects(
      () => setProfileAvatar({ auth: { uid }, data: request() }, ports),
      "failed-precondition",
      AVATAR_REPLACE_COOLDOWN_REASON,
    );
    assert.equal(
      ports.copyCreateOnlyCallCount,
      copyCountBeforeCooldownAttempt,
      "a cooldown-blocked call must never mint an orphaned avatars/ object via the expensive Storage copy",
    );

    ports.staging.set(stagingPath, stored());
    ports.nowMs = (updatedAtMs ?? 0) + AVATAR_REPLACE_COOLDOWN_MS;
    const secondUpload = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    assert.match(secondUpload.avatarUrl, /^https:\/\//);
  });

  it("issues exactly one copyCreateOnly call on the happy path", async () => {
    const ports = fakePorts();
    await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    assert.equal(ports.copyCreateOnlyCallCount, 1);
  });

  it("on first upload, avatarPreviousObjectPath is absent and nothing is deleted except staging", async () => {
    const ports = fakePorts();
    await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    assert.equal(ports.profile?.avatarPreviousObjectPath, undefined);
    assert.deepEqual(ports.deletedPaths, [stagingPath]);
  });

  it("on replace, the object deleted is exactly the one that was in avatarPreviousObjectPath, and the immediately-previous object is NOT deleted", async () => {
    const ports = fakePorts();
    const first = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    const firstObjectPath = pathFromUrl(first.avatarUrl);

    ports.staging.set(stagingPath, stored());
    ports.nowMs += AVATAR_REPLACE_COOLDOWN_MS;
    const second = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    const secondObjectPath = pathFromUrl(second.avatarUrl);
    assert.equal(ports.profile?.avatarObjectPath, secondObjectPath);
    assert.equal(ports.profile?.avatarPreviousObjectPath, firstObjectPath);
    // The first generation has nothing before it, so nothing was deleted yet.
    assert.equal(ports.deletedPaths.includes(firstObjectPath), false);

    ports.staging.set(stagingPath, stored());
    ports.nowMs += AVATAR_REPLACE_COOLDOWN_MS;
    const third = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    const thirdObjectPath = pathFromUrl(third.avatarUrl);
    assert.equal(ports.profile?.avatarObjectPath, thirdObjectPath);
    assert.equal(ports.profile?.avatarPreviousObjectPath, secondObjectPath);
    // The generation two replaces ago (first) must now be deleted...
    assert.equal(ports.deletedPaths.includes(firstObjectPath), true);
    // ...but the immediately-previous generation (second) must NOT be.
    assert.equal(ports.deletedPaths.includes(secondObjectPath), false);
  });

  it("clears fields but issues no delete call for a poisoned stored avatarPreviousObjectPath", async () => {
    for (const poisoned of ["project-documents/x.pdf", "feed-thumbnails/a/b/c.png", "../../etc/passwd"]) {
      const ports = fakePorts();
      const first = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
      const firstObjectPath = pathFromUrl(first.avatarUrl);
      // Simulate a poisoned/foreign value having ended up in
      // avatarPreviousObjectPath (defence-in-depth only: this field is
      // backend-owned and should never actually hold a foreign path).
      assert.ok(ports.profile);
      ports.profile = { ...ports.profile, avatarPreviousObjectPath: poisoned };

      ports.staging.set(stagingPath, stored());
      ports.nowMs += AVATAR_REPLACE_COOLDOWN_MS;
      const second = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
      const secondObjectPath = pathFromUrl(second.avatarUrl);

      assert.equal(ports.profile?.avatarObjectPath, secondObjectPath);
      assert.equal(ports.profile?.avatarPreviousObjectPath, firstObjectPath);
      assert.equal(ports.deletedPaths.includes(poisoned), false);
    }
  });

  it("a transaction failure leaves the promoted object in place and deletes nothing", async () => {
    const ports = fakePorts();
    // Default fixture state (profile exists, no cooldown, not suspended)
    // means the pre-check above passes cleanly — this failure models a
    // genuine contention/abort thrown by runProfileTransaction itself
    // (e.g. a Firestore transaction retry-exhaustion), a reason the
    // advisory pre-check has no way to see coming, so the copy must
    // already have happened by the time this throws.
    ports.transactionShouldFail = true;
    await rejects(() => setProfileAvatar({ auth: { uid }, data: request() }, ports), "internal");
    assert.equal(ports.copyCreateOnlyCallCount, 1, "the pre-check cannot catch a genuine transaction-layer failure");
    assert.equal(ports.avatars.size, 1, "the copy already happened before the failing transaction");
    assert.equal(ports.deletedPaths.length, 0);
    assert.equal(ports.staging.has(stagingPath), true, "staging must survive an aborted transaction");
  });

  it("retry after a precondition failure on the copy is idempotent", async () => {
    const ports = fakePorts();
    const fixedId = "b".repeat(32);
    const destinationPath = newAvatarObjectPath(fixedId);
    ports.fixedId = fixedId;
    // Simulate the destination already having been created by a previous,
    // not-fully-observed attempt: copyCreateOnly's create-only contract
    // means the retry must silently treat this as already-promoted rather
    // than throwing.
    ports.avatars.set(destinationPath, stored({ path: destinationPath }));

    const result = await setProfileAvatar({ auth: { uid }, data: request() }, ports);

    assert.equal(pathFromUrl(result.avatarUrl), destinationPath);
    assert.equal(ports.profile?.avatarObjectPath, destinationPath);
    assert.equal(ports.avatars.size, 1, "the pre-existing destination must not be duplicated");
    assert.equal(ports.deletedPaths.includes(stagingPath), true, "staging must still be cleaned up after an idempotent copy");
  });

  it("clearProfileAvatar deletes all four fields and both validated object paths", async () => {
    const ports = fakePorts();
    const first = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    const firstObjectPath = pathFromUrl(first.avatarUrl);
    ports.staging.set(stagingPath, stored());
    ports.nowMs += AVATAR_REPLACE_COOLDOWN_MS;
    const second = await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    const secondObjectPath = pathFromUrl(second.avatarUrl);

    const result = await clearProfileAvatar({ auth: { uid }, data: undefined }, ports);
    assert.equal(result.cleared, true);
    assert.deepEqual(ports.profile, { exists: true, avatarObjectPath: undefined, avatarPreviousObjectPath: undefined, avatarUpdatedAtMs: undefined });
    assert.equal(ports.deletedPaths.includes(firstObjectPath), true);
    assert.equal(ports.deletedPaths.includes(secondObjectPath), true);
  });

  it("clearProfileAvatar skips a delete for a poisoned stored object path but still clears the fields", async () => {
    const ports = fakePorts();
    await setProfileAvatar({ auth: { uid }, data: request() }, ports);
    assert.ok(ports.profile);
    // Simulate a poisoned/foreign value having ended up in avatarObjectPath
    // (defence-in-depth only: this field is backend-owned).
    ports.profile = { ...ports.profile, avatarObjectPath: "project-documents/x.pdf" };
    ports.deletedPaths.length = 0;

    const result = await clearProfileAvatar({ auth: { uid }, data: undefined }, ports);

    assert.equal(result.cleared, true);
    assert.deepEqual(ports.profile, { exists: true, avatarObjectPath: undefined, avatarPreviousObjectPath: undefined, avatarUpdatedAtMs: undefined });
    assert.equal(ports.deletedPaths.length, 0, "a poisoned stored path must never be handed to a delete call");
  });

  it("clearProfileAvatar rejects an unsupported payload", async () => {
    const ports = fakePorts();
    await rejects(() => clearProfileAvatar({ auth: { uid }, data: { extra: true } }, ports), "invalid-argument");
  });
});

type StoredFixture = ProfileAvatarStoredObject;

class FakePorts implements ProfileAvatarPorts {
  readonly staging = new Map<string, StoredFixture>([[stagingPath, stored()]]);
  readonly avatars = new Map<string, StoredFixture>();
  readonly deletedPaths: string[] = [];
  profile: ProfileAvatarProfileSnapshot | undefined = {
    exists: true,
    avatarObjectPath: undefined,
    avatarPreviousObjectPath: undefined,
    avatarUpdatedAtMs: undefined,
  };
  suspended = false;
  transactionShouldFail = false;
  nowMs = 1_000_000;
  fixedId: string | undefined;
  copyCreateOnlyCallCount = 0;
  private idCounter = 0;

  async readObject(path: string): Promise<StoredFixture | undefined> {
    return this.staging.get(path) ?? this.avatars.get(path);
  }

  async copyCreateOnly(sourcePath: string, destinationPath: string, options: { readonly token: string; readonly cacheControl: string }): Promise<void> {
    this.copyCreateOnlyCallCount += 1;
    if (this.avatars.has(destinationPath)) return;
    const source = this.staging.get(sourcePath);
    this.avatars.set(destinationPath, {
      path: destinationPath,
      contentType: "image/png",
      metadata: { firebaseStorageDownloadTokens: options.token },
      bytes: source?.bytes ?? png(256, 256),
    });
  }

  async deleteObject(path: string): Promise<void> {
    this.deletedPaths.push(path);
    this.staging.delete(path);
    this.avatars.delete(path);
  }

  newAvatarId(): string {
    if (this.fixedId !== undefined) return this.fixedId;
    this.idCounter += 1;
    return this.idCounter.toString(16).padStart(32, "0");
  }

  newDownloadToken(): string {
    return "3fa85f64-5717-4562-b3fc-2c963f66afa6";
  }

  bucketName(): string {
    return "demo-runiac-feed.appspot.com";
  }

  emulatorHost(): string | undefined {
    return undefined;
  }

  now(): number {
    return this.nowMs;
  }

  async readAccountData(_uid: string): Promise<Readonly<Record<string, unknown>> | undefined> {
    return this.suspended ? { accountStatus: "suspended" } : {};
  }

  async readProfileSnapshot(_uid: string): Promise<ProfileAvatarProfileSnapshot> {
    return this.snapshotProfile();
  }

  private snapshotProfile(): ProfileAvatarProfileSnapshot {
    return this.profile ?? { exists: false, avatarObjectPath: undefined, avatarPreviousObjectPath: undefined, avatarUpdatedAtMs: undefined };
  }

  async runProfileTransaction<T>(_uid: string, body: (tx: ProfileAvatarTransactionPort) => Promise<T>): Promise<T> {
    if (this.transactionShouldFail) throw coded("internal");
    const tx: ProfileAvatarTransactionPort = {
      assertCallerNotSuspended: async () => {
        if (this.suspended) throw coded("permission-denied");
      },
      readProfile: async () => this.snapshotProfile(),
      writeSetAvatar: (fields) => {
        this.profile = {
          exists: true,
          avatarObjectPath: fields.avatarObjectPath,
          avatarPreviousObjectPath: fields.avatarPreviousObjectPath,
          avatarUpdatedAtMs: this.nowMs,
        };
      },
      writeClearAvatar: () => {
        this.profile = { exists: true, avatarObjectPath: undefined, avatarPreviousObjectPath: undefined, avatarUpdatedAtMs: undefined };
      },
    };
    return body(tx);
  }
}

function fakePorts(): FakePorts {
  return new FakePorts();
}

function request(): { readonly stagingPath: string } {
  return { stagingPath };
}

function stored(overrides: Partial<StoredFixture> = {}): StoredFixture {
  return {
    path: overrides.path ?? stagingPath,
    contentType: overrides.contentType ?? "image/png",
    metadata: overrides.metadata ?? { ownerUid: uid },
    bytes: overrides.bytes ?? png(256, 256),
  };
}

function pathFromUrl(url: string): string {
  const match = /\/o\/([^?]+)\?/.exec(url);
  assert.ok(match, `expected an object-store URL, got: ${url}`);
  const encoded = match?.[1];
  assert.ok(encoded !== undefined);
  const decoded = decodeURIComponent(encoded);
  assert.equal(isAvatarObjectPath(decoded), true, `decoded path is not a valid avatar object path: ${decoded}`);
  return decoded;
}

function coded(code: string): Error & { readonly code: string } {
  return Object.assign(new Error(code), { code });
}

async function rejects(action: () => Promise<unknown>, code: string, detailsReason?: string): Promise<void> {
  await assert.rejects(action, (error: unknown) => {
    if (typeof error !== "object" || error === null || !("code" in error) || (error as { code: unknown }).code !== code) {
      return false;
    }
    if (detailsReason === undefined) return true;
    const details = (error as { details?: unknown }).details;
    return (
      typeof details === "object" &&
      details !== null &&
      (details as Record<string, unknown>)["reason"] === detailsReason
    );
  });
}

function png(width: number, height: number): Uint8Array {
  return Uint8Array.from([
    137, 80, 78, 71, 13, 10, 26, 10,
    ...chunk("IHDR", [...u32(width), ...u32(height), 8, 6, 0, 0, 0]),
    ...chunk("IDAT", [0]),
    ...chunk("IEND", []),
  ]);
}
function u32(value: number): number[] {
  return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255];
}
function chunk(type: string, data: readonly number[]): number[] {
  const typeBytes = [...type].map((character) => character.charCodeAt(0));
  return [...u32(data.length), ...typeBytes, ...data, ...u32(crc32([...typeBytes, ...data]))];
}
function crc32(bytes: readonly number[]): number {
  let crc = 0xffff_ffff;
  for (const value of bytes) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1;
  }
  return (crc ^ 0xffff_ffff) >>> 0;
}
