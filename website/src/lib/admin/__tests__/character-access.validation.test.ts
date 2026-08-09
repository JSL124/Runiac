import { describe, expect, it } from "vitest";

import {
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  validateCharacterAccessConfig,
  type CharacterAccessConfig,
} from "../config-validation";

// Mirrors functions/test/configLoader.test.ts validateCharacterAccessConfig.
// The cross-repo drift check keeps the two validators token-identical; this
// suite locks the admin console's own copy of the contract.
describe("validateCharacterAccessConfig", () => {
  it("accepts the defaults (Cap and Ivy premium-only)", () => {
    expect(validateCharacterAccessConfig(DEFAULT_CHARACTER_ACCESS_CONFIG).valid).toBe(true);
    expect(DEFAULT_CHARACTER_ACCESS_CONFIG.premiumOnlyCharacters).toEqual(["cap", "purple"]);
  });

  it("accepts an empty list (every character open)", () => {
    expect(
      validateCharacterAccessConfig({ premiumOnlyCharacters: [], version: 1 }).valid,
    ).toBe(true);
  });

  it("rejects unknown character ids", () => {
    const result = validateCharacterAccessConfig({
      premiumOnlyCharacters: ["cap", "green"],
      version: 1,
    });
    expect(result.valid).toBe(false);
    expect(result.errors.some((error) => error.startsWith("premiumOnlyCharacters"))).toBe(true);
  });

  it("rejects duplicates", () => {
    const result = validateCharacterAccessConfig({
      premiumOnlyCharacters: ["cap", "cap"],
      version: 1,
    });
    expect(result.valid).toBe(false);
  });

  it("rejects a non-array", () => {
    const result = validateCharacterAccessConfig({
      premiumOnlyCharacters: "cap",
      version: 1,
    } as unknown as CharacterAccessConfig);
    expect(result.valid).toBe(false);
  });
});
