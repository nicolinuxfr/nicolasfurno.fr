import { describe, expect, it } from "vitest";
import { formatDisplayValue } from "./format";

describe("formatDisplayValue", () => {
  it("francise une date ISO", () => {
    expect(formatDisplayValue("2026-03-15")).toBe("15 mars 2026");
  });

  it("francise une plage de diffusion", () => {
    expect(formatDisplayValue("2024-01-02 → 2025-02-01")).toBe(
      "2 janvier 2024 → 1 février 2025",
    );
  });

  it("n’affiche qu’une fois deux dates identiques", () => {
    expect(formatDisplayValue("2026-03-05 → 2026-03-05")).toBe("5 mars 2026");
  });

  it("conserve les valeurs qui ne sont pas des dates complètes", () => {
    expect(formatDisplayValue("155 min")).toBe("155 min");
    expect(formatDisplayValue("2022")).toBe("2022");
  });
});
