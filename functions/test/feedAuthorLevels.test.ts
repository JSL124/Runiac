import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getFeedAuthorLevels, type FeedAuthorLevelsPorts } from "../src/feed/authorLevels/core.js";
import type { FeedRelationshipCheckInput } from "../src/feed/relationship.js";
import { buildAvatarDownloadUrl, type AvatarUrlContext } from "../src/profile/avatar/avatarPaths.js";

const viewer = "viewer-a";
const friend = "friend-a";
const stranger = "stranger-a";
const blocked = "blocked-a";
const post = "post-a";

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

describe("Feed author levels core", () => {
  it("resolves the caller's own uid, a reciprocal friend, and omits a denied/blocked uid", async () => {
    const ports = fakePorts();
    ports.profiles.set(viewer, { levelLabel: "Champion", levelProgressPercent: 42 });
    ports.profiles.set(friend, { levelLabel: "Rookie", levelProgressPercent: 10 });
    ports.relationships.set(stranger, { viewerHasAuthorFriend: false, authorHasViewerFriend: false, viewerBlockedAuthor: false, authorBlockedViewer: false });
    ports.relationships.set(blocked, { viewerHasAuthorFriend: true, authorHasViewerFriend: true, viewerBlockedAuthor: true, authorBlockedViewer: false });
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [viewer, friend, stranger, blocked] } }, ports);
    assert.deepEqual(result.levels[viewer], { levelLabel: "Champion", levelProgressPercent: 42, displayName: "", avatarInitials: "", avatarUrl: "" });
    assert.deepEqual(result.levels[friend], { levelLabel: "Rookie", levelProgressPercent: 10, displayName: "", avatarInitials: "", avatarUrl: "" });
    assert.equal(stranger in result.levels, false);
    assert.equal(blocked in result.levels, false);
  });

  it("dedupes repeated uids into a single entry and a single profile read", async () => {
    const ports = fakePorts();
    ports.profiles.set(friend, { levelLabel: "Rookie", levelProgressPercent: 10 });
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend, friend, friend] } }, ports);
    assert.equal(Object.keys(result.levels).length, 1);
    assert.deepEqual(result.levels[friend], { levelLabel: "Rookie", levelProgressPercent: 10, displayName: "", avatarInitials: "", avatarUrl: "" });
    assert.equal(ports.readProfilesCalls.length, 1);
    assert.equal(ports.readProfilesCalls[0]?.length, 1);
  });

  it("throws invalid-argument when more than 50 distinct uids are requested", async () => {
    const ports = fakePorts();
    const uids = Array.from({ length: 51 }, (_, index) => `uid-${index}`);
    await rejects(() => getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids } }, ports), "invalid-argument");
  });

  it("returns an empty levels map with no profile read for an empty uid array", async () => {
    const ports = fakePorts();
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [] } }, ports);
    assert.deepEqual(result.levels, {});
    assert.equal(ports.readProfilesCalls.length, 0);
  });

  it("resolves a missing profile document to an empty label and zero percent", async () => {
    const ports = fakePorts();
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.deepEqual(result.levels[viewer], { levelLabel: "", levelProgressPercent: 0, displayName: "", avatarInitials: "", avatarUrl: "" });
  });

  it("falls back to Lv.{level} when levelLabel is absent", async () => {
    const ports = fakePorts();
    ports.profiles.set(viewer, { level: 7 });
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.deepEqual(result.levels[viewer], { levelLabel: "Lv.7", levelProgressPercent: 0, displayName: "", avatarInitials: "", avatarUrl: "" });
  });

  // A Feed post freezes the author's name at publish time, so the overlay this
  // result feeds is the only thing that can show a renamed runner's current
  // name on the posts they already published.
  it("resolves the author's current nickname over their displayName", async () => {
    const ports = fakePorts();
    ports.profiles.set(friend, { levelLabel: "Rookie", levelProgressPercent: 10, displayName: "Old Name", nickname: "New Name", avatarInitials: "NN" });
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports);
    assert.deepEqual(result.levels[friend], { levelLabel: "Rookie", levelProgressPercent: 10, displayName: "New Name", avatarInitials: "NN", avatarUrl: "" });
  });

  it("trims a stored identity and leaves a missing one empty so the client keeps its stored value", async () => {
    const ports = fakePorts();
    ports.profiles.set(friend, { displayName: "  Spaced Runner  ", avatarInitials: " SR " });
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports);
    assert.equal(result.levels[friend]?.displayName, "Spaced Runner");
    assert.equal(result.levels[friend]?.avatarInitials, "SR");
    ports.profiles.set(blocked, {});
    const missing = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [blocked] } }, ports);
    assert.equal(missing.levels[blocked]?.displayName, "");
  });

  it("clamps an out-of-range levelProgressPercent into 0..100", async () => {
    const ports = fakePorts();
    ports.profiles.set(viewer, { levelLabel: "Champion", levelProgressPercent: 250 });
    const overResult = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.equal(overResult.levels[viewer]?.levelProgressPercent, 100);
    ports.profiles.set(viewer, { levelLabel: "Champion", levelProgressPercent: -5 });
    const underResult = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.equal(underResult.levels[viewer]?.levelProgressPercent, 0);
  });

  it("treats a non-finite levelProgressPercent as zero", async () => {
    const ports = fakePorts();
    ports.profiles.set(viewer, { levelLabel: "Champion", levelProgressPercent: Number.NaN });
    const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [viewer] } }, ports);
    assert.equal(result.levels[viewer]?.levelProgressPercent, 0);
  });

  it("rejects malformed payloads with invalid-argument", async () => {
    const ports = fakePorts();
    for (const data of [
      {}, { uids: "not-an-array" }, { uids: [123] }, { uids: [""] }, { uids: [viewer], extra: true }, { uids: [viewer, ""] },
    ]) {
      await rejects(() => getFeedAuthorLevels({ auth: { uid: viewer }, data }, ports), "invalid-argument");
    }
  });

  it("rejects an unauthenticated request with unauthenticated", async () => {
    const ports = fakePorts();
    await rejects(() => getFeedAuthorLevels({ data: { uids: [viewer] } }, ports), "unauthenticated");
  });

  // firestore.rules authorizes a comment through its POST, not its commenter:
  // two runners who share a friend but not each other still read each other's
  // comments on that friend's post. Without the post-scoped grant the overlay
  // resolves nothing for them and the rename defect survives right there.
  describe("post-scoped grants", () => {
    it("resolves a non-friend who commented on a post the viewer may read", async () => {
      const ports = fakePorts();
      ports.profiles.set(stranger, { displayName: "Old", nickname: "Renamed", avatarInitials: "RN" });
      ports.relationships.set(stranger, { viewerHasAuthorFriend: false, authorHasViewerFriend: false });
      ports.posts.set(post, { status: "published", authorUid: friend });
      ports.commentAuthors.set(post, [stranger]);
      const scoped = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [stranger] } }, ports);
      assert.equal(scoped.levels[stranger]?.displayName, "Renamed");
      // Same uid, no post in scope: still omitted, so the grant is the post's
      // doing and not a blanket widening.
      const unscoped = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [stranger] } }, ports);
      assert.equal(stranger in unscoped.levels, false);
    });

    it("omits a non-friend who did not comment on that post", async () => {
      const ports = fakePorts();
      ports.relationships.set(stranger, { viewerHasAuthorFriend: false, authorHasViewerFriend: false });
      ports.posts.set(post, { status: "published", authorUid: friend });
      ports.commentAuthors.set(post, ["someone-else"]);
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [stranger] } }, ports);
      assert.equal(stranger in result.levels, false);
    });

    it("never relaxes a block, in either direction", async () => {
      const ports = fakePorts();
      ports.posts.set(post, { status: "published", authorUid: friend });
      ports.commentAuthors.set(post, [blocked, "blocked-by-b"]);
      ports.relationships.set(blocked, { viewerHasAuthorFriend: false, authorHasViewerFriend: false, viewerBlockedAuthor: true });
      ports.relationships.set("blocked-by-b", { viewerHasAuthorFriend: false, authorHasViewerFriend: false, authorBlockedViewer: true });
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [blocked, "blocked-by-b"] } }, ports);
      assert.deepEqual(result.levels, {});
    });

    it("omits everyone when the viewer cannot read the post itself", async () => {
      const ports = fakePorts();
      ports.relationships.set(stranger, { viewerHasAuthorFriend: false, authorHasViewerFriend: false });
      ports.relationships.set("post-owner", { viewerHasAuthorFriend: false, authorHasViewerFriend: false });
      ports.posts.set(post, { status: "published", authorUid: "post-owner" });
      ports.commentAuthors.set(post, [stranger]);
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [stranger] } }, ports);
      assert.deepEqual(result.levels, {});
    });

    it("omits everyone for an unpublished or missing post", async () => {
      const ports = fakePorts();
      ports.relationships.set(stranger, { viewerHasAuthorFriend: false, authorHasViewerFriend: false });
      ports.commentAuthors.set(post, [stranger]);
      ports.posts.set(post, { status: "draft", authorUid: friend });
      const draft = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [stranger] } }, ports);
      assert.deepEqual(draft.levels, {});
      ports.posts.delete(post);
      const missing = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [stranger] } }, ports);
      assert.deepEqual(missing.levels, {});
    });

    it("costs no post read when every requested uid is already a friend", async () => {
      const ports = fakePorts();
      ports.profiles.set(friend, { levelLabel: "Rookie" });
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId: post, uids: [friend] } }, ports);
      assert.equal(result.levels[friend]?.levelLabel, "Rookie");
      assert.equal(ports.readPostCalls.length, 0);
    });

    it("rejects a malformed postId with invalid-argument", async () => {
      const ports = fakePorts();
      for (const postId of ["", "a/b", "../escape", "with\u0000null", 42]) {
        await rejects(() => getFeedAuthorLevels({ auth: { uid: viewer }, data: { postId, uids: [stranger] } }, ports), "invalid-argument");
      }
    });
  });

  describe("avatarUrl", () => {
    it("surfaces a valid stored avatarUrl", async () => {
      const ports = fakePorts();
      ports.profiles.set(friend, { levelLabel: "Rookie", avatarUrl: VALID_AVATAR_URL });
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, VALID_AVATAR_URL);
    });

    it("resolves a foreign-bucket avatarUrl to empty rather than relaying it", async () => {
      const ports = fakePorts();
      ports.profiles.set(friend, { levelLabel: "Rookie", avatarUrl: FOREIGN_AVATAR_URL });
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, "");
    });

    it("resolves a malformed avatarUrl string to empty", async () => {
      const ports = fakePorts();
      ports.profiles.set(friend, { levelLabel: "Rookie", avatarUrl: "not a url at all" });
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, "");
    });

    it("resolves a profile with no avatar fields to empty, never undefined", async () => {
      const ports = fakePorts();
      ports.profiles.set(friend, { levelLabel: "Rookie" });
      const result = await getFeedAuthorLevels({ auth: { uid: viewer }, data: { uids: [friend] } }, ports, AVATAR_CONTEXT);
      assert.equal(result.levels[friend]?.avatarUrl, "");
      assert.equal("avatarUrl" in (result.levels[friend] ?? {}), true);
    });
  });
});

