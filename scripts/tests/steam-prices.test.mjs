import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import { onRequest } from "../../functions/api/prix-steam.js";

test("fonction Steam : cache, expiration, validation et erreurs", async (t) => {
  const originalFetch = globalThis.fetch;
  const originalCaches = globalThis.caches;
  const entries = new Map();
  let calls = 0;
  let data = { success: true, data: { price_overview: { currency: "EUR", final: 1499 } } };
  globalThis.caches = { default: {
    match: async (key) => entries.get(key.url)?.clone(),
    put: async (key, response) => { entries.set(key.url, response); },
  } };
  globalThis.fetch = async (url) => {
    calls++;
    assert.match(url, /cc=fr/);
    return Response.json({ 620: data });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
    if (originalCaches === undefined) delete globalThis.caches;
    else globalThis.caches = originalCaches;
  });
  async function request(query = "id=620", method = "GET") {
    const pending = [];
    const response = await onRequest({
      request: new Request(`https://example.com/api/prix-steam?${query}`, { method }),
      waitUntil: (promise) => pending.push(promise),
    });
    await Promise.all(pending);
    return response;
  }

  const first = await request();
  assert.deepEqual(await first.json(), { final: 1499, currency: "EUR", free: false });
  assert.equal(first.headers.get("Cache-Control"), "public, max-age=86400");
  await request("id=620&extra=ignored");
  assert.equal(calls, 1, "le cache évite un deuxième appel à Steam");

  const key = "https://example.com/api/prix-steam?id=620";
  const cached = entries.get(key);
  cached.headers.set("X-Price-Expires", String(Date.now() + 3600000));
  const hit = await request();
  const ttl = Number(hit.headers.get("Cache-Control").split("=")[1]);
  assert.ok(ttl <= 3600 && ttl > 3590, "le navigateur ne prolonge pas l'âge du prix");

  entries.clear();
  data = { success: true, data: { is_free: true } };
  assert.deepEqual(await (await request()).json(), { final: 0, currency: "EUR", free: true });

  for (const invalid of [
    { success: false },
    { success: true, data: {} },
    { success: true, data: { price_overview: { currency: "USD", final: 1499 } } },
  ]) {
    entries.clear();
    data = invalid;
    const response = await request();
    assert.equal(response.status, 502);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.equal(entries.size, 0);
  }
  globalThis.fetch = async () => { throw new Error("Timeout"); };
  assert.equal((await request()).status, 502);
  assert.equal((await request("id=../foo")).status, 400);
  assert.equal((await request("id=620", "POST")).status, 405);
});

test("navigateur : actualisation automatique et conservation du prix en cas d'erreur", async () => {
  const source = await readFile(new URL("../../assets/js/steam-prices.js", import.meta.url), "utf8");
  async function run(fetch, storage = new Map()) {
    const link = { dataset: { steamId: "620" }, textContent: "Acheter (29,99 €)" };
    const pending = [];
    vm.runInNewContext(source, {
      Intl, AbortSignal, fetch,
      localStorage: {
        getItem: (key) => storage.get(key) ?? null,
        setItem: (key, value) => storage.set(key, value),
      },
      document: { querySelectorAll: () => ({ forEach: (fn) => {
        pending.push(fn(link), fn(link));
      } }) },
    });
    await Promise.all(pending);
    return link.textContent;
  }
  let calls = 0;
  const updated = await run(async () => {
    calls++;
    return Response.json({ final: 1499, currency: "EUR", free: false });
  });
  assert.match(updated, /14,99/);
  assert.equal(calls, 1);
  assert.equal(await run(async () => { throw new Error(); }), "Acheter (29,99 €)");
  assert.equal(await run(async () => new Response("Erreur", { status: 502 })), "Acheter (29,99 €)");
  assert.equal(await run(async () => Response.json({ final: 0, currency: "EUR", free: true })), "Jouer gratuitement");

  const storage = new Map();
  const expires = Date.now() + 3600000;
  const key = "steam-price:fr:EUR:v1:620";
  calls = 0;
  const fetchPrice = async () => {
    calls++;
    return Response.json({ final: 619, currency: "EUR", free: false }, {
      headers: { "X-Price-Expires": String(expires) },
    });
  };
  assert.match(await run(fetchPrice, storage), /6,19/);
  assert.equal(JSON.parse(storage.get(key)).expires, expires);
  assert.match(await run(fetchPrice, storage), /6,19/);
  assert.equal(calls, 1, "une nouvelle page utilise localStorage sans appel réseau");

  storage.set(key, JSON.stringify({ price: { final: 99, currency: "EUR", free: false }, expires: Date.now() - 1 }));
  assert.match(await run(fetchPrice, storage), /6,19/);
  assert.equal(calls, 2, "une entrée expirée est renouvelée");
  storage.set(key, "JSON invalide");
  assert.match(await run(fetchPrice, storage), /6,19/);
  storage.set(key, JSON.stringify({ price: { final: -1, currency: "EUR", free: false }, expires }));
  assert.match(await run(fetchPrice, storage), /6,19/);

  const blocked = { get: () => { throw new Error("Blocked"); }, set: () => { throw new Error("Full"); } };
  assert.match(await run(fetchPrice, blocked), /6,19/);
  storage.set(key, JSON.stringify({ price: { final: 99, currency: "EUR", free: false }, expires: Date.now() - 1 }));
  assert.equal(await run(async () => { throw new Error(); }, storage), "Acheter (29,99 €)");
});
