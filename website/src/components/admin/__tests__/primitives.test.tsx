import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

import { StatCard, StatusPill } from "../primitives";

describe("StatCard", () => {
  it("renders the label, value, and hint", () => {
    render(
      <StatCard label="Registered users" value={128} hint="Backend-reported" />,
    );

    expect(screen.getByText("Registered users")).toBeInTheDocument();
    expect(screen.getByText("128")).toBeInTheDocument();
    expect(screen.getByText("Backend-reported")).toBeInTheDocument();
  });

  it("does not render an hint paragraph when hint is omitted", () => {
    render(<StatCard label="Registered users" value={128} />);

    expect(screen.queryByText("Backend-reported")).not.toBeInTheDocument();
  });

  it("applies the neutral (brand) tone class by default", () => {
    render(<StatCard label="Label" value="42" />);

    expect(screen.getByText("42")).toHaveClass("text-brand");
  });

  it("applies the accent tone class", () => {
    render(<StatCard label="Label" value="42" tone="accent" />);

    expect(screen.getByText("42")).toHaveClass("text-accent");
  });

  it("applies the critical tone class", () => {
    render(<StatCard label="Label" value="42" tone="critical" />);

    expect(screen.getByText("42")).toHaveClass("text-[#b42318]");
  });
});

describe("StatusPill", () => {
  it("renders 'Operational' for status operational", () => {
    render(<StatusPill status="operational" />);

    expect(screen.getByText("Operational")).toBeInTheDocument();
  });

  it("renders 'Degraded' for status degraded", () => {
    render(<StatusPill status="degraded" />);

    expect(screen.getByText("Degraded")).toBeInTheDocument();
  });

  it("renders 'Down' for status down", () => {
    render(<StatusPill status="down" />);

    expect(screen.getByText("Down")).toBeInTheDocument();
  });
});
