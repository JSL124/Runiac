import { describe, expect, it, vi, beforeEach } from "vitest";
import { fireEvent, render, screen, within } from "@testing-library/react";

import { PolicySettings } from "../PolicySettings";
import {
  DEFAULT_AUTOMATION_CONFIG,
  DEFAULT_CHALLENGE_ACCESS_CONFIG,
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  DEFAULT_FEATURE_ACCESS_CONFIG,
  type AutomationConfig,
} from "@/lib/admin/config-validation";

const saveAutomationConfigMock = vi.fn();

// The server actions module is "use server" and pulls in firebase-admin /
// server-only deps that must never load under jsdom. Mock the whole module.
vi.mock("@/lib/actions/admin", () => ({
  saveAutomationConfig: (...args: unknown[]) => saveAutomationConfigMock(...args),
  saveChallengeAccessConfig: vi.fn(),
  saveCharacterAccessConfig: vi.fn(),
  saveFeatureAccessConfig: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

function renderPolicySettings(automationConfig: AutomationConfig = DEFAULT_AUTOMATION_CONFIG) {
  render(
    <PolicySettings
      featureAccessConfig={DEFAULT_FEATURE_ACCESS_CONFIG}
      automationConfig={automationConfig}
      challengeAccessConfig={DEFAULT_CHALLENGE_ACCESS_CONFIG}
      characterAccessConfig={DEFAULT_CHARACTER_ACCESS_CONFIG}
    />,
  );
}

function sectionFor(heading: string) {
  return screen.getByText(heading).closest("section") as HTMLElement;
}

// A rule is one <li> holding its switch AND its threshold, so the same box is
// reachable by either label.
function ruleBox(label: string) {
  return within(sectionFor("Moderation automation"))
    .getByText(label)
    .closest("li") as HTMLElement;
}

function switchFor(label: string) {
  return within(ruleBox(label)).getByRole("checkbox");
}

function saveAutomation() {
  fireEvent.click(screen.getByRole("button", { name: "Save automation settings" }));
  fireEvent.click(screen.getByRole("button", { name: "Confirm save" }));
}

describe("PolicySettings — Automation thresholds", () => {
  beforeEach(() => {
    saveAutomationConfigMock.mockReset();
    saveAutomationConfigMock.mockResolvedValue({ ok: true, live: true });
  });

  it("collapses the auto-hide threshold to a read-only value while auto-hide is off", () => {
    // DEFAULT_AUTOMATION_CONFIG has autoHide.enabled === false.
    renderPolicySettings();

    expect(screen.queryByLabelText("Auto-hide report threshold")).toBeNull();

    const row = ruleBox("Report threshold");
    expect(within(row).getByText("Inactive")).toBeInTheDocument();
    expect(within(row).getByText(/3\s+reports/)).toBeInTheDocument();
    expect(
      within(row).getByText(/Turn this rule on to change the threshold/),
    ).toBeInTheDocument();
  });

  it("keeps the stale-report age editable because its own switch is on by default", () => {
    renderPolicySettings();

    expect(screen.getByLabelText("Stale report escalation age in days")).toBeInTheDocument();
    expect(within(ruleBox("Escalation age")).queryByText("Inactive")).toBeNull();
  });

  it("collapses the stale-report age as soon as its own switch is turned off", () => {
    renderPolicySettings();

    fireEvent.click(switchFor("Escalate stale reports"));

    expect(screen.queryByLabelText("Stale report escalation age in days")).toBeNull();
    const row = ruleBox("Escalation age");
    expect(within(row).getByText("Inactive")).toBeInTheDocument();
    expect(within(row).getByText(/7\s+day\(s\)/)).toBeInTheDocument();
  });

  it("unlocks the threshold from the DRAFT switch so enabling and retuning save together", () => {
    renderPolicySettings();

    // Turning the switch on must reveal the slider immediately, without an
    // intermediate save. Gating on the saved prop instead would force
    // enable -> save -> retune -> save, and auto-hide would run at the old
    // threshold in between.
    fireEvent.click(switchFor("Auto-hide reported posts"));

    const slider = screen.getByLabelText("Auto-hide report threshold");
    fireEvent.change(slider, { target: { value: "2" } });

    saveAutomation();

    expect(saveAutomationConfigMock).toHaveBeenCalledTimes(1);
    expect(saveAutomationConfigMock.mock.calls[0][0].autoHide).toEqual({
      enabled: true,
      reportThreshold: 2,
    });
  });

  it("hides the scheduled jobs and notification rules but still saves their stored values", () => {
    // The scheduled.* toggles and the notifications block were removed from
    // this screen on purpose. Removing a CONTROL must never rewrite the VALUE:
    // the Cloud Functions that read them keep whatever the config already had.
    const stored: AutomationConfig = {
      ...DEFAULT_AUTOMATION_CONFIG,
      scheduled: {
        leaderboardSnapshotRefresh: false,
        subscriptionExpirySweep: true,
        pushNotificationDispatch: false,
      },
      notifications: {
        notifyErrorGroups: false,
        minimumErrorSeverity: "high",
        notifyNewReports: true,
      },
    };
    renderPolicySettings(stored);

    for (const gone of [
      "Leaderboard snapshot refresh",
      "Subscription expiry sweep",
      "Push notification dispatch",
      "Alert on serious error groups",
      "Alert on new reports",
      "Minimum severity",
    ]) {
      expect(screen.queryByText(gone)).toBeNull();
    }

    fireEvent.click(switchFor("Auto-hide reported posts"));
    saveAutomation();

    const saved = saveAutomationConfigMock.mock.calls[0][0];
    expect(saved.scheduled).toEqual(stored.scheduled);
    expect(saved.notifications).toEqual(stored.notifications);
  });

  it("still saves a collapsed threshold value instead of dropping it to the default", () => {
    // Collapsing is an editing affordance, never a reset: the tuned 9 must
    // survive a save made while the slider is hidden.
    renderPolicySettings({
      ...DEFAULT_AUTOMATION_CONFIG,
      autoHide: { enabled: true, reportThreshold: 9 },
    });

    fireEvent.click(switchFor("Auto-hide reported posts"));
    expect(screen.queryByLabelText("Auto-hide report threshold")).toBeNull();

    saveAutomation();

    expect(saveAutomationConfigMock.mock.calls[0][0].autoHide).toEqual({
      enabled: false,
      reportThreshold: 9,
    });
  });
});
