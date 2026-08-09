// Pure lobby-expiry decision seam.
//
// A RECRUITING lobby expires exactly 24h after its server `createdAt`. This
// module owns that arithmetic and the pure predicate that any callable (or the
// Todo-6 scheduled sweep) uses to decide whether a lobby must be lazily marked
// EXPIRED. No firebase imports, no Firestore access, no UI copy.

import type { InstanceState } from "./challengeTypes.js";

// Lobby time-to-live: exactly 24 hours in milliseconds.
export const LOBBY_TTL_MS = 24 * 60 * 60 * 1000;

// Compute the exact lobby expiry instant from the server createdAt instant.
export function lobbyExpiresAtMs(createdAtMs: number): number {
  return createdAtMs + LOBBY_TTL_MS;
}

export type LobbyExpiryInput = {
  readonly status: InstanceState;
  readonly lobbyExpiresAtMs: number;
  readonly nowMs: number;
};

// A lobby must be expired when it is still RECRUITING and the current server
// instant is at or past its expiry instant. The boundary is inclusive: a lobby
// is expired the moment `nowMs === lobbyExpiresAtMs`.
export function shouldExpireLobby(input: LobbyExpiryInput): boolean {
  if (input.status !== "RECRUITING") return false;
  return input.nowMs >= input.lobbyExpiresAtMs;
}
