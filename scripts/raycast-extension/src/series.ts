type Detail = { label: string; value: string };
type SeasonOption = {
  value: string;
  label: string;
  year?: string;
  episodes?: number;
};

type PreparedSeries = {
  label: string;
  suggestedSlug: string;
  details?: Detail[];
  seasons?: SeasonOption[];
};

function selectionSeasonNumbers(selection: string): Set<number> {
  const [start, end] = selection.split("-");
  const from = Number(start);
  const to = end ? Number(end) : from;
  const numbers = new Set<number>();
  for (let season = from; season <= to; season += 1) numbers.add(season);
  return numbers;
}

function yearSpan(years: string[]): string {
  if (years.length === 0) return "";
  const sorted = [...years].sort();
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  return first === last ? first : `${first} → ${last}`;
}

function scopeSelectionDetails(
  details: Detail[] | undefined,
  seasons: SeasonOption[] | undefined,
  selection: string,
): Detail[] | undefined {
  if (!details) return undefined;
  const wanted = selectionSeasonNumbers(selection);
  const selected = (seasons ?? []).filter((season) =>
    wanted.has(Number(season.value)),
  );
  if (selected.length === 0) return details;

  const years = selected
    .map((season) => season.year ?? "")
    .filter((year) => year !== "");
  const episodes = selected.reduce(
    (total, season) => total + (season.episodes ?? 0),
    0,
  );

  return details.map((detail) => {
    if (detail.label === "Diffusion") {
      const span = yearSpan(years);
      return span ? { ...detail, value: span } : detail;
    }
    if (detail.label === "Format" && episodes > 0) {
      const runtime = detail.value.match(/\s·\s.*$/)?.[0] ?? "";
      return { ...detail, value: `${episodes} épisodes${runtime}` };
    }
    return detail;
  });
}

export function normalizeSeasonSelection(values: string[]) {
  const selected = values
    .filter((value) => value !== "all")
    .map(Number)
    .sort((a, b) => a - b);

  if (selected.length === 0) {
    if (values.includes("all")) return "all";
    throw new Error("Choisir au moins une saison.");
  }
  if (selected.some((value) => !Number.isInteger(value) || value <= 0)) {
    throw new Error("La sélection de saisons est invalide.");
  }
  if (
    selected.some(
      (value, index) => index > 0 && value !== selected[index - 1] + 1,
    )
  ) {
    throw new Error("Les saisons sélectionnées doivent être contiguës.");
  }

  return selected.length === 1
    ? String(selected[0])
    : `${selected[0]}-${selected[selected.length - 1]}`;
}

export function prepareSeriesSelection<T extends PreparedSeries>(
  prepared: T,
  selection: string,
): T {
  if (selection === "all" || selection === "1") return prepared;

  const [start, end] = selection.split("-");
  const qualifier = end
    ? Number(end) === Number(start) + 1
      ? `saisons\u00a0${start} et\u00a0${end}`
      : `saisons\u00a0${start} à\u00a0${end}`
    : `saison\u00a0${start}`;

  return {
    ...prepared,
    label: `${prepared.label} (${qualifier})`,
    suggestedSlug: `${prepared.suggestedSlug}-${end ? "saisons" : "saison"}-${selection}`,
    details: scopeSelectionDetails(prepared.details, prepared.seasons, selection),
  };
}

export function seasonRequestValue(selection: string) {
  if (selection === "all" || !selection.includes("-")) return selection;

  const [start, end] = selection.split("-").map(Number);
  return Array.from(
    { length: end - start + 1 },
    (_, index) => start + index,
  ).join(",");
}
