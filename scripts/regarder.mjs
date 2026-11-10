import { existsSync, readFileSync, readdirSync, writeFileSync, renameSync, mkdirSync, appendFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = (file, fallback = {}) => existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : fallback;

import { services } from './lib/regarder.mjs';
export { services, selectServices } from './lib/regarder.mjs';

// Chaque lien distinct est stocké une fois ; pays et saisons ne gardent que ses indices.
export function packRecord(record) {
  if (!record.streamingOptions && record.version !== 3) return record;
  const offers = [];
  const indices = new Map();
  const permanent = new Set((record.permanentServices ?? []).map(offer => offer.id));
  const resolve = items => record.version === 3
    ? (items ?? []).map(index => record.offers[index])
    : services(items);
  const packOptions = options => Object.fromEntries(Object.entries(options ?? {}).map(([country, items]) => [country,
    resolve(items).filter(offer => !permanent.has(offer.id)).map(offer => {
      const key = JSON.stringify(offer);
      if (!indices.has(key)) { indices.set(key, offers.length); offers.push(offer); }
      return indices.get(key);
    }),
  ]).filter(([, items]) => items.length));
  const streamingOptions = packOptions(record.streamingOptions);
  const seasons = Object.fromEntries(Object.entries(record.seasons ?? {}).map(([season, options]) => [season, packOptions(options)])
    .filter(([, options]) => Object.keys(options).length));
  const packed = { ...record, version: 3, offers, streamingOptions, seasons };
  for (const key of ['offers', 'streamingOptions', 'seasons', 'permanentServices']) {
    if (!Object.keys(packed[key] ?? {}).length) delete packed[key];
  }
  return packed;
}

export function compact(data, metadata, now = new Date()) {
  const networks = (metadata.networks ?? []).map(n => n.name.toLowerCase());
  const originals = [];
  if (networks.includes('netflix')) originals.push('netflix');
  if (networks.some(n => /^apple tv(?:\+)?$/.test(n))) originals.push('apple');
  return packRecord({
    version: 2,
    checkedAt: now.toISOString(),
    streamingOptions: data.streamingOptions,
    permanentServices: services(Object.values(data.streamingOptions).flat()).filter(s => originals.includes(s.id)),
    seasons: Object.fromEntries((data.seasons ?? []).map(s => [s.title.replace(/^Season /, ''), s.streamingOptions ?? {}])),
  });
}

function save(file, record) {
  writeFileSync(`${file}.tmp`, `${JSON.stringify(packRecord(record))}\n`);
  renameSync(`${file}.tmp`, file);
}

export async function collect({ root, key, limit = 20, reserve = 150, articlePath = null,
  fetchImpl = globalThis.fetch, now = Date.now(), log = console.log,
  quotaFile = join(root, '.cache/regarder-quota.json') }) {
  const works = new Map();
  for (const [category, type] of [['film', 'movie'], ['serie', 'tv']]) {
    for (const folder of readdirSync(join(root, 'content', category), { withFileTypes: true })) {
      const path = join(root, 'content', category, folder.name, 'meta.json');
      if (!folder.isDirectory() || !existsSync(path)) continue;
      const metadata = read(path);
      if (!Number.isSafeInteger(metadata.id) || metadata.id <= 0) continue;
      const id = `${type}/${metadata.id}`;
      const article = readFileSync(join(root, 'content', category, folder.name, 'index.md'), 'utf8');
      const date = Date.parse(article.match(/^date:\s*["']?([^\n"']+)/m)?.[1] ?? '') || 0;
      if (!articlePath && (date > now || /^draft:\s*true\s*$/m.test(article))) continue;
      if (!works.has(id)) works.set(id, { metadata, files: [], date });
      works.get(id).date = Math.max(works.get(id).date, date);
      works.get(id).files.push(join(root, 'content', category, folder.name, 'regarder.json'));
    }
  }
  let calls = 0;
  let reason = 'Catalogue à jour';
  let quota = read(quotaFile, null);
  if (!quota || !Number.isFinite(Date.parse(quota.resetAt)) || Date.parse(quota.resetAt) <= now) quota = null;
  for (const [id, { metadata, files }] of [...works].sort((a, b) => b[1].date - a[1].date)) {
    if (calls >= limit) { reason = `Plafond de ${limit} appels atteint`; break; }
    if (articlePath && !files.some(file => resolve(file, '..') === articlePath)) continue;
    const locals = files.map(file => ({ file, record: read(file) }));
    const automatic = locals.filter(({ record }) => !Object.hasOwn(record.override ?? {}, 'services'));
    if (!automatic.length) continue;
    const previous = automatic.map(({ record }) => record).filter(record => [2, 3].includes(record.version) && record.checkedAt)
      .sort((a, b) => Date.parse(b.checkedAt) - Date.parse(a.checkedAt))[0];
    if (previous && now - Date.parse(previous.checkedAt) < 180 * 86400000) {
      for (const { file, record } of automatic) {
        if (!record.checkedAt || record.checkedAt !== previous.checkedAt) save(file, { ...previous, override: record.override });
      }
      continue;
    }
    if (quota && quota.granted - quota.used <= reserve) {
      reason = `Réserve de ${reserve} appels atteinte ; reprise après le ${quota.resetAt}`;
      break;
    }
    calls++;
    const response = await fetchImpl(`https://api.movieofthenight.com/v4/shows/${encodeURIComponent(id)}?output_language=en`, {
      headers: { 'X-API-Key': key }, signal: AbortSignal.timeout(30000),
    });
    const granted = response.headers.get('x-quota-granted');
    const used = response.headers.get('x-quota-used');
    const resetAt = response.headers.get('x-quota-reset');
    if (granted === null || used === null || !/^\d+$/.test(granted) || !/^\d+$/.test(used) || !Number.isFinite(Date.parse(resetAt))) {
      await response.body?.cancel();
      throw new Error(`${id} : en-têtes de quota absents ou invalides ; collecte arrêtée par précaution.`);
    }
    quota = { granted: Number(granted), used: Number(used), resetAt, checkedAt: new Date(now).toISOString() };
    mkdirSync(dirname(quotaFile), { recursive: true });
    writeFileSync(`${quotaFile}.tmp`, JSON.stringify(quota) + '\n');
    renameSync(`${quotaFile}.tmp`, quotaFile);
    if (response.status === 429 || response.status === 402) {
      await response.body?.cancel();
      throw new Error(`${id} : HTTP ${response.status}, collecte arrêtée sans nouvelle tentative.`);
    }
    if (response.status === 404) {
      for (const { file, record } of automatic) save(file, { version: 2, checkedAt: new Date(now).toISOString(), streamingOptions: {}, seasons: {}, permanentServices: previous?.permanentServices ?? [], override: record.override });
      log(`${id} : absent du fournisseur`);
      continue;
    }
    if (!response.ok) throw new Error(`${id} : HTTP ${response.status}. Import arrêté ; les données précédentes sont conservées.`);
    const data = await response.json();
    if (data.tmdbId !== id || !data.streamingOptions || typeof data.streamingOptions !== 'object') throw new Error(`${id} : réponse inattendue.`);
    const entry = compact(data, metadata, new Date(now));
    // Une disparition du catalogue ne supprime pas un lien original déjà connu.
    const permanent = [...new Map([...(previous?.permanentServices ?? []), ...(entry.permanentServices ?? [])].map(s => [s.id, s])).values()];
    entry.permanentServices = permanent;
    for (const { file, record } of automatic) save(file, { ...entry, override: record.override });
    log(`${id} : ${Object.keys(data.streamingOptions).length} pays enregistrés`);
  }
  log(`${calls} appel(s). ${reason}.`);
  if (quota) log(`Quota : ${quota.used}/${quota.granted}, ${quota.granted - quota.used} appels restants ; remise à zéro ${quota.resetAt}.`);
  return { calls, reason, quota };
}

async function main() {
  const args = process.argv.slice(2);
  if (args.some(arg => !/^--(?:limit|reserve)=\d+$/.test(arg) && !arg.startsWith('--article='))) {
    throw new Error('Usage : node scripts/regarder.mjs [--limit=20] [--reserve=150] [--article=CHEMIN_DOSSIER]');
  }
  const argument = name => args.find(arg => arg.startsWith(`--${name}=`))?.slice(name.length + 3);
  const articlePath = argument('article') ? resolve(argument('article')) : null;
  const limit = Number(argument('limit') ?? 20);
  // La réserve sert aux créations explicites, qui peuvent donc l'utiliser.
  const reserve = Number(argument('reserve') ?? (articlePath ? 0 : 150));
  if (!Number.isSafeInteger(limit) || limit < 1 || !Number.isSafeInteger(reserve) || reserve < 0) throw new Error('Plafond ou réserve invalide.');
  let key = process.env.MOTN_API_KEY;
  if (!key && existsSync(join(root, '.envrc'))) key = readFileSync(join(root, '.envrc'), 'utf8').match(/^\s*(?:export\s+)?MOTN_API_KEY\s*=\s*["']?([^\s"']+)/m)?.[1];
  if (!key) throw new Error('Ajouter MOTN_API_KEY dans .envrc ou dans l’environnement.');
  const result = await collect({ root, key, limit, reserve, articlePath });
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `Collecte Regarder : ${result.calls} appel(s). ${result.reason}.\n` +
    (result.quota ? `Quota : ${result.quota.used}/${result.quota.granted} utilisé ; remise à zéro ${result.quota.resetAt}.\n` : ''));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch(error => { console.error(error.message); process.exitCode = 1; });
