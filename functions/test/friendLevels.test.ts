import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getFriendLevels, type FriendLevelsPorts } from "../src/friends/friendLevels/core.js";
import { buildAvatarDownloadUrl, type AvatarUrlContext } from "../src/profile/avatar/avatarPaths.js";

const viewer = "viewer-a";
const friend = "friend-a";
const requested = "requested-a";
const blocked = "blocked-a";
const stranger = "stranger-a";

const BUCKET = "runiac-fypp.appspot.com";
const AVATAR_CONTEXT: AvatarUrlContext = { bucket: BUCKET };
const TOKEN = "3fa85f64-5717-4562-b3fc-2c963f66afa6";
const VALID_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: BUCKET,
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: TOKEN,
});
const FOREIGN_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: "some-other-bucket.appspot.com",
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: TOKEN,
});

describe("Friend levels core", () => {
  it("resolves the caller's own uid always, without any edge lookup", async () => {
    const ports = fakePorts();
    ports.profiles.set(viewer, { levelLabel: "Champion", levelProgressPercent: 42 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.deepEqual(result.levels[viewer], { levelLabel: "Champion", levelProgressPercent: 42, avatarUrl: "" });
    assert.equal(ports.edgeCalls.length, 0);
  });

  it("permits a uid with a friends edge", async () => {
    const ports = fakePorts();
    ports.friendEdges.add(friend);
    ports.profiles.set(friend, { levelLabel: "Rookie", levelProgressPercent: 10 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports);
    assert.deepEqual(result.levels[friend], { levelLabel: "Rookie", levelProgressPercent: 10, avatarUrl: "" });
  });

  it("permits a uid with a friendRequests edge", async () => {
    const ports = fakePorts();
    ports.requestEdges.add(requested);
    ports.profiles.set(requested, { levelLabel: "Rookie", levelProgressPercent: 5 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [requested] } }, ports);
    assert.deepEqual(result.levels[requested], { levelLabel: "Rookie", levelProgressPercent: 5, avatarUrl: "" });
  });

  it("permits a uid with a blockedUsers edge", async () => {
    const ports = fakePorts();
    ports.blockEdges.add(blocked);
    ports.profiles.set(blocked, { levelLabel: "Champion", levelProgressPercent: 99 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [blocked] } }, ports);
    assert.deepEqual(result.levels[blocked], { levelLabel: "Champion", levelProgressPercent: 99, avatarUrl: "" });
  });

  it("omits a uid with no edge at all", async () => {
    const ports = fakePorts();
    ports.profiles.set(stranger, { levelLabel: "Champion", levelProgressPercent: 99 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [stranger] } }, ports);
    assert.equal(stranger in result.levels, false);
  });

  it("dedupes repeated uids into a single entry and a single profile read", async () => {
    const ports = fakePorts();
    ports.friendEdges.add(friend);
    ports.profiles.set(friend, { levelLabel: "Rookie", levelProgressPercent: 10 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend, friend, friend] } }, ports);
    assert.equal(Object.keys(result.levels).length, 1);
    assert.deepEqual(result.levels[friend], { levelLabel: "Rookie", levelProgressPercent: 10, avatarUrl: "" });
    assert.equal(ports.readProfilesCalls.length, 1);
    assert.equal(ports.readProfilesCalls[0]?.length, 1);
  });

  it("throws invalid-argument when more than 50 distinct uids are requested", async () => {
    const ports = fakePorts();
    const uids = Array.from({ length: 51 }, (_, index) => `uid-${index}`);
    await rejects(() => getFriendLevels({ auth: { uid: viewer }, data: { uids } }, ports), "invalid-argument");
  });

  it("returns an empty levels map with no profile read for an empty uid array", async () => {
    const ports = fakePorts();
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [] } }, ports);
    assert.deepEqual(result.levels, {});
    assert.equal(ports.readProfilesCalls.length, 0);
  });

  it("rejects malformed payloads with invalid-argument", async () => {
    const ports = fakePorts();
    for (const data of [
      {}, { uids: "not-an-array" }, { uids: [123] }, { uids: [""] }, { uids: [viewer], extra: true }, { uids: [viewer, ""] },
    ]) {
      await rejects(() => getFriendLevels({ auth: { uid: viewer }, data }, ports), "invalid-argument");
    }
  });

  it("rejects an unauthenticated request with unauthenticated", async () => {
    const ports = fakePorts();
    await rejects(() => getFriendLevels({ data: { uids: [viewer] } }, ports), "unauthenticated");
  });

  it("resolves a missing profile document to an empty label and zero percent", async () => {
    const ports = fakePorts();
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.deepEqual(result.levels[viewer], { levelLabel: "", levelProgressPercent: 0, avatarUrl: "" });
  });

  it("falls back to Lv.{level} when levelLabel is absent", async () => {
    const ports = fakePorts();
    ports.profiles.set(viewer, { level: 7 });
    const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.deepEqual(result.levels[viewer], { levelLabel: "Lv.7", levelProgressPercent: 0, avatarUrl: "" });
  });

  describe("avatarUrl", () => {
    it("surfaces a valid stored avatarUrl", async () => {
      const ports = fakePorts();
      ports.friendEdges.add(friend);
      ports.profiles.set(friend, { levelLabel: "Rookie", avatarUrl: VALID_AVATAR_URL });
      const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, VALID_AVATAR_URL);
    });

    it("resolves a foreign-bucket avatarUrl to empty rather than relaying it", async () => {
      const ports = fakePorts();
      ports.friendEdges.add(friend);
      ports.profiles.set(friend, { levelLabel: "Rookie", avatarUrl: FOREIGN_AVATAR_URL });
      const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, "");
    });

    it("resolves a malformed avatarUrl string to empty", async () => {
      const ports = fakePorts();
      ports.friendEdges.add(friend);
      ports.profiles.set(friend, { levelLabel: "Rookie", avatarUrl: "not a url at all" });
      const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, "");
    });

    it("resolves a profile with no avatar fields to empty, never undefined", async () => {
      const ports = fakePorts();
      ports.friendEdges.add(friend);
      ports.profiles.set(friend, { levelLabel: "Rookie" });
      const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, "");
      assert.equal("avatarUrl" in (result.levels[friend] ?? {}), true);
    });

    it("never carries a displayName field, even alongside a resolved avatar", async () => {
      const ports = fakePorts();
      ports.friendEdges.add(friend);
      ports.profiles.set(friend, { levelLabel: "Rookie", displayName: "Should Not Appear", avatarUrl: VALID_AVATAR_URL });
      const result = await getFriendLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal("displayName" in (result.levels[friend] ?? {}), false);
    });
  });
});

type Profile = {
  readonly levelLabel?: string;
  readonly level?: number;
  readonly levelProgressPercent?: number;
  readonly avatarUrl?: string;
  readonly displayName?: string;
};
class FakePorts implements FriendLevelsPorts {
  profiles = new Map<string, Profile>();
  friendEdges = new Set<string>();
  requestEdges = new Set<string>();
  blockEdges = new Set<string>();
  edgeCalls: (readonly [string, string])[] = [];
  readProfilesCalls: (readonly string[])[] = [];
  async hasSocialEdge(callerUid: string, uid: string): Promise<boolean> {
    this.edgeCalls.push([callerUid, uid]);
    return this.friendEdges.has(uid) || this.requestEdges.has(uid) || this.blockEdges.has(uid);
  }
  async readProfiles(uids: readonly string[]): Promise<readonly (Readonly<Record<string, unknown>> | undefined)[]> {
    this.readProfilesCalls.push(uids);
    return uids.map((uid) => this.profiles.get(uid));
  }
}
function fakePorts(): FakePorts { return new FakePorts(); }
async function rejects(action: () => Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(action, (error: unknown) => typeof error === "object" && error !== null && "code" in error && error["code"] === code);
}
