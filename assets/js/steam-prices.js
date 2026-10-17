const prices = new Map();
const currency = new Intl.NumberFormat("fr-FR", {
  style: "currency", currency: "EUR",
});

function validPrice(price) {
  return price?.currency === "EUR" && Number.isSafeInteger(price.final) &&
    price.final >= 0 && typeof price.free === "boolean";
}

async function getPrice(id) {
  const key = `steam-price:fr:EUR:v1:${id}`;
  try {
    const cached = JSON.parse(localStorage.getItem(key));
    if (validPrice(cached?.price) && Number.isFinite(cached.expires) &&
        cached.expires > Date.now()) return cached.price;
  } catch {
    // Le stockage peut être bloqué ou contenir une entrée illisible.
  }

  const response = await fetch(`/api/prix-steam?id=${encodeURIComponent(id)}`, {
    signal: AbortSignal.timeout(7000),
  });
  if (!response.ok) throw new Error("Prix indisponible");
  const price = await response.json();
  if (!validPrice(price)) throw new Error("Prix invalide");

  // Ne prolonge pas l'expiration serveur, même avec une réponse du cache HTTP.
  const expires = Number(response.headers.get("X-Price-Expires"));
  if (Number.isFinite(expires) && expires > Date.now()) {
    try {
      localStorage.setItem(key, JSON.stringify({ price, expires }));
    } catch {
      // Un stockage bloqué ou plein n'empêche pas l'affichage du prix.
    }
  }
  return price;
}

async function updatePrice(link) {
  const id = link.dataset.steamId;
  try {
    if (!prices.has(id)) {
      prices.set(id, getPrice(id));
    }
    const price = await prices.get(id);
    link.textContent = price.free
      ? "Jouer gratuitement"
      : `Acheter (${currency.format(price.final / 100)})`;
  } catch {
    // Garde le prix de meta.json si Steam ou la fonction sont indisponibles.
  }
}

document.querySelectorAll("a[data-steam-id]").forEach(updatePrice);
