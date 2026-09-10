type PreparedSeries = {
  label: string;
  suggestedSlug: string;
};

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