type Profile = {
  readonly levelLabel?: string;
  readonly level?: number;
  readonly levelProgressPercent?: number;
  readonly displayName?: string;
  readonly nickname?: string;
  readonly avatarInitials?: string;
  readonly avatarUrl?: string;
};
class FakePorts implements FeedAuthorLevelsPorts {
  profiles = new Map<string, Profile>();
  relationships = new Map<string, Partial<FeedRelationshipCheckInput>>();
  posts = new Map<string, { readonly status: string; readonly authorUid: string }>();
  commentAuthors = new Map<string, readonly string[]>();
  readProfilesCalls: (readonly string[])[] = [];
  readPostCalls: string[] = [];
  async relationshipFor(viewerUid: string, authorUid: string): Promise<FeedRelationshipCheckInput> {
    const overrides = this.relationships.get(authorUid) ?? { viewerHasAuthorFriend: true, authorHasViewerFriend: true, viewerBlockedAuthor: false, authorBlockedViewer: false };
    return { viewerUid, authorUid, viewerHasAuthorFriend: true, authorHasViewerFriend: true, viewerBlockedAuthor: false, authorBlockedViewer: false, ...overrides };
  }
  async readProfiles(uids: readonly string[]): Promise<readonly (Readonly<Record<string, unknown>> | undefined)[]> {
    this.readProfilesCalls.push(uids);
    return uids.map((uid) => this.profiles.get(uid));
  }
  async readPost(postId: string) {
    this.readPostCalls.push(postId);
    return this.posts.get(postId);
  }
  async commentAuthorsAmong(postId: string, uids: readonly string[]): Promise<readonly string[]> {
    const authors = new Set(this.commentAuthors.get(postId) ?? []);
    return uids.filter((uid) => authors.has(uid));
  }
}
function fakePorts(): FakePorts { return new FakePorts(); }
async function rejects(action: () => Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(action, (error: unknown) => typeof error === "object" && error !== null && "code" in error && error["code"] === code);
}
