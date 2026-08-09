import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

import { SystemConfigSummary } from "../SystemConfigSummary";
import { formatDateTime } from "@/lib/admin/format";
import type { ConfigSummary } from "@/lib/admin/live-data";

const summaries: ConfigSummary[] = [
  {
    id: "progression",
    label: "Progression (XP & levels)",
    href: "/admin/gamification",
    version: 3,
    updatedAt: "2026-07-15T08:30:00.000Z",
    updatedBy: "admin@runiac.app",
    configured: true,
  },
  {
    id: "leaderboard",
    label: "Leaderboard",
    href: "/admin/leaderboard",
    version: null,
    updatedAt: null,
    updatedBy: null,
    configured: false,
  },
];

describe("SystemConfigSummary", () => {
  it("shows a version chip for a configured entry", () => {
    render(<SystemConfigSummary summaries={summaries} />);

    expect(screen.getByText("v3")).toBeInTheDocument();
  });

  it("shows a 'Using defaults' chip for an unconfigured entry", () => {
    render(<SystemConfigSummary summaries={summaries} />);

    expect(screen.getByText("Using defaults")).toBeInTheDocument();
  });

  it("does not show a 'Using defaults' chip for a configured entry", () => {
    render(<SystemConfigSummary summaries={[summaries[0]]} />);

    expect(screen.queryByText("Using defaults")).not.toBeInTheDocument();
  });

  it("links Manage to each summary's href", () => {
    render(<SystemConfigSummary summaries={summaries} />);

    const links = screen.getAllByRole("link", { name: "Manage" });
    expect(links[0]).toHaveAttribute("href", "/admin/gamification");
    expect(links[1]).toHaveAttribute("href", "/admin/leaderboard");
  });

  it("renders formatted last-updated text and the updatedBy actor for a configured entry", () => {
    render(<SystemConfigSummary summaries={summaries} />);

    const formatted = formatDateTime(summaries[0].updatedAt as string);
    expect(
      screen.getByText(new RegExp(`Last updated ${formatted}`)),
    ).toBeInTheDocument();
    expect(screen.getByText(/admin@runiac\.app/)).toBeInTheDocument();
  });

  it("renders a 'not yet saved' message for an entry with no updatedAt", () => {
    render(<SystemConfigSummary summaries={summaries} />);

    expect(
      screen.getByText("Not yet saved to a live config document"),
    ).toBeInTheDocument();
  });
});
