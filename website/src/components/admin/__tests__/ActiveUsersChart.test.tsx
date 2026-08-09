import { beforeAll, describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

import { ActiveUsersChart } from "../ActiveUsersChart";
import type { ActiveUsersPoint } from "@/lib/admin/types";

// Recharts' <ResponsiveContainer> observes its own size via ResizeObserver,
// which jsdom does not implement. A minimal stub is enough for the chart to
// mount without throwing; we never assert on the SVG it (doesn't) produce at
// 0x0, only on the accessible wrapper ActiveUsersChart renders around it.
beforeAll(() => {
  if (!("ResizeObserver" in globalThis)) {
    class ResizeObserverStub {
      observe() {}
      unobserve() {}
      disconnect() {}
    }

    (globalThis as { ResizeObserver?: unknown }).ResizeObserver =
      ResizeObserverStub;
  }
});

const data: ActiveUsersPoint[] = [
  { label: "Feb", activeUsers: 12000 },
  { label: "Mar", activeUsers: 12500 },
  { label: "Jul", activeUsers: 15800 },
];

describe("ActiveUsersChart", () => {
  it("renders an accessible image role", () => {
    render(<ActiveUsersChart data={data} />);

    expect(screen.getByRole("img")).toBeInTheDocument();
  });

  it("labels the chart with the first and last point labels", () => {
    render(<ActiveUsersChart data={data} />);

    const chart = screen.getByRole("img");
    expect(chart).toHaveAttribute(
      "aria-label",
      expect.stringContaining("Feb"),
    );
    expect(chart).toHaveAttribute(
      "aria-label",
      expect.stringContaining("Jul"),
    );
  });

  it("renders without throwing for a single data point", () => {
    expect(() =>
      render(
        <ActiveUsersChart data={[{ label: "Jul", activeUsers: 1000 }]} />,
      ),
    ).not.toThrow();
  });

  it("renders without throwing for an empty data set", () => {
    expect(() => render(<ActiveUsersChart data={[]} />)).not.toThrow();
  });
});
