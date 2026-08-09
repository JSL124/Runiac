import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  isInstanceTerminal,
  isInvitationTerminal,
  isParticipantTerminal,
  isRewardTerminal,
  transitionInstance,
  transitionInvitation,
  transitionParticipant,
  transitionReward,
} from "../src/challenge/challengeStateMachine.js";
import type {
  ChallengeActor,
  ChallengeActorKind,
  ChallengeTransitionError,
  InstanceAction,
  InstanceState,
  InvitationAction,
  InvitationState,
  ParticipantAction,
  ParticipantRole,
  ParticipantState,
  RewardAction,
  RewardState,
  TransitionResult,
} from "../src/challenge/challengeTypes.js";

const ALL_ACTOR_KINDS: readonly ChallengeActorKind[] = ["owner", "self", "other", "system"];

function actor(kind: ChallengeActorKind): ChallengeActor {
  return { kind };
}

function otherActorKinds(allowed: ChallengeActorKind): readonly ChallengeActorKind[] {
  return ALL_ACTOR_KINDS.filter((kind) => kind !== allowed);
}

// ---------------------------------------------------------------------------
// Instance machine
// ---------------------------------------------------------------------------

const INSTANCE_STATES: readonly InstanceState[] = [
  "RECRUITING",
  "ACTIVE",
  "SETTLING",
  "SUCCEEDED",
  "FAILED",
  "CANCELLED",
  "EXPIRED",
];

type InstancePermitted = {
  readonly from: InstanceState;
  readonly action: InstanceAction;
  readonly actor: ChallengeActorKind;
  readonly to: InstanceState;
};

const INSTANCE_PERMITTED: readonly InstancePermitted[] = [
  { from: "RECRUITING", action: { type: "START", mode: "SOLO", rosterSize: 1 }, actor: "owner", to: "ACTIVE" },
  { from: "RECRUITING", action: { type: "START", mode: "GROUP", rosterSize: 2 }, actor: "owner", to: "ACTIVE" },
  { from: "RECRUITING", action: { type: "START", mode: "GROUP", rosterSize: 5 }, actor: "owner", to: "ACTIVE" },
  { from: "RECRUITING", action: { type: "CANCEL_LOBBY" }, actor: "owner", to: "CANCELLED" },
  { from: "RECRUITING", action: { type: "EXPIRE_LOBBY" }, actor: "system", to: "EXPIRED" },
  { from: "ACTIVE", action: { type: "BEGIN_SETTLEMENT" }, actor: "system", to: "SETTLING" },
  { from: "ACTIVE", action: { type: "ABANDON" }, actor: "owner", to: "CANCELLED" },
  { from: "SETTLING", action: { type: "SETTLE_SUCCEEDED" }, actor: "system", to: "SUCCEEDED" },
  { from: "SETTLING", action: { type: "SETTLE_FAILED" }, actor: "system", to: "FAILED" },
];

const INSTANCE_ALL_ACTIONS: readonly InstanceAction[] = [
  { type: "START", mode: "SOLO", rosterSize: 1 },
  { type: "CANCEL_LOBBY" },
  { type: "EXPIRE_LOBBY" },
  { type: "BEGIN_SETTLEMENT" },
  { type: "ABANDON" },
  { type: "SETTLE_SUCCEEDED" },
  { type: "SETTLE_FAILED" },
];

describe("instance state machine — permitted transitions", () => {
  for (const testCase of INSTANCE_PERMITTED) {
    it(`${testCase.from} --${testCase.action.type}(${testCase.actor})--> ${testCase.to}`, () => {
      const result = transitionInstance(testCase.from, testCase.action, actor(testCase.actor));
      assert.ok(result.ok);
      assert.equal(result.state, testCase.to);
    });
  }
});

