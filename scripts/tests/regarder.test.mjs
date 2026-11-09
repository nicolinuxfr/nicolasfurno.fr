import test from "node:test";
import assert from "node:assert/strict";
import { onRequest } from "../../functions/api/regarder.js";

test("filtre les offres par pays, abonnement et saison sans partager la réponse géolocalisée", async () => {
  const oldFetch = globalThis.fetch;
  const oldCaches = globalThis.caches;
  const option = (id, type = "subscription", addon) => ({ service: { id, name: id }, type, addon, link: `https://${id}.example/title` });
  let calls = 0;
  let saved;
  globalThis.caches = { default: { match: async () => saved?.clone(), put: async (_, response) => { saved = response.clone(); } } };
  globalThis.fetch = async () => {
    calls++;
    return Response.json({ tmdbId: "tv/42", streamingOptions: {
      fr: [option("netflix"), option("prime", "addon", {}), option("apple", "buy")],
      ca: [option("prime")],
    }, seasons: [
      { title: "Season 1", streamingOptions: { fr: [option("netflix")] } },
      { title: "Season 2", streamingOptions: { fr: [option("netflix")] } },
      { title: "Season 3", streamingOptions: { fr: [option("prime")] } },
    ] });
  };
  const run = async (country, query = "") => {
    const request = new Request(`https://example.com/api/regarder?type=tv&id=42${query}`);
    request.cf = { country };
    const pending = [];
    const response = await onRequest({ request, env: { MOTN_API_KEY: "test" }, waitUntil: (p) => pending.push(p) });
    await Promise.all(pending);
    assert.equal(response.headers.get("cache-control"), "private, no-store");
    return (await response.json()).services.map((item) => item.name);
  };
  try {
    assert.deepEqual(await run("FR"), ["netflix"]);
    assert.deepEqual(await run("CA"), ["prime"]);
    assert.deepEqual(await run("FR", "&saisons=1"), ["netflix"]);
    assert.deepEqual(await run("FR", "&saisons=1,2"), ["netflix"]);
    assert.deepEqual(await run("FR", "&saisons=1,3"), []);
    assert.deepEqual(await run("FR", "&saisons=9"), []);
    assert.equal(calls, 1);
  } finally {
    globalThis.fetch = oldFetch;
    globalThis.caches = oldCaches;
  }
});
