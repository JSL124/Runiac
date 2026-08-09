import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { assertFeedFixtureEnvironment, runFeedFixtureScenario } from "../src/feed/fixtures/emulatorFixtures.js";
import { reciprocalFriendships, syntheticFeedFixture } from "../src/feed/fixtures/fixtureDefinitions.js";

describe("Feed fixture emulator guard", () => {
  const valid = {
    GCLOUD_PROJECT: "demo-runiac-feed",
    FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
    FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5001",
    FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199",
  };

  it("fails closed before mutation for every invalid environment", async () => {
    const invalid = [
      { ...valid, GCLOUD_PROJECT: "runiac-fypp" },
      { ...valid, FIREBASE_AUTH_EMULATOR_HOST: "" },
      { ...valid, FIRESTORE_EMULATOR_HOST: "localhost:8080" },
      { ...valid, FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5002" },
      { ...valid, FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9198" },
    ];
    for (const environment of invalid) {
      assert.equal(assertFeedFixtureEnvironment(environment).ok, false);
      let mutations = 0;
      const result = await runFeedFixtureScenario({ environment, scenario: "baseline", mutate: async () => { mutations += 1; } });
      assert.equal(result.ok, false);
      assert.equal(mutations, 0);
    }
  });

  it("permits only known repeatable synthetic scenarios after the guard", async () => {
    for (const scenario of ["reset", "baseline", "unfriend", "block-viewer", "block-author", "delete-activity"] as const) {
      let mutations = 0;
      for (const repeat of [1, 2]) {
        const result = await runFeedFixtureScenario({ environment: valid, scenario, mutate: async (received) => { mutations += 1; assert.equal(received, scenario); } });
        assert.equal(result.ok, true);
        assert.equal(repeat, mutations);
      }
    }
    assert.equal(assertFeedFixtureEnvironment(valid).ok, true);
  });

  it("rejects an unknown fixture scenario before mutation", async () => {
    let mutations = 0;
    const result = await runFeedFixtureScenario({ environment: valid, scenario: "unknown", mutate: async () => { mutations += 1; } });
    assert.equal(result.ok, false);
    assert.equal(mutations, 0);
  });

  it("describes only synthetic identities and creates reciprocal friendship pairs", () => {
    assert.equal(syntheticFeedFixture.identities.length, 3);
    assert.equal(syntheticFeedFixture.identities.some((identity) => identity.role === "non_friend"), true);
    assert.deepEqual(reciprocalFriendships(syntheticFeedFixture.author.uid, syntheticFeedFixture.acceptedFriend.uid), [
      { ownerUid: syntheticFeedFixture.author.uid, friendUid: syntheticFeedFixture.acceptedFriend.uid },
      { ownerUid: syntheticFeedFixture.acceptedFriend.uid, friendUid: syntheticFeedFixture.author.uid },
    ]);
  });
});
