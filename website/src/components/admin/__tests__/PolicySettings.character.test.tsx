import { describe, expect, it, vi, beforeEach } from "vitest";
import { fireEvent, render, screen, within } from "@testing-library/react";

import { PolicySettings } from "../PolicySettings";
import {
  DEFAULT_AUTOMATION_CONFIG,
  DEFAULT_CHALLENGE_ACCESS_CONFIG,
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  DEFAULT_FEATURE_ACCESS_CONFIG,
} from "@/lib/admin/config-validation";

const saveCharacterAccessConfigMock = vi.fn();

// The server actions module is "use server" and pulls in firebase-admin /
// server-only deps that must never load under jsdom. Mock the whole module.
vi.mock("@/lib/actions/admin", () => ({
  saveAutomationConfig: vi.fn(),
  saveChallengeAccessConfig: vi.fn(),
  saveCharacterAccessConfig: (...args: unknown[]) => saveCharacterAccessConfigMock(...args),
  saveFeatureAccessConfig: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

function renderPolicySettings() {
  render(
    <PolicySettings
      featureAccessConfig={DEFAULT_FEATURE_ACCESS_CONFIG}
      automationConfig={DEFAULT_AUTOMATION_CONFIG}
      challengeAccessConfig={DEFAULT_CHALLENGE_ACCESS_CONFIG}
      characterAccessConfig={DEFAULT_CHARACTER_ACCESS_CONFIG}
    />,
  );
}

function characterSection() {
  return screen.getByText("Character access").closest("section") as HTMLElement;
}

function rowFor(name: string) {
  const section = within(characterSection());
  return section.getByText(name).closest("li") as HTMLElement;
}

describe("PolicySettings — Character access", () => {
  beforeEach(() => {
    saveCharacterAccessConfigMock.mockReset();
  });

  it("renders all four characters with the default premium-only state", () => {
    renderPolicySettings();

    // Bolt and Mila are open to all; Cap and Ivy are premium-only by default.
    expect(within(rowFor("Bolt")).getByText("Open to all")).toBeInTheDocument();
    expect(within(rowFor("Mila")).getByText("Open to all")).toBeInTheDocument();
    expect(within(rowFor("Cap")).getByText("Premium only")).toBeInTheDocument();
    expect(within(rowFor("Ivy")).getByText("Premium only")).toBeInTheDocument();

    expect(within(rowFor("Bolt")).getByRole("checkbox")).not.toBeChecked();
    expect(within(rowFor("Cap")).getByRole("checkbox")).toBeChecked();
  });

  it("saves the toggled premium-only character list", async () => {
    saveCharacterAccessConfigMock.mockResolvedValue({ ok: true, live: true });
    renderPolicySettings();

    // Promote Bolt to premium-only.
    fireEvent.click(within(rowFor("Bolt")).getByRole("checkbox"));
    fireEvent.click(
      within(characterSection()).getByRole("button", { name: "Save character access" }),
    );

    expect(saveCharacterAccessConfigMock).toHaveBeenCalledTimes(1);
    const saved = saveCharacterAccessConfigMock.mock.calls[0][0];
    // Persisted in catalog display order: blue, cap, pink, purple.
    expect(saved.premiumOnlyCharacters).toEqual(["blue", "cap", "purple"]);
  });
});
