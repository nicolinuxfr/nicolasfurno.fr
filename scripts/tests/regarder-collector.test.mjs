import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { collect } from '../regarder.mjs';

const now = Date.parse('2026-11-10T08:00:00Z');
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'regarder-collector-'));
  for (const category of ['film', 'serie']) mkdirSync(join(root, 'content', category), { recursive: true });
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const article = (slug, id, date, options = {}) => {
    const dir = join(root, 'content', options.category ?? 'film', slug);
    mkdirSync(dir);
    writeFileSync(join(dir, 'index.md'), `---\ndate: ${date}\n${options.draft ? 'draft: true\n' : ''}---\n`);
    writeFileSync(join(dir, 'meta.json'), JSON.stringify({ id }));
    if (options.record) writeFileSync(join(dir, 'regarder.json'), JSON.stringify(options.record));
    return dir;
  };
  return { root, article, run: options => collect({ root, key: 'test', now, log: () => {}, ...options }) };
}
function reply(id, used, { status = 200, resetAt = '2026-12-01T00:00:00Z', headers = true } = {}) {
  return Response.json({ tmdbId: id, streamingOptions: { fr: [{ type: 'subscription', service: { id: 'netflix', name: 'Netflix' }, link: 'https://www.netflix.com/title/123' }] } }, {
    status,
    headers: headers ? { 'x-quota-granted': '1000', 'x-quota-used': String(used), 'x-quota-reset': resetAt } : {},
  });
}
const identity = url => decodeURIComponent(new URL(url).pathname.split('/').at(-1));

test('priorité aux publications récentes, déduplication, exclusion des brouillons et futures publications', async t => {
  const { article, run } = fixture(t);
  article('ancien', 1, '2020-01-01');
  article('recent', 2, '2026-11-09');
  article('doublon', 2, '2024-01-01');
  article('intermediaire', 3, '2025-01-01');
  article('brouillon', 4, '2026-11-10', { draft: true });
  article('futur', 5, '2027-01-01');
  const calls = [];
  const result = await run({ limit: 2, fetchImpl: async url => { const id = identity(url); calls.push(id); return reply(id, calls.length); } });
  assert.deepEqual(calls, ['movie/2', 'movie/3']);
  assert.equal(result.calls, 2);
});

test('arrêt à la réserve, zéro appel au passage suivant, reprise après remise à zéro', async t => {
  const { article, run } = fixture(t);
  article('ancien', 1, '2020-01-01');
  article('recent', 2, '2026-11-09');
  let calls = 0;
  const fetchImpl = async url => { calls++; return reply(identity(url), 850); };
  assert.equal((await run({ fetchImpl })).calls, 1);
  assert.equal((await run({ fetchImpl })).calls, 0);
  assert.equal(calls, 1);
  assert.equal((await run({ now: Date.parse('2026-12-02'), fetchImpl: async url => reply(identity(url), 1, { resetAt: '2027-01-01T00:00:00Z' }) })).calls, 1);
});

test('les données fraîches et les corrections manuelles sont réutilisées sans appel', async t => {
  const { article, run } = fixture(t);
  const record = { version: 3, checkedAt: new Date(now).toISOString(), permanentServices: [{ id: 'netflix', name: 'Netflix', link: 'https://www.netflix.com/title/123' }] };
  article('recent', 1, '2026-11-09', { record });
  const copy = article('autre-saison', 1, '2024-01-01', { record: { override: { exclude: ['netflix'] } } });
  article('manuel', 2, '2026-11-08', { record: { override: { services: [] } } });
  const result = await run({ fetchImpl: () => { throw new Error('Appel inattendu'); } });
  assert.equal(result.calls, 0);
  const saved = JSON.parse(readFileSync(join(copy, 'regarder.json')));
  assert.equal(saved.checkedAt, record.checkedAt);
  assert.deepEqual(saved.override, { exclude: ['netflix'] });
});

test('une création explicite peut utiliser la réserve ; les réponses 404 sont mémorisées', async t => {
  const { article, run } = fixture(t);
  const articlePath = article('nouveau', 1, '2026-11-10', { draft: true });
  const fetchImpl = async url => reply(identity(url), 850, { status: 404 });
  await run({ articlePath, fetchImpl });
  // Le 404 ne provoque aucun nouvel appel avant expiration.
  assert.equal((await run({ articlePath, reserve: 0, fetchImpl: () => { throw new Error('404 non mémorisé'); } })).calls, 0);
  const other = article('nouveau-2', 2, '2026-11-10', { draft: true });
  assert.equal((await run({ articlePath: other, reserve: 0, fetchImpl: async url => reply(identity(url), 851) })).calls, 1);
});

test('en-têtes manquants : arrêt immédiat, aucun fichier trompeur enregistré', async t => {
  const { article, run } = fixture(t);
  const dir = article('recent', 1, '2026-11-09');
  await assert.rejects(run({ fetchImpl: async url => reply(identity(url), 1, { headers: false }) }), /quota absents/);
  assert.equal(existsSync(join(dir, 'regarder.json')), false);
});

test('une erreur conserve les succès précédents et ne relance pas le fournisseur', async t => {
  const { article, run } = fixture(t);
  article('ancien', 1, '2020-01-01');
  const newest = article('recent', 2, '2026-11-09');
  let calls = 0;
  await assert.rejects(run({ fetchImpl: async url => reply(identity(url), ++calls, { status: calls === 1 ? 200 : 429 }) }), /429/);
  assert.equal(calls, 2);
  assert.equal(existsSync(join(newest, 'regarder.json')), true);
});
