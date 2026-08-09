import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import { AttentionItemsPanel } from "../AttentionItemsPanel";
import type { AttentionItem } from "@/lib/admin/types";

const dismissAttentionItemMock = vi.fn();

vi.mock("@/lib/actions/admin", () => ({
  dismissAttentionItem: (...args: [string]) =>
    dismissAttentionItemMock(...args),
}));

const refreshMock = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: refreshMock }),
}));

const items: AttentionItem[] = [
  {
    id: "item-1",
    title: "Suspicious leaderboard score",
    detail: "Runner flagged by anomaly detection",
    severity: "high",
    href: "/admin/leaderboard",
  },
  {
    id: "item-2",
    title: "Pending report",
    detail: "A user reported a route",
    severity: "medium",
    href: "/admin/exceptions",
  },
];

describe("AttentionItemsPanel", () => {
  beforeEach(() => {
    dismissAttentionItemMock.mockReset();
    refreshMock.mockReset();
  });

  it("renders the empty-state paragraph when there are no items", () => {
    render(<AttentionItemsPanel items={[]} />);

    expect(
      screen.getByText(/Nothing needs attention right now/i),
    ).toBeInTheDocument();
  });

  it("renders one row per item with title, detail, a Review label, and a Dismiss control", () => {
    render(<AttentionItemsPanel items={items} />);

    for (const item of items) {
      expect(screen.getByText(item.title)).toBeInTheDocument();
      expect(screen.getByText(item.detail)).toBeInTheDocument();
    }

    expect(screen.getAllByText("Review")).toHaveLength(items.length);
    expect(
      screen.getAllByRole("button", { name: "Dismiss" }),
    ).toHaveLength(items.length);
  });

  it("calls dismissAttentionItem with the item id when Dismiss is clicked", async () => {
    dismissAttentionItemMock.mockResolvedValue({ ok: true, live: false });
    const user = userEvent.setup();
    render(<AttentionItemsPanel items={items} />);

    const [firstDismissButton] = screen.getAllByRole("button", {
      name: "Dismiss",
    });
    await user.click(firstDismissButton);

    await waitFor(() =>
      expect(dismissAttentionItemMock).toHaveBeenCalledWith("item-1"),
    );
  });

  it("calls router.refresh() when the action resolves live: true", async () => {
    dismissAttentionItemMock.mockResolvedValue({ ok: true, live: true });
    const user = userEvent.setup();
    render(<AttentionItemsPanel items={items} />);

    const [firstDismissButton] = screen.getAllByRole("button", {
      name: "Dismiss",
    });
    await user.click(firstDismissButton);

    await waitFor(() => expect(refreshMock).toHaveBeenCalledTimes(1));
  });

  it("does not call router.refresh() when the action resolves live: false", async () => {
    dismissAttentionItemMock.mockResolvedValue({ ok: true, live: false });
    const user = userEvent.setup();
    render(<AttentionItemsPanel items={items} />);

    const [firstDismissButton] = screen.getAllByRole("button", {
      name: "Dismiss",
    });
    await user.click(firstDismissButton);

    await waitFor(() =>
      expect(dismissAttentionItemMock).toHaveBeenCalledWith("item-1"),
    );
    expect(refreshMock).not.toHaveBeenCalled();
  });

  it("shows error text when the action resolves an error shape", async () => {
    dismissAttentionItemMock.mockResolvedValue({
      ok: false,
      error: "The backend rejected this action. Try again.",
    });
    const user = userEvent.setup();
    render(<AttentionItemsPanel items={items} />);

    const [firstDismissButton] = screen.getAllByRole("button", {
      name: "Dismiss",
    });
    await user.click(firstDismissButton);

    expect(
      await screen.findByText("The backend rejected this action. Try again."),
    ).toBeInTheDocument();
    expect(refreshMock).not.toHaveBeenCalled();
  });
});
