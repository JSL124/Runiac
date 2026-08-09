import assert from "node:assert/strict";
import { it } from "node:test";
import { hasCallableFirebaseCliProperties } from "../src/leaderboard/leaderboardSeedFirestore.js";

it("rejects an incompatible Firebase CLI module shape", () => {
  // Given: a module-like value whose clientId export is not callable.
  const incompatibleModule = {
    clientId: "not-a-function",
    clientSecret: (): string => "secret",
  };

  // When: the Firebase CLI module boundary is checked before use.
  const isCompatible = hasCallableFirebaseCliProperties(incompatibleModule, ["clientId", "clientSecret"]);

  // Then: the value is rejected without loading Firebase CLI or contacting a service.
  assert.equal(isCompatible, false);
});
