const frenchDate = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

function formatSingleDate(value: string): string {
  const iso = /^\d{4}-\d{2}-\d{2}$/.test(value);
  const textual = /^\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4}$/.test(value);
  if (!iso && !textual) return value;
  const date = new Date(iso ? `${value}T00:00:00Z` : value);
  return Number.isNaN(date.getTime()) ? value : frenchDate.format(date);
}

export function formatDisplayValue(value: string): string {
  const parts = value.split(" → ").map((part) => formatSingleDate(part));
  return parts.length === 2 && parts[0] === parts[1]
    ? parts[0]
    : parts.join(" → ");
}
