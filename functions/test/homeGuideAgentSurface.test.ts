import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HomeGuideContractError, parseHomeGuidePlanDisplayContext } from "../src/agent/homeGuideContracts.js";

describe("home guide callable payload boundary", () => {
  it("accepts a bounded display-only plan context", () => {
    const payload = parseHomeGuidePlanDisplayContext(validPayload());

    assert.equal(payload.planTitle, "Beginner 5K Launch");
    assert.equal(payload.weekNumber, 2);
    assert.equal(payload.steps.length, 3);
  });

  it("rejects malformed input before a trusted UID read is possible", () => {
    assert.throws(
      () => parseHomeGuidePlanDisplayContext({ ...validPayload(), xp: 999 }),
      HomeGuideContractError,
    );
    assert.throws(
      () => parseHomeGuidePlanDisplayContext({ ...validPayload(), durationMinutes: 0 }),
      HomeGuideContractError,
    );
    assert.throws(
      () => parseHomeGuidePlanDisplayContext("not-an-object"), HomeGuideContractError);
  });

  it("normalizes bounded display text without accepting prompt-shaped fields", () => {
    const payload = parseHomeGuidePlanDisplayContext({
      ...validPayload(),
      planTitle: "  Beginner 5K Launch  ",
      description: "Steady\n and comfortable.",
    });

    assert.equal(payload.planTitle, "Beginner 5K Launch");
    assert.equal(payload.description, "Steady and comfortable.");
  });
});

function validPayload(): Record<string, unknown> {
  return {
    planTitle: "Beginner 5K Launch",
    weekNumber: 2,
    weekFocus: "Build endurance",
    dayLabel: "Wednesday",
    workoutTitle: "Easy Run",
    durationMinutes: 25,
    intensity: "easy",
    description: "Steady and comfortable.",
    steps: ["Warm up with a brisk walk", "Run easy", "Cool down"],
    supportiveNote: "You've got this.",
  };
}
