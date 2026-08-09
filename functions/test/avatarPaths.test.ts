import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  isAvatarObjectPath,
  newAvatarObjectPath,
  isOwnedAvatarStagingPath,
  buildAvatarDownloadUrl,
  resolveProfileAvatarUrl,
  avatarObjectPathFromUrl,
} from "../src/profile/avatar/avatarPaths.js";

const BUCKET = "runiac-fypp.appspot.com";
const TOKEN = "3fa85f64-5717-4562-b3fc-2c963f66afa6";
const VALID_ID = "0123456789abcdef0123456789abcdef";

describe("Avatar path contract", () => {
  it("mints a valid object path and round-trips it through the download URL and back", () => {
    const objectPath = newAvatarObjectPath(VALID_ID);
    assert.equal(objectPath, `avatars/${VALID_ID}.png`);
    assert.equal(isAvatarObjectPath(objectPath), true);

    const url = buildAvatarDownloadUrl({ bucket: BUCKET, objectPath, token: TOKEN });
    assert.equal(
      url,
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}?alt=media&token=${TOKEN}`,
    );

    const resolved = resolveProfileAvatarUrl({ avatarUrl: url }, { bucket: BUCKET });
    assert.equal(resolved, url);

    const decodedPath = avatarObjectPathFromUrl(url, { bucket: BUCKET });
    assert.equal(decodedPath, objectPath);
  });

  it("builds the emulator form of the download URL and round-trips it back too", () => {
    const objectPath = newAvatarObjectPath(VALID_ID);
    const emulatorHost = "127.0.0.1:9199";
    const url = buildAvatarDownloadUrl({ bucket: BUCKET, objectPath, token: TOKEN, emulatorHost });
    assert.equal(
      url,
      `http://${emulatorHost}/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}?alt=media&token=${TOKEN}`,
    );

    assert.equal(resolveProfileAvatarUrl({ avatarUrl: url }, { bucket: BUCKET, emulatorHost }), url);
    assert.equal(avatarObjectPathFromUrl(url, { bucket: BUCKET, emulatorHost }), objectPath);
  });

  it("newAvatarObjectPath throws unless the id is exactly 32 lowercase hex characters", () => {
    assert.throws(() => newAvatarObjectPath("not-hex-at-all"));
    assert.throws(() => newAvatarObjectPath(VALID_ID.slice(0, 31)));
    assert.throws(() => newAvatarObjectPath(VALID_ID.toUpperCase()));
    assert.throws(() => newAvatarObjectPath(`${VALID_ID}f`));
  });

  it("buildAvatarDownloadUrl throws on a foreign object path or a non-UUID token", () => {
    assert.throws(() =>
      buildAvatarDownloadUrl({ bucket: BUCKET, objectPath: "feed-thumbnails/uid/act/route-preview.png", token: TOKEN }),
    );
    assert.throws(() =>
      buildAvatarDownloadUrl({ bucket: BUCKET, objectPath: `avatars/${VALID_ID}.png`, token: "not-a-uuid" }),
    );
  });

  it("accepts only the exact avatars/{32-hex}.png shape and rejects every foreign or malformed path", () => {
    assert.equal(isAvatarObjectPath(`avatars/${VALID_ID}.png`), true);

    const rejected = [
      "project-documents/x.pdf",
      "feed-thumbnails/uid/act/route-preview.png",
      "share-cards/uid/rank-card.png",
      `/avatars/${VALID_ID}.png`,
      "avatars/../secret.png",
      `avatars/${VALID_ID.slice(0, 31)}.png`,
      `avatars/${VALID_ID.toUpperCase()}.png`,
      `avatars/${VALID_ID}.jpg`,
      `avatars/a/${VALID_ID}.png`,
      "",
      "avatars/.png",
    ];
    for (const value of rejected) {
      assert.equal(isAvatarObjectPath(value), false, `expected rejection for: ${JSON.stringify(value)}`);
    }
    // isAvatarObjectPath must be a type guard over unknown, not just string.
    assert.equal(isAvatarObjectPath(undefined), false);
    assert.equal(isAvatarObjectPath(42), false);
  });

  it("resolveProfileAvatarUrl returns '' for every structurally unsound URL", () => {
    const objectPath = newAvatarObjectPath(VALID_ID);
    const encoded = encodeURIComponent(objectPath);

    const cases = [
      // foreign host
      `https://evil.com/v0/b/${BUCKET}/o/${encoded}?alt=media&token=${TOKEN}`,
      // different bucket
      `https://firebasestorage.googleapis.com/v0/b/other-bucket/o/${encoded}?alt=media&token=${TOKEN}`,
      // missing alt=media
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?token=${TOKEN}`,
      // extra query param
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media&token=${TOKEN}&extra=1`,
      // fragment
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media&token=${TOKEN}#frag`,
      // non-UUID token
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media&token=not-a-uuid`,
      // http:// URL when emulatorHost is unset
      `http://127.0.0.1:9199/v0/b/${BUCKET}/o/${encoded}?alt=media&token=${TOKEN}`,
      // alt not exactly "media"
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=thumbnail&token=${TOKEN}`,
      // object path embedded in the URL is not a valid avatar path
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent("feed-thumbnails/uid/act/route-preview.png")}?alt=media&token=${TOKEN}`,
    ];

    for (const url of cases) {
      assert.equal(
        resolveProfileAvatarUrl({ avatarUrl: url }, { bucket: BUCKET }),
        "",
        `expected rejection for: ${url}`,
      );
    }
  });

  it("resolveProfileAvatarUrl rejects an http:// URL whose host differs from the supplied emulatorHost", () => {
    const objectPath = newAvatarObjectPath(VALID_ID);
    const url = buildAvatarDownloadUrl({
      bucket: BUCKET,
      objectPath,
      token: TOKEN,
      emulatorHost: "127.0.0.1:9199",
    });
    assert.equal(
      resolveProfileAvatarUrl({ avatarUrl: url }, { bucket: BUCKET, emulatorHost: "localhost:9199" }),
      "",
    );
  });

  it("resolveProfileAvatarUrl accepts an emulator URL only when emulatorHost matches", () => {
    const objectPath = newAvatarObjectPath(VALID_ID);
    const emulatorHost = "127.0.0.1:9199";
    const url = buildAvatarDownloadUrl({ bucket: BUCKET, objectPath, token: TOKEN, emulatorHost });
    assert.equal(resolveProfileAvatarUrl({ avatarUrl: url }, { bucket: BUCKET, emulatorHost }), url);
  });

  it("resolveProfileAvatarUrl never throws on garbage input", () => {
    for (const garbage of [undefined, null, 42, {}, "not a url"]) {
      assert.doesNotThrow(() => resolveProfileAvatarUrl(garbage, { bucket: BUCKET }));
      assert.equal(resolveProfileAvatarUrl(garbage, { bucket: BUCKET }), "");
    }
    // A document that has an avatarUrl field of the wrong type must also
    // resolve to "" rather than throw.
    for (const avatarUrl of [42, {}, [], null, undefined]) {
      assert.doesNotThrow(() => resolveProfileAvatarUrl({ avatarUrl }, { bucket: BUCKET }));
      assert.equal(resolveProfileAvatarUrl({ avatarUrl }, { bucket: BUCKET }), "");
    }
  });

  it("isOwnedAvatarStagingPath is defensive about the owner segment, traversal, and extra segments", () => {
    assert.equal(isOwnedAvatarStagingPath("avatar-staging/uid1/abc.png", "uid1"), true);
    assert.equal(isOwnedAvatarStagingPath("avatar-staging/uid2/abc.png", "uid1"), false);
    assert.equal(isOwnedAvatarStagingPath("avatar-staging/uid1/../abc.png", "uid1"), false);
    assert.equal(isOwnedAvatarStagingPath("avatar-staging/uid1/nested/abc.png", "uid1"), false);
    assert.equal(isOwnedAvatarStagingPath("avatar-staging/uid1/abc.jpg", "uid1"), false);
    assert.equal(isOwnedAvatarStagingPath("feed-thumbnail-staging/uid1/abc.png", "uid1"), false);
  });
});
