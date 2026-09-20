import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Hugo decides which articles are published, including draft/future/expiry rules.
// Its CSV also preserves explicit article URLs and front matter slugs.
export function parseCSV(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"') {
      if (quoted && text[i + 1] === '"') { field += '"'; i++; }
      else quoted = !quoted;
    } else if (!quoted && (ch === ',' || ch === '\n')) {
      row.push(field); field = '';
      if (ch === '\n') { rows.push(row); row = []; }
    } else if (ch !== '\r' || quoted) field += ch;
  }
  if (field || row.length) rows.push([...row, field]);
  const headers = rows.shift() || [];
  return rows.filter(r => r.length === headers.length).map(r => Object.fromEntries(headers.map((h, i) => [h, r[i]])));
}

const normalize = name => name.normalize('NFKC').trim().replace(/\s+/gu, ' ').toLocaleLowerCase('fr');
const slug = name => name.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'personne';

export function familyName(name) {
  const words = name.normalize('NFKC').trim().split(/\s+/u);
  if (/^(jr\.?|sr\.?|ii|iii|iv)$/i.test(words.at(-1))) words.pop();
  let start = words.length - 1;
  while (start > 1 && /^(de|del|della|di|da|dos|du|van|von|der|den|la|le)$/i.test(words[start - 1])) start--;
  return words.slice(start).join(' ').replace(/,$/, '');
}

export function releaseDate(article) {
  const value = article.section === 'film' ? article.meta?.release_date
    : article.section === 'serie' ? article.meta?.first_air_date
    : article.section === 'album' ? article.meta?.releaseDate?.slice(0, 10)
    : article.meta?.publishedDate;
  const match = String(value || '').match(/^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$/);
  // Partial dates (especially books) sort at the beginning of the known year/month.
  // Missing dates sort last, without substituting the review's publication date.
  return match && match[1] !== '0000'
    ? `${match[1]}-${match[2] || '01'}-${match[3] || '01'}` : '9999-12-31';
}

export function buildDiscovery(articles) {
  const people = new Map();
  const tmdb = (person, role) => ({ key: `tmdb:${person.id}`, name: person.name, role, external: `https://www.themoviedb.org/person/${person.id}`, suffix: String(person.id) });
  const valid = person => person.id && person.name;
  for (const article of articles) {
    const credits = [];
    if (article.section === 'film') {
      credits.push(...(article.cast?.crew || []).filter(p => p.job === 'Director' && valid(p)).map(p => tmdb(p, 'director')));
      credits.push(...(article.cast?.cast || []).slice(0, 8).filter(valid).map(p => tmdb(p, 'actor')));
    } else if (article.section === 'serie') {
      credits.push(...(article.meta?.networks || []).filter(valid).map(network => ({
        key: `network:${network.id}`, name: network.name, role: 'network',
        external: `https://www.themoviedb.org/network/${network.id}`, suffix: String(network.id)
      })));
      credits.push(...(article.meta?.created_by || []).filter(valid).map(p => tmdb(p, 'creator')));
      // Match the actors actually displayed by the series template, including
      // the selected seasons rather than the cast of the whole series.
      const cast = article.seasons?.length && article.hasSeasons
        ? article.seasons.flatMap(s => s.aggregate_credits?.cast || [])
        : article.cast?.cast || [];
      const seen = new Set();
      const actors = [...cast].sort((a, b) => (a.order || 0) - (b.order || 0)).filter(p => {
        if (!valid(p) || seen.has(p.id)) return false;
        seen.add(p.id); return true;
      }).slice(0, 10);
      credits.push(...actors.map(p => tmdb(p, 'actor')));
    } else if (article.section === 'livre') {
      for (const raw of (article.meta?.authors || []).filter(n => typeof n === 'string' && n.trim())) {
        const name = raw.normalize('NFKC').trim().replace(/\s+/gu, ' ');
        const key = `author:${normalize(name)}`;
        credits.push({ key, name, originalName: raw, role: 'author', suffix: createHash('sha256').update(key).digest('hex').slice(0, 10) });
      }
    } else if (article.section === 'album' && article.meta?.artistName?.trim()) {
      const name = article.meta.artistName.trim();
      const key = article.meta.artistId ? `artist:${article.meta.artistId}` : `artist:${normalize(name)}`;
      credits.push({ key, name, originalName: article.meta.artistName, role: 'artist',
        suffix: article.meta.artistId ? String(article.meta.artistId) : createHash('sha256').update(key).digest('hex').slice(0, 10) });
    }
    for (const credit of credits) {
      if (!people.has(credit.key)) people.set(credit.key, { ...credit, roles: [], names: [], articles: [] });
      const person = people.get(credit.key);
      if (!person.roles.includes(credit.role)) person.roles.push(credit.role);
      if (!person.names.includes(credit.originalName || credit.name)) person.names.push(credit.originalName || credit.name);
      if (!person.articles.some(a => a.url === article.url)) person.articles.push({
        url: article.url, page: article.page, releaseDate: releaseDate(article),
        work: article.section === 'serie' && article.meta?.id ? `serie:${article.meta.id}` : article.url,
        seriesId: article.section === 'serie' ? article.meta?.id : undefined
      });
    }
  }
  const paths = { director: 'realisateurs', author: 'auteurs', actor: 'acteurs', creator: 'createurs', artist: 'artistes' };
  const profiles = [...people.values()].filter(p => new Set(p.articles.map(a => a.work)).size >= 2).map(p => {
    // Prefer the director/author section when a person has several roles.
    const role = ['director', 'author', 'actor', 'creator', 'artist', 'network'].find(r => p.roles.includes(r));
    return { ...p, role, workCount: new Set(p.articles.map(a => a.work)).size,
      sortName: ['artist', 'network'].includes(role) ? p.name : familyName(p.name),
      groups: [...new Set(p.articles.map(a => a.work))].map(work => p.articles.filter(a => a.work === work)),
      url: role === 'network' ? `/reseaux/${slug(p.name)}/` : `/personnes/${paths[role]}/${slug(p.name)}/` };
  }).sort((a, b) => a.sortName.localeCompare(b.sortName, 'fr', { sensitivity: 'base' }) || a.name.localeCompare(b.name, 'fr'));
  const urlCounts = new Map();
  for (const person of profiles) urlCounts.set(person.url, (urlCounts.get(person.url) || 0) + 1);
  for (const person of profiles) {
    if (urlCounts.get(person.url) > 1) person.url = `${person.url.slice(0, -1)}-${person.suffix}/`;
  }
  const byArticle = {};
  for (const person of profiles) {
    for (const article of person.articles) (byArticle[article.url] ||= []).push(person.key);
  }
  return { people: Object.fromEntries(profiles.map(p => [p.key, p])), orderedKeys: profiles.map(p => p.key), byArticle };
}