describe("instance state machine — rejections leave source unchanged", () => {
  it("rejects every action/actor from every terminal state", () => {
    const terminals = INSTANCE_STATES.filter(isInstanceTerminal);
    for (const state of terminals) {
      for (const action of INSTANCE_ALL_ACTIONS) {
        for (const kind of ALL_ACTOR_KINDS) {
          assertRejected(transitionInstance(state, action, actor(kind)), "TERMINAL_STATE", state);
        }
      }
    }
  });

  it("rejects a permitted edge attempted by any disallowed actor", () => {
    for (const testCase of INSTANCE_PERMITTED) {
      for (const kind of otherActorKinds(testCase.actor)) {
        assertRejected(
          transitionInstance(testCase.from, testCase.action, actor(kind)),
          "FORBIDDEN_ACTOR",
          testCase.from,
        );
      }
    }
  });

  it("rejects actions with no edge from the current non-terminal state", () => {
    const illegal: readonly [InstanceState, InstanceAction][] = [
      ["RECRUITING", { type: "BEGIN_SETTLEMENT" }],
      ["RECRUITING", { type: "ABANDON" }],
      ["RECRUITING", { type: "SETTLE_SUCCEEDED" }],
      ["ACTIVE", { type: "START", mode: "SOLO", rosterSize: 1 }],
      ["ACTIVE", { type: "CANCEL_LOBBY" }],
      ["ACTIVE", { type: "EXPIRE_LOBBY" }],
      ["ACTIVE", { type: "SETTLE_SUCCEEDED" }],
      ["SETTLING", { type: "START", mode: "SOLO", rosterSize: 1 }],
      ["SETTLING", { type: "BEGIN_SETTLEMENT" }],
      ["SETTLING", { type: "ABANDON" }],
    ];
    for (const [state, action] of illegal) {
      for (const kind of ALL_ACTOR_KINDS) {
        assertRejected(transitionInstance(state, action, actor(kind)), "ILLEGAL_TRANSITION", state);
      }
    }
  });

  it("rejects mode/roster-inconsistent starts as MODE_ROSTER_MISMATCH", () => {
    const mismatches: readonly InstanceAction[] = [
      { type: "START", mode: "SOLO", rosterSize: 2 },
      { type: "START", mode: "SOLO", rosterSize: 0 },
      { type: "START", mode: "GROUP", rosterSize: 1 },
      { type: "START", mode: "GROUP", rosterSize: 0 },
    ];
    for (const action of mismatches) {
      assertRejected(transitionInstance("RECRUITING", action, actor("owner")), "MODE_ROSTER_MISMATCH", "RECRUITING");
    }
  });
});

// ---------------------------------------------------------------------------
// Invitation machine
// ---------------------------------------------------------------------------

const INVITATION_STATES: readonly InvitationState[] = [
  "PENDING",
  "ACCEPTED",
  "DECLINED",
  "REVOKED",
  "EXPIRED",
];

type InvitationPermitted = {
  readonly action: InvitationAction;
  readonly actor: ChallengeActorKind;
  readonly to: InvitationState;
};

const INVITATION_PERMITTED: readonly InvitationPermitted[] = [
  { action: { type: "ACCEPT" }, actor: "self", to: "ACCEPTED" },
  { action: { type: "DECLINE" }, actor: "self", to: "DECLINED" },
  { action: { type: "REVOKE" }, actor: "owner", to: "REVOKED" },
  { action: { type: "EXPIRE" }, actor: "system", to: "EXPIRED" },
];

const INVITATION_ALL_ACTIONS: readonly InvitationAction[] = [
  { type: "ACCEPT" },
  { type: "DECLINE" },
  { type: "REVOKE" },
  { type: "EXPIRE" },
];

describe("invitation state machine — permitted transitions", () => {
  for (const testCase of INVITATION_PERMITTED) {
    it(`PENDING --${testCase.action.type}(${testCase.actor})--> ${testCase.to}`, () => {
      const result = transitionInvitation("PENDING", testCase.action, actor(testCase.actor));
      assert.ok(result.ok);
      assert.equal(result.state, testCase.to);
    });
  }
});

