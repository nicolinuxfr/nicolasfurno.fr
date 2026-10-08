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

  it("scopes diffusion and format to the selected season", () => {
    const babyFever = {
      ...prepared,
      details: [
        { label: "Diffuseur", value: "Netflix" },
        { label: "Titre original", value: "Skruek" },
        { label: "Diffusion", value: "2022-06-08 → 2024-08-22" },
        { label: "Format", value: "12 épisodes · 30 min" },
      ],
      seasons: [
        { value: "1", label: "Saison 1", year: "2022", episodes: 6 },
        { value: "2", label: "Saison 2", year: "2024", episodes: 6 },
      ],
    };

    expect(prepareSeriesSelection(babyFever, "2").details).toEqual([
      { label: "Diffuseur", value: "Netflix" },
      { label: "Titre original", value: "Skruek" },
      { label: "Diffusion", value: "2024" },
      { label: "Format", value: "6 épisodes · 30 min" },
    ]);
  });

  it("spans years and totals episodes across a selected range", () => {
    const series = {
      label: "*Série*, Chaîne",
      suggestedSlug: "serie-chaine",
      details: [
        { label: "Diffusion", value: "2020-01-01 → 2025-12-31" },
        { label: "Format", value: "30 épisodes" },
      ],
      seasons: [
        { value: "1", label: "Saison 1", year: "2020", episodes: 10 },
        { value: "2", label: "Saison 2", year: "2022", episodes: 8 },
        { value: "3", label: "Saison 3", year: "2025", episodes: 12 },
      ],
    };

    expect(prepareSeriesSelection(series, "2-3").details).toEqual([
      { label: "Diffusion", value: "2022 → 2025" },
      { label: "Format", value: "20 épisodes" },
    ]);
  });

  it("leaves details untouched when season metadata is unavailable", () => {
    const untouched = {
      label: "*Série*, Chaîne",
      suggestedSlug: "serie-chaine",
      details: [{ label: "Format", value: "30 épisodes" }],
    };

    expect(prepareSeriesSelection(untouched, "2").details).toEqual([
      { label: "Format", value: "30 épisodes" },
    ]);
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
