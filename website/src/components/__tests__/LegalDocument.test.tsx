import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

import { LegalDocument } from "../LegalDocument";

const sections = [
  { heading: "1. Who we are", body: <p>We are Runiac.</p> },
  { heading: "2. Your rights", body: <p>You may ask us to delete data.</p> },
];

function renderDocument() {
  render(
    <LegalDocument
      eyebrow="Legal"
      title="Privacy Policy"
      effectiveDate="26 July 2026"
      intro="What we collect and why."
      sections={sections}
    />,
  );
}

describe("LegalDocument", () => {
  it("renders the eyebrow, title, and intro", () => {
    renderDocument();

    expect(screen.getByText("Legal")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { level: 1, name: "Privacy Policy" }),
    ).toBeInTheDocument();
    expect(screen.getByText("What we collect and why.")).toBeInTheDocument();
  });

  it("renders the effective date", () => {
    renderDocument();

    expect(
      screen.getByText("Effective date: 26 July 2026"),
    ).toBeInTheDocument();
  });

  it("renders every section heading and body", () => {
    renderDocument();

    for (const section of sections) {
      expect(
        screen.getByRole("heading", { level: 2, name: section.heading }),
      ).toBeInTheDocument();
    }
    expect(screen.getByText("We are Runiac.")).toBeInTheDocument();
    expect(
      screen.getByText("You may ask us to delete data."),
    ).toBeInTheDocument();
  });

  it("states that the document is not legal advice", () => {
    renderDocument();

    expect(screen.getByText(/not legal advice/)).toBeInTheDocument();
  });

  it("links the contact email", () => {
    renderDocument();

    expect(screen.getByRole("link", { name: "admin@runiac.app" })).toHaveAttribute(
      "href",
      "mailto:admin@runiac.app",
    );
  });
});
