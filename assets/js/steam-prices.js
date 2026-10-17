const prices = new Map();
const currency = new Intl.NumberFormat("fr-FR", {
  style: "currency", currency: "EUR",
});

async function updatePrice(link) {
  const id = link.dataset.steamId;
  try {
    if (!prices.has(id)) {
      prices.set(id, fetch(`/api/prix-steam?id=${encodeURIComponent(id)}`, {
        signal: AbortSignal.timeout(7000),
      }).then(async (response) => {
        if (!response.ok) throw new Error("Prix indisponible");
        return response.json();
      }));
    }
    const price = await prices.get(id);
    if (price.currency !== "EUR" || !Number.isSafeInteger(price.final) || price.final < 0) return;
    link.textContent = price.free
      ? "Jouer gratuitement"
      : `Acheter (${currency.format(price.final / 100)})`;
  } catch {
    // Garde le prix de meta.json si Steam ou la fonction sont indisponibles.
  }
}

document.querySelectorAll("a[data-steam-id]").forEach(updatePrice);
