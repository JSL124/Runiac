import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  LOBBY_TTL_MS,
  lobbyExpiresAtMs,
  shouldExpireLobby,
} from "../src/challenge/challengeExpiry.js";
import type { InstanceState } from "../src/challenge/challengeTypes.js";

const CREATED_AT = 1_700_000_000_000;

describe("challenge lobby expiry (pure)", () => {
  it("expires exactly 24h after createdAt", () => {
    assert.equal(LOBBY_TTL_MS, 24 * 60 * 60 * 1000);
    assert.equal(lobbyExpiresAtMs(CREATED_AT), CREATED_AT + 86_400_000);
  });

  it("is not expired one millisecond before the deadline", () => {
    const expiresAt = lobbyExpiresAtMs(CREATED_AT);
    assert.equal(
      shouldExpireLobby({ status: "RECRUITING", lobbyExpiresAtMs: expiresAt, nowMs: expiresAt - 1 }),
      false,
    );
  });

  it("is expired at the exact deadline (inclusive boundary)", () => {
    const expiresAt = lobbyExpiresAtMs(CREATED_AT);
    assert.equal(
      shouldExpireLobby({ status: "RECRUITING", lobbyExpiresAtMs: expiresAt, nowMs: expiresAt }),
      true,
    );
  });

  it("is expired after the deadline", () => {
    const expiresAt = lobbyExpiresAtMs(CREATED_AT);
    assert.equal(
      shouldExpireLobby({ status: "RECRUITING", lobbyExpiresAtMs: expiresAt, nowMs: expiresAt + 1 }),
      true,
    );
  });

  it("never expires a non-RECRUITING instance", () => {
    const expiresAt = lobbyExpiresAtMs(CREATED_AT);
    const nonRecruiting: readonly InstanceState[] = [
      "ACTIVE",
      "SETTLING",
      "SUCCEEDED",
      "FAILED",
      "CANCELLED",
      "EXPIRED",
    ];
    for (const status of nonRecruiting) {
      assert.equal(
        shouldExpireLobby({ status, lobbyExpiresAtMs: expiresAt, nowMs: expiresAt + 1_000_000 }),
        false,
      );
    }
  });
});