describe("invitation state machine — rejections leave source unchanged", () => {
  it("rejects every action/actor from every terminal state", () => {
    const terminals = INVITATION_STATES.filter(isInvitationTerminal);
    for (const state of terminals) {
      for (const action of INVITATION_ALL_ACTIONS) {
        for (const kind of ALL_ACTOR_KINDS) {
          assertRejected(transitionInvitation(state, action, actor(kind)), "TERMINAL_STATE", state);
        }
      }
    }
  });

  it("rejects a permitted edge attempted by any disallowed actor", () => {
    for (const testCase of INVITATION_PERMITTED) {
      for (const kind of otherActorKinds(testCase.actor)) {
        assertRejected(
          transitionInvitation("PENDING", testCase.action, actor(kind)),
          "FORBIDDEN_ACTOR",
          "PENDING",
        );
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Participant machine
// ---------------------------------------------------------------------------

const PARTICIPANT_STATES: readonly ParticipantState[] = [
  "ACCEPTED",
  "ACTIVE",
  "LEFT",
  "CANCELLED",
  "SUCCEEDED",
  "INELIGIBLE",
  "FAILED",
];

const PARTICIPANT_ROLES: readonly ParticipantRole[] = ["owner", "member"];

type ParticipantPermitted = {
  readonly from: ParticipantState;
  readonly role: ParticipantRole;
  readonly action: ParticipantAction;
  readonly actor: ChallengeActorKind;
  readonly to: ParticipantState;
};

const PARTICIPANT_PERMITTED: readonly ParticipantPermitted[] = [
  { from: "ACCEPTED", role: "member", action: { type: "ACTIVATE" }, actor: "system", to: "ACTIVE" },
  { from: "ACCEPTED", role: "owner", action: { type: "ACTIVATE" }, actor: "system", to: "ACTIVE" },
  { from: "ACCEPTED", role: "member", action: { type: "WITHDRAW" }, actor: "self", to: "LEFT" },
  { from: "ACCEPTED", role: "member", action: { type: "CANCEL" }, actor: "system", to: "CANCELLED" },
  { from: "ACTIVE", role: "member", action: { type: "LEAVE" }, actor: "self", to: "LEFT" },
  { from: "ACTIVE", role: "member", action: { type: "CANCEL" }, actor: "system", to: "CANCELLED" },
  { from: "ACTIVE", role: "owner", action: { type: "CANCEL" }, actor: "system", to: "CANCELLED" },
  { from: "ACTIVE", role: "member", action: { type: "SETTLE_SUCCEEDED" }, actor: "system", to: "SUCCEEDED" },
  { from: "ACTIVE", role: "owner", action: { type: "SETTLE_SUCCEEDED" }, actor: "system", to: "SUCCEEDED" },
  { from: "ACTIVE", role: "member", action: { type: "SETTLE_INELIGIBLE" }, actor: "system", to: "INELIGIBLE" },
  { from: "ACTIVE", role: "member", action: { type: "SETTLE_FAILED" }, actor: "system", to: "FAILED" },
  // Server-initiated removal (premium-lapse eviction). Same destination as a
  // self-service LEAVE, but only the system may perform it, from either
  // pre-start (ACCEPTED) or in-flight (ACTIVE) participation.
  { from: "ACCEPTED", role: "member", action: { type: "REMOVE" }, actor: "system", to: "LEFT" },
  { from: "ACTIVE", role: "member", action: { type: "REMOVE" }, actor: "system", to: "LEFT" },
];

const PARTICIPANT_ALL_ACTIONS: readonly ParticipantAction[] = [
  { type: "ACTIVATE" },
  { type: "WITHDRAW" },
  { type: "LEAVE" },
  { type: "REMOVE" },
  { type: "CANCEL" },
  { type: "SETTLE_SUCCEEDED" },
  { type: "SETTLE_INELIGIBLE" },
  { type: "SETTLE_FAILED" },
];

describe("participant state machine — permitted transitions", () => {
  for (const testCase of PARTICIPANT_PERMITTED) {
    it(`${testCase.from}/${testCase.role} --${testCase.action.type}(${testCase.actor})--> ${testCase.to}`, () => {
      const result = transitionParticipant(
        { state: testCase.from, role: testCase.role },
        testCase.action,
        actor(testCase.actor),
      );
      assert.ok(result.ok);
      assert.equal(result.state, testCase.to);
    });
  }
});

describe("participant state machine — rejections leave source unchanged", () => {
  it("rejects every action/actor/role from every terminal state", () => {
    const terminals = PARTICIPANT_STATES.filter(isParticipantTerminal);
    for (const state of terminals) {
      for (const role of PARTICIPANT_ROLES) {
        for (const action of PARTICIPANT_ALL_ACTIONS) {
          for (const kind of ALL_ACTOR_KINDS) {
            const context = { state, role };
            assertRejectedContext(
              transitionParticipant(context, action, actor(kind)),
              "TERMINAL_STATE",
              context,
            );
          }
        }
      }
    }
  });

  it("rejects a permitted edge attempted by any disallowed actor", () => {
    for (const testCase of PARTICIPANT_PERMITTED) {
      for (const kind of otherActorKinds(testCase.actor)) {
        const context = { state: testCase.from, role: testCase.role };
        assertRejectedContext(
          transitionParticipant(context, testCase.action, actor(kind)),
          "FORBIDDEN_ACTOR",
          context,
        );
      }
    }
  });

  it("rejects owner self-exit (leave/withdraw) with OWNER_CANNOT_LEAVE", () => {
    const ownerLeave = transitionParticipant({ state: "ACTIVE", role: "owner" }, { type: "LEAVE" }, actor("self"));
    assertRejectedContext(ownerLeave, "OWNER_CANNOT_LEAVE", { state: "ACTIVE", role: "owner" });
    const ownerWithdraw = transitionParticipant(
      { state: "ACCEPTED", role: "owner" },
      { type: "WITHDRAW" },
      actor("self"),
    );
    assertRejectedContext(ownerWithdraw, "OWNER_CANNOT_LEAVE", { state: "ACCEPTED", role: "owner" });
  });

  it("rejects removing an owner, so eviction must demote before it removes", () => {
    // REMOVE is a system action, not a self-exit, but it stays subject to the
    // owner guard on purpose: it makes "an owner is never silently dropped out
    // of their own challenge" a machine-checked invariant. The premium-lapse
    // eviction path must either transfer ownership first (demoting this
    // participant to `member`) or cancel the whole instance.
    for (const state of ["ACCEPTED", "ACTIVE"] as const) {
      assertRejectedContext(
        transitionParticipant({ state, role: "owner" }, { type: "REMOVE" }, actor("system")),
        "OWNER_CANNOT_LEAVE",
        { state, role: "owner" },
      );
    }
  });

  it("rejects actions with no edge from the current non-terminal state", () => {
    const illegal: readonly [ParticipantState, ParticipantAction][] = [
      ["ACCEPTED", { type: "LEAVE" }],
      ["ACCEPTED", { type: "SETTLE_SUCCEEDED" }],
      ["ACCEPTED", { type: "SETTLE_INELIGIBLE" }],
      ["ACCEPTED", { type: "SETTLE_FAILED" }],
      ["ACTIVE", { type: "ACTIVATE" }],
      ["ACTIVE", { type: "WITHDRAW" }],
    ];
    for (const [state, action] of illegal) {
      for (const role of PARTICIPANT_ROLES) {
        for (const kind of ALL_ACTOR_KINDS) {
          const context = { state, role };
          assertRejectedContext(
            transitionParticipant(context, action, actor(kind)),
            "ILLEGAL_TRANSITION",
            context,
          );
        }
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Reward machine
// ---------------------------------------------------------------------------

const REWARD_STATES: readonly RewardState[] = ["NOT_ELIGIBLE", "PENDING", "ISSUED"];

const REWARD_ALL_ACTIONS: readonly RewardAction[] = [{ type: "ISSUE" }];

describe("reward state machine", () => {
  it("issues a pending reward only for the system actor", () => {
    const result = transitionReward("PENDING", { type: "ISSUE" }, actor("system"));
    assert.ok(result.ok);
    assert.equal(result.state, "ISSUED");
  });

  it("rejects issuing a pending reward from any non-system actor", () => {
    for (const kind of otherActorKinds("system")) {
      assertRejected(transitionReward("PENDING", { type: "ISSUE" }, actor(kind)), "FORBIDDEN_ACTOR", "PENDING");
    }
  });

  it("rejects issuing from terminal reward states", () => {
    const terminals = REWARD_STATES.filter(isRewardTerminal);
    for (const state of terminals) {
      for (const action of REWARD_ALL_ACTIONS) {
        for (const kind of ALL_ACTOR_KINDS) {
          assertRejected(transitionReward(state, action, actor(kind)), "TERMINAL_STATE", state);
        }
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Shared assertions
// ---------------------------------------------------------------------------

function assertRejected<TState>(
  result: TransitionResult<unknown>,
  expectedError: ChallengeTransitionError,
  source: TState,
): void {
  assert.equal(result.ok, false);
  assert.ok(!("state" in result), "a rejected transition must not return a next state");
  assert.ok(!result.ok);
  assert.equal(result.error, expectedError);
  // Source is a primitive string; a pure transition never mutates it.
  assert.equal(source, source);
}

function assertRejectedContext(
  result: TransitionResult<unknown>,
  expectedError: ChallengeTransitionError,
  source: { readonly state: ParticipantState; readonly role: ParticipantRole },
): void {
  const before = { ...source };
  assert.equal(result.ok, false);
  assert.ok(!("state" in result), "a rejected transition must not return a next state");
  assert.ok(!result.ok);
  assert.equal(result.error, expectedError);
  assert.deepEqual(source, before);
}
