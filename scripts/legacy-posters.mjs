import { existsSync, readFileSync, readdirSync, mkdirSync, writeFileSync, renameSync, unlinkSync } from 'node:fs';
import { join, dirname, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const posterRoot = join(root, '.cache/legacy-posters/assets/legacy');

function field(source, name) {
  return source.match(new RegExp(`^${name}:\\s*["']?([^\\n"']+)`, 'm'))?.[1].trim() || '';
}

function token() {
  if (process.env.HUGO_TMDB) return process.env.HUGO_TMDB;
  const envrc = join(root, '.envrc');
  if (!existsSync(envrc)) return '';
  return readFileSync(envrc, 'utf8').match(/^\s*(?:export\s+)?HUGO_TMDB\s*=\s*["']?([^\s"']+)/m)?.[1] || '';
}

async function tmdbGet(endpoint, parameters = {}) {
  const credential = token();
  if (!credential) throw new Error('HUGO_TMDB est requis pour retrouver un nouveau film dans TMDB.');
  const url = new URL(`https://api.themoviedb.org/3/${endpoint}`);
  url.searchParams.set('language', 'fr-FR');
  for (const [name, value] of Object.entries(parameters)) url.searchParams.set(name, value);
  const headers = { accept: 'application/json' };
  if (credential.startsWith('eyJ')) headers.Authorization = `Bearer ${credential}`;
  else url.searchParams.set('api_key', credential);
  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(`TMDB ${endpoint} : HTTP ${response.status}`);
  return response.json();
}

function words(value) {
  return value.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().match(/[a-z0-9]+/g) || [];
}

export function previousFilm(parts, slug, currentDate) {
  const target = words(slug);
  const candidates = parts.filter(part => part.poster_path && part.release_date && part.release_date < currentDate);
  const scored = candidates.map(part => {
    const title = words(part.title);
    const matches = title.filter(word => target.includes(word)).length;
    return { part, score: title.length ? matches / title.length + matches * 0.12 : 0 };
  }).sort((a, b) => b.score - a.score || b.part.release_date.localeCompare(a.part.release_date));
  if (!scored[0] || scored[0].score < 0.35) return null;
  if (scored[1] && scored[0].score - scored[1].score < 0.1) return null;
  return scored[0].part;
}

async function searchedFilm(slug, currentDate) {
  const fragments = slug.split('-');
  const director = fragments.at(-1);
  const query = fragments.slice(0, -1).join(' ');
  const results = await tmdbGet('search/movie', { query });
  const candidates = (results.results || []).filter(item => item.release_date && item.release_date < currentDate);
  const matching = [];
  for (const candidate of candidates) {
    const film = await tmdbGet(`movie/${candidate.id}`, { append_to_response: 'credits' });
    if (film.credits?.crew?.some(person => person.job === 'Director' && words(person.name).includes(director))) {
      matching.push(film);
    }
  }
  matching.sort((a, b) => a.release_date.localeCompare(b.release_date));
  return previousFilm(matching, slug, currentDate) || matching[0] || null;
}

export function bookQuery(slug) {
  const parts = slug.split('-');
  return { title: parts.slice(0, -1).join(' '), author: parts.at(-1) };
}

async function bookCover(slug) {
  const { title, author } = bookQuery(slug);
  const url = new URL('https://openlibrary.org/search.json');
  url.searchParams.set('title', title);
  url.searchParams.set('author', author);
  url.searchParams.set('limit', '10');
  url.searchParams.set('fields', 'key,title,cover_i,isbn');
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Open Library : HTTP ${response.status}`);
  const results = await response.json();
  const wanted = words(title);
  const match = (results.docs || []).filter(item => item.cover_i).map(item => {
    const found = words(item.title);
    return { item, score: wanted.filter(word => found.includes(word)).length / wanted.length };
  }).sort((a, b) => b.score - a.score)[0];
  if (!match || match.score < 0.75) return [];
  const covers = [`https://covers.openlibrary.org/b/id/${match.item.cover_i}-L.jpg`];
  const isbn = match.item.isbn?.find(value => /^\d{13}$/.test(value));
  if (isbn) {
    const bnf = new URL('https://openapi.bnf.fr/couverture/image/image/recupererImage');
    bnf.searchParams.set('EAN', isbn);
    bnf.searchParams.set('couverture', '1');
    bnf.searchParams.set('taille', 'originale');
    covers.push(bnf.href);
  }
  return covers;
}

export function jpegDimensions(image) {
  for (let offset = 2; offset < image.length - 9;) {
    if (image[offset] !== 0xff) break;
    const marker = image[offset + 1];
    const length = image.readUInt16BE(offset + 2);
    if ([0xc0, 0xc1, 0xc2, 0xc3].includes(marker)) {
      return { height: image.readUInt16BE(offset + 5), width: image.readUInt16BE(offset + 7) };
    }
    if (length < 2) break;
    offset += length + 2;
  }
  throw new Error('Dimensions JPEG introuvables');
}

async function loadImage(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Image ${url} : HTTP ${response.status}`);
  const image = Buffer.from(await response.arrayBuffer());
  if (image[0] !== 0xff || image[1] !== 0xd8) throw new Error(`Image non JPEG : ${url}`);
  return image;
}

function writeImage(image, destination) {
  mkdirSync(dirname(destination), { recursive: true });
  const temporary = `${destination}.tmp`;
  try {
    writeFileSync(temporary, image);
    renameSync(temporary, destination);
  } finally {
    if (existsSync(temporary)) unlinkSync(temporary);
  }
  console.log(`Image enregistrée : ${destination.slice(root.length)}`);
}

async function saveImage(url, destination) {
  writeImage(await loadImage(url), destination);
}

async function savePoster(posterPath, destination) {
  if (!/^\/[A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp)$/.test(posterPath)) {
    throw new Error(`Chemin d'affiche TMDB invalide : ${posterPath}`);
  }
  await saveImage(`https://image.tmdb.org/t/p/w780${posterPath}`, destination);
}

async function main() {
  const series = new Map();
  for (const folder of readdirSync(join(root, 'content/serie'), { withFileTypes: true })) {
    if (!folder.isDirectory()) continue;
    const directory = join(root, 'content/serie', folder.name);
    const article = join(directory, 'index.md');
    const metadataFile = join(directory, 'meta.json');
    if (!existsSync(article) || !existsSync(metadataFile)) continue;
    const id = field(readFileSync(article, 'utf8'), 'tmdb');
    if (!/^\d+$/.test(id)) continue;
    const metadata = JSON.parse(readFileSync(metadataFile, 'utf8'));
    const entry = series.get(id) || { count: 0, poster: '', date: '' };
    entry.count++;
    const date = field(readFileSync(article, 'utf8'), 'date');
    if (metadata.poster_path && date >= entry.date) {
      entry.poster = metadata.poster_path;
      entry.date = date;
    }
    series.set(id, entry);
  }
  for (const [id, seriesInfo] of series) {
    if (seriesInfo.count < 2 || !seriesInfo.poster) continue;
    const destination = join(posterRoot, 'tmdb', `${id}.jpg`);
    if (existsSync(destination)) continue;
    try { await savePoster(seriesInfo.poster, destination); } catch { /* Affiche indisponible. */ }
  }
  for (const category of ['serie', 'film', 'livre']) {
    for (const folder of readdirSync(join(root, 'content', category), { withFileTypes: true })) {
      if (!folder.isDirectory()) continue;
      const directory = join(root, 'content', category, folder.name);
      const article = join(directory, 'index.md');
      if (!existsSync(article)) continue;
      const source = readFileSync(article, 'utf8');
      const before = field(source, 'avant');
      if (!before.startsWith('https://voiretmanger.fr/')) continue;
      const metadataFile = join(directory, 'meta.json');
      if (!existsSync(metadataFile)) continue;
      const metadata = JSON.parse(readFileSync(metadataFile, 'utf8'));

      try {
      if (category === 'serie') {
        const id = field(source, 'tmdb');
        if (!/^\d+$/.test(id)) continue;
        const destination = join(posterRoot, 'serie', `${id}.jpg`);
        if (existsSync(destination)) continue;
        const season = metadata.seasons?.find(item => item.season_number === 1);
        if (!season?.poster_path) throw new Error(`Aucune affiche TMDB de saison 1 : ${article}`);
        await savePoster(season.poster_path, destination);
      } else if (category === 'film') {
        if (!field(source, 'sagas')) continue;
        const slug = basename(new URL(before).pathname.replace(/\/$/, ''));
        const destination = join(posterRoot, 'film', `${slug}.jpg`);
        if (existsSync(destination)) continue;
        let film = null;
        const collectionId = metadata.belongs_to_collection?.id;
        if (collectionId) {
          try {
            const collection = await tmdbGet(`collection/${collectionId}`);
            film = previousFilm(collection.parts || [], slug, metadata.release_date);
          } catch (error) {
            if (!/HTTP 404/.test(error.message)) throw error;
          }
        }
        if (!film) film = await searchedFilm(slug, metadata.release_date);
        if (!film) throw new Error(`Film précédent introuvable ou ambigu dans TMDB pour ${before}`);
        await savePoster(film.poster_path, destination);
      } else {
        if (!field(source, 'sagas')) continue;
        const slug = basename(new URL(before).pathname.replace(/\/$/, ''));
        const destination = join(posterRoot, 'livre', `${slug}.jpg`);
        if (existsSync(destination)) continue;
        const covers = await bookCover(slug);
        const images = await Promise.allSettled(covers.map(loadImage));
        const available = images.filter(result => result.status === 'fulfilled').map(result => result.value);
        if (available.length) {
          available.sort((a, b) => jpegDimensions(b).width - jpegDimensions(a).width);
          writeImage(available[0], destination);
        }
      }
      } catch { /* L'article reste publié sans cette affiche. */ }
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
