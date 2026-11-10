import test from 'node:test';
import assert from 'node:assert/strict';
import { compact, selectServices } from '../regarder.mjs';
const offer = (id, link = `https://${id}.example/title`) => ({ type: 'subscription', service: { id, name: id }, link });
test('conserve tous les pays et Netflix original hors France', () => {
  const options = { us: [offer('netflix'), offer('hulu')], fr: [offer('prime')], ca: [] };
  const data = compact({ streamingOptions: options, seasons: [{ title: 'Season 1', streamingOptions: { us: [offer('hulu')] } }] }, { networks: [{ name: 'Netflix' }] });
  assert.deepEqual(Object.keys(data.streamingOptions), ['us', 'fr']);
  assert.deepEqual(data.offers.map(s => s.id), ['hulu', 'prime']);
  assert.deepEqual(selectServices(data, 'ca').map(s => s.id), ['netflix']);
  assert.deepEqual(selectServices(data, 'fr').map(s => s.id), ['prime', 'netflix']);
  assert.deepEqual(selectServices(data, 'us').map(s => s.id), ['hulu', 'netflix']);
  assert.deepEqual(selectServices(data, 'fr', [1]).map(s => s.id), ['netflix']);
  assert.deepEqual(selectServices(data, 'us', [1]).map(s => s.id), ['hulu', 'netflix']);
});
test('respecte les saisons, les exclusions et le remplacement manuel vide', () => {
  const record = { streamingOptions: { fr: [offer('a'), offer('b')] }, seasons: { 1: { fr: [offer('a'), offer('b')] }, 2: { fr: [offer('b')] } } };
  assert.deepEqual(selectServices(record, 'fr', [1, 2]).map(s => s.id), ['b']);
  assert.deepEqual(selectServices(record, 'fr', [3]), []);
  assert.deepEqual(selectServices({ ...record, override: { exclude: ['a'] } }, 'fr', [0]).map(s => s.id), ['b']);
  assert.deepEqual(selectServices({ ...record, override: { services: [] } }, 'fr'), []);
});
test('rejette achat, supplément et liens non HTTPS', () => {
  const result = compact({ streamingOptions: { fr: [offer('ok'), offer('bad', 'javascript:alert(1)'), { ...offer('buy'), type: 'buy' }, { ...offer('addon'), addon: {} }] } }, {});
  assert.deepEqual(selectServices(result, 'fr').map(s => s.id), ['ok']);
});

test('une série originale ne garde que son lien permanent, sans variantes régionales ou épisodes', () => {
  const data = compact({ streamingOptions: { fr: [offer('apple')], es: [offer('apple', 'https://tv.apple.com/es/show/example/id')] }, seasons: [{ title: 'Season 1', streamingOptions: { fr: [offer('apple', 'https://tv.apple.com/fr/episode/example/id')] } }, { title: 'Season 2', streamingOptions: { fr: [] } }] }, { networks: [{ name: 'Apple TV' }] });
  assert.equal(data.offers, undefined);
  assert.equal(data.streamingOptions, undefined);
  assert.equal(data.seasons, undefined);
  assert.deepEqual(selectServices(data, 'fr', [1]), data.permanentServices);
  assert.deepEqual(selectServices(data, 'ca', [2]), data.permanentServices);
});

test('le lien permanent Apple TV suit le pays du visiteur, pas le premier pays de l’API', () => {
  const link = 'https://tv.apple.com/es/show/silo/umc.cmc.example';
  const record = { version: 3, permanentServices: [{ id: 'apple', name: 'Apple TV', link }] };
  assert.equal(selectServices(record, 'fr')[0].link, link.replace('/es/', '/fr/'));
  assert.equal(selectServices(record, 'gb', [3])[0].link, link.replace('/es/', '/gb/'));
  assert.equal(record.permanentServices[0].link, link);
  assert.equal(selectServices({ ...record, override: { services: [{ id: 'apple', name: 'Apple TV', link }] } }, 'fr')[0].link, link);
});

test('Netflix : les saisons renvoient à la fiche de la série, pas à celle de l’épisode', () => {
  const data = compact({ streamingOptions: { fr: [offer('netflix', 'https://www.netflix.com/title/80021955')] }, seasons: [{ title: 'Season 6', streamingOptions: { fr: [offer('netflix', 'https://www.netflix.com/watch/81341715?trackId=123')] } }] }, {});
  assert.equal(selectServices(data, 'fr', [6])[0].link, 'https://www.netflix.com/title/80021955');
  assert.equal(data.offers.length, 1);
  // Le Worker corrige aussi les fichiers déjà publiés dans l’ancien format.
  const legacy = { version: 3, offers: [{ id: 'netflix', name: 'Netflix', link: 'https://www.netflix.com/title/80021955' }, { id: 'netflix', name: 'Netflix', link: 'https://www.netflix.com/watch/81341715' }], seasons: { 6: { fr: [1] } } };
  assert.equal(selectServices(legacy, 'fr', [6])[0].link, 'https://www.netflix.com/title/80021955');
  assert.deepEqual(selectServices({ version: 3, offers: [legacy.offers[1]], streamingOptions: { fr: [0] } }, 'fr'), []);
});
