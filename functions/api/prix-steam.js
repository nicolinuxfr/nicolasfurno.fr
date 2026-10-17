const DAY = 86400;

function failure(status) {
  return Response.json({ error: "Prix indisponible" }, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export async function onRequest({ request, waitUntil }) {
  if (request.method !== "GET") return failure(405);
  const url = new URL(request.url);
  const id = url.searchParams.get("id");
  if (!/^[1-9]\d{0,9}$/.test(id ?? "")) return failure(400);

  // Ignore les autres paramètres et normalise la route pour partager le cache.
  const key = new Request(`${url.origin}/api/prix-steam?id=${id}`);
  const cache = caches.default;
  const cached = await cache.match(key);
  if (cached) {
    // Le cache navigateur expire à la même date que la donnée côté serveur.
    const response = new Response(cached.body, cached);
    const remaining = Math.max(0, Math.floor(
      (Number(cached.headers.get("X-Price-Expires")) - Date.now()) / 1000,
    ));
    response.headers.set("Cache-Control", `public, max-age=${remaining}`);
    return response;
  }

  try {
    const upstream = await fetch(
      `https://store.steampowered.com/api/appdetails?appids=${id}&cc=fr&l=french`,
      { signal: AbortSignal.timeout(5000) },
    );
    if (!upstream.ok) return failure(502);
    const payload = await upstream.json();
    const game = payload[id];
    if (!game?.success || !game.data) return failure(502);
    const price = game.data.price_overview;
    const free = game.data.is_free === true;
    if (!free && (price?.currency !== "EUR" ||
        !Number.isSafeInteger(price.final) || price.final < 0)) return failure(502);

    const response = Response.json({
      final: free ? 0 : price.final,
      currency: "EUR",
      free,
    }, { headers: {
      "Cache-Control": `public, max-age=${DAY}`,
      "X-Price-Expires": String(Date.now() + DAY * 1000),
    } });
    waitUntil(cache.put(key, response.clone()).catch(() => {}));
    return response;
  } catch {
    return failure(502);
  }
}
