import { describe, expect, it } from "vitest";
import {
  normalizeSeasonSelection,
  prepareSeriesSelection,
  seasonRequestValue,
} from "./series";

describe("normalizeSeasonSelection", () => {
  it("keeps the whole-series choice", () => {
    expect(normalizeSeasonSelection(["all"])).toBe("all");
  });

  it("sorts and compacts contiguous seasons", () => {
    expect(normalizeSeasonSelection(["9", "8"])).toBe("8-9");
  });

  it("prefers explicit seasons when all is still selected", () => {
    expect(normalizeSeasonSelection(["all", "8", "9"])).toBe("8-9");
  });

  it("rejects an empty or discontinuous selection", () => {
    expect(() => normalizeSeasonSelection([])).toThrow("au moins une saison");
    expect(() => normalizeSeasonSelection(["7", "9"])).toThrow("contiguës");
  });
});

describe("prepareSeriesSelection", () => {
  const prepared = {
    label: "*Rick et Morty*, Adult Swim",
    suggestedSlug: "rick-morty-adult-swim",
  };

  it("qualifies the title and slug before the final form", () => {
    expect(prepareSeriesSelection(prepared, "8-9")).toEqual({
      label: "*Rick et Morty*, Adult Swim (saisons\u00a08 et\u00a09)",
      suggestedSlug: "rick-morty-adult-swim-saisons-8-9",
    });
  });

  it("keeps the base presentation for all seasons and season one", () => {
    expect(prepareSeriesSelection(prepared, "all")).toBe(prepared);
    expect(prepareSeriesSelection(prepared, "1")).toBe(prepared);
  });
});

describe("seasonRequestValue", () => {
  it("expands a range for the Raycast backend bridge", () => {
    expect(seasonRequestValue("8-10")).toBe("8,9,10");
  });

  it("keeps whole-series and single-season choices unchanged", () => {
    expect(seasonRequestValue("all")).toBe("all");
    expect(seasonRequestValue("8")).toBe("8");
  });
});
