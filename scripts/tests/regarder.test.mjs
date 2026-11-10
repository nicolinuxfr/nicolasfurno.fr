import test from 'node:test';
import assert from 'node:assert/strict';
import { onRequest } from '../../functions/api/regarder.js';
import { packRecord } from '../regarder.mjs';

test('le Worker choisit le pays dans le fichier local sans contacter le fournisseur', async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async () => { throw new Error('Aucun appel réseau externe autorisé'); };
  const env = { ASSETS: { fetch: async url => {
    calls.push(String(url));
    return Response.json(packRecord({ version: 2, streamingOptions: Object.fromEntries(['fr', 'ca'].map(country => [country, [{ type: 'subscription', service: { id: country, name: country }, link: `https://${country}.example/title` }]])) }));
  } } };
  try {
    for (const country of ['FR', 'CA']) {
      const request = new Request('https://example.com/api/regarder?source=/serie/exemple/regarder.json');
      request.cf = { country };
      const response = await onRequest({ request, env });
      assert.equal(response.headers.get('cache-control'), 'private, no-store');
      assert.deepEqual((await response.json()).services.map(s => s.id), [country.toLowerCase()]);
    }
    const plus = new Request('https://example.com/api/regarder?source=/serie/silo-apple-tv+/regarder.json');
    plus.cf = { country: 'FR' };
    // URLSearchParams interprète + comme une espace : la source est toujours encodée par le client.
    const plusURL = new URL(plus.url);
    plusURL.searchParams.set('source', '/serie/silo-apple-tv+/regarder.json');
    const plusRequest = new Request(plusURL);
    plusRequest.cf = { country: 'FR' };
    assert.equal((await onRequest({ request: plusRequest, env })).status, 200);
    const old = await onRequest({ request: new Request('https://example.com/api/regarder?type=tv&id=2388') });
    assert.deepEqual(await old.json(), { services: [] });
    const bad = await onRequest({ request: new Request('https://example.com/api/regarder?source=https://evil.example/file') });
    assert.equal(bad.status, 400);
    assert.deepEqual(calls, [...Array(2).fill('https://example.com/serie/exemple/regarder.json'), 'https://example.com/serie/silo-apple-tv+/regarder.json']);
  } finally { globalThis.fetch = original; }
});