function generate(root) {
  const readJSON = file => existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
  const published = parseCSV(execFileSync('hugo', ['list', 'published'], { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 }));
  const articles = published.filter(p => p.kind === 'page' && ['film', 'livre', 'serie', 'album'].includes(p.section)).map(p => {
    const file = path.resolve(root, p.path);
    return { section: p.section, url: new URL(p.permalink).pathname,
      page: path.relative(path.join(root, 'content'), file).replace(/\/index\.md$/, '').replaceAll(path.sep, '/'),
      hasSeasons: /^saison:\s*\[(?!0\s*\])/m.test(readFileSync(file, 'utf8')),
      seasons: readJSON(path.join(path.dirname(file), 'seasons.json')),
      meta: readJSON(path.join(path.dirname(file), 'meta.json')), cast: readJSON(path.join(path.dirname(file), 'cast.json')) };
  });
  const data = buildDiscovery(articles);
  // Keep mounted directories in place so Hugo does not lose its file watchers.
  const output = path.join(root, '.cache/discovery');
  mkdirSync(path.join(output, 'content/pages'), { recursive: true });
  mkdirSync(path.join(output, 'data'), { recursive: true });
  const generated = new Set();
  const writeGenerated = (file, content) => {
    generated.add(file);
    if (!existsSync(file) || readFileSync(file, 'utf8') !== content) writeFileSync(file, content);
  };
  const writePage = (name, metadata) => {
    const file = path.join(output, `content/pages/${name}.md`);
    mkdirSync(path.dirname(file), { recursive: true });
    writeGenerated(file, `${JSON.stringify({ type: 'pages', ...metadata }, null, 2)}\n`);
  };
  writePage('discovery', { title: 'Personnes', url: '/personnes/', layout: 'people' });
  for (const person of Object.values(data.people)) {
    writePage(`discovery-${person.role}-${person.suffix}/_index`, { title: person.name, url: person.url, outputs: ['HTML'], layout: 'person', personKey: person.key });
  }
  writeGenerated(path.join(output, 'data/discovery.json'), JSON.stringify(data));
  const removeStaleFiles = directory => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) removeStaleFiles(file);
      else if (!generated.has(file)) rmSync(file);
    }
  };
  removeStaleFiles(output);
  console.log(`${Object.keys(data.people).length} pages de personnes générées.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) generate(process.cwd());
