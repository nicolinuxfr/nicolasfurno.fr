const DAY = 86400;

function failure(status) {
  return Response.json({ error: "Disponibilités indisponibles" }, {
    status, headers: { "Cache-Control": "no-store" },
  });
}

function offers(options, country) {
  const found = new Map();
  for (const item of options?.[country] ?? []) {
    if (item.type !== "subscription" || item.addon || !item.service?.id || !item.service?.name) continue;
    try {
      const url = new URL(item.link);
      if (url.protocol !== "https:") continue;
      if (!found.has(item.service.id)) found.set(item.service.id, { name: item.service.name, link: url.href });
    } catch { /* Lien invalide. */ }
  }
  return found;
}

export async function onRequest({ request, env, waitUntil }) {
  if (request.method !== "GET") return failure(405);
  const url = new URL(request.url);
  const type = url.searchParams.get("type");
  const id = url.searchParams.get("id");
  const seasons = url.searchParams.get("saisons") || "";
  if (!/^(movie|tv)$/.test(type ?? "") || !/^[1-9]\d{0,9}$/.test(id ?? "") ||
      (seasons && (type !== "tv" || !/^\d{1,3}(,\d{1,3}){0,19}$/.test(seasons)))) return failure(400);
  const country = request.cf?.country?.toLowerCase();
  if (!/^[a-z]{2}$/.test(country ?? "") || country === "xx" || country === "t1") {
    return Response.json({ services: [] }, { headers: { "Cache-Control": "no-store" } });
  }
  if (!env.MOTN_API_KEY) return failure(503);

  // Le cache contient toutes les régions et reste interne : aucune réponse géolocalisée n'est partagée.
  const cache = caches.default;
  const key = new Request(`${url.origin}/api/regarder-cache/${type}/${id}`);
  try {
    let cached = await cache.match(key);
    if (!cached) {
      const upstream = await fetch(`https://api.movieofthenight.com/v4/shows/${type}%2F${id}?output_language=en`, {
        headers: { "X-API-Key": env.MOTN_API_KEY }, signal: AbortSignal.timeout(10000),
      });
      if (!upstream.ok) return failure(502);
      const data = await upstream.json();
      if (!data || data.tmdbId !== `${type}/${id}` || !data.streamingOptions) return failure(502);
      const compact = { streamingOptions: data.streamingOptions, seasons: (data.seasons ?? []).map((season) => ({
        title: season.title, streamingOptions: season.streamingOptions,
      })) };
      cached = Response.json(compact, { headers: { "Cache-Control": `public, max-age=${DAY}` } });
      waitUntil(cache.put(key, cached.clone()).catch(() => {}));
    }
    const data = await cached.json();
    let result = offers(data.streamingOptions, country);
    const selected = seasons ? [...new Set(seasons.split(",").map(Number).filter(Boolean))] : [];
    if (selected.length) {
      const matching = selected.map((number) => data.seasons.find((season) => season.title === `Season ${number}`));
      if (matching.some((season) => !season)) result = new Map();
      else if (matching.length === 1) result = offers(matching[0].streamingOptions, country);
      else {
        const availability = matching.map((season) => offers(season.streamingOptions, country));
        result = new Map([...result].filter(([service]) => availability.every((items) => items.has(service))));
      }
    }
    return Response.json({ services: [...result.values()] }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return failure(502);
  }
}
