import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { buildDiscovery, parseCSV, familyName, releaseDate } from '../discovery.mjs';

test('chronologie des œuvres : sortie, première diffusion, année partielle et date absente', () => {
  assert.equal(releaseDate({ section: 'film', date: '2026-01-01', meta: { release_date: '2001-10-05' } }), '2001-10-05');
  assert.equal(releaseDate({ section: 'serie', meta: { first_air_date: '2010-02-03', last_air_date: '2025-06-07' } }), '2010-02-03');
  assert.equal(releaseDate({ section: 'livre', meta: { publishedDate: '1999' } }), '1999-01-01');
  assert.equal(releaseDate({ section: 'livre', meta: { publishedDate: '1999-04' } }), '1999-04-01');
  assert.equal(releaseDate({ section: 'film', date: '2026-01-01' }), '9999-12-31');
});

test('albums : identité du groupe, variantes de nom, seuil et date de sortie', () => {
  const album = (url, artistId, artistName, releaseDate) => ({ section: 'album', url, page: url, meta: { artistId, artistName, releaseDate } });
  const data = buildDiscovery([
    album('/a/', 42, 'Un Groupe', '2020-05-12T07:00:00Z'),
    album('/b/', 42, 'UN GROUPE', '1999-01-02T08:00:00Z'),
    album('/c/', 99, 'Un Groupe', '2000-01-01'),
    album('/d/', undefined, 'Autre Groupe', '2010-01-01'),
    album('/e/', undefined, 'Autre Groupe', '2012-01-01')
  ]);
  const group = data.people['artist:42'];
  assert.equal(group.workCount, 2);
  assert.equal(group.sortName, 'Un Groupe');
  assert.deepEqual(group.names, ['Un Groupe', 'UN GROUPE']);
  assert.equal(group.articles[0].releaseDate, '2020-05-12');
  assert.equal(group.articles[1].releaseDate, '1999-01-02');
  assert.ok(group.url.startsWith('/personnes/artistes/'));
  assert.equal(data.people['artist:99'], undefined);
  assert.equal(data.people['artist:autre groupe'].workCount, 2);
});

test('tri simple par nom de famille, noms composés et suffixes', () => {
  assert.equal(familyName('Wes Anderson'), 'Anderson');
  assert.equal(familyName('Robert Downey Jr.'), 'Downey');
  assert.equal(familyName('Ursula K. Le Guin'), 'Le Guin');
  assert.equal(familyName('Guillermo del Toro'), 'del Toro');
  const books = ['Zoe Anderson', 'Adam Zevin'].flatMap((name, i) => [0, 1].map(j => ({ section: 'livre', url: `/${i}/${j}/`, meta: { authors: [name] } })));
  const data = buildDiscovery(books);
  assert.deepEqual(data.orderedKeys.map(k => data.people[k].name), ['Zoe Anderson', 'Adam Zevin']);
});

test('films et séries : une identité pour plusieurs rôles, saisons dédoublonnées', () => {
  const actor = { id: 12, name: 'Une Personne', order: 0 };
  const series = (url, id) => ({ section: 'serie', url, page: url, meta: { id, created_by: [actor] }, hasSeasons: true, seasons: [{ aggregate_credits: { cast: [actor, actor] } }] });
  const film = { section: 'film', url: '/film/', page: 'film', cast: { cast: [actor], crew: [{ ...actor, job: 'Director' }] } };
  assert.deepEqual(buildDiscovery([series('/s1/', 100), series('/s2/', 100)]).people, {});
  const data = buildDiscovery([series('/s1/', 100), series('/s2/', 100), film]);
  const person = data.people['tmdb:12'];
  assert.equal(Object.keys(data.people).length, 1);
  assert.equal(person.workCount, 2);
  assert.equal(person.articles.length, 3);
  assert.equal(person.groups.length, 2);
  assert.deepEqual(new Set(person.roles), new Set(['actor', 'creator', 'director']));
  assert.ok(person.url.startsWith('/personnes/realisateurs/'));
  assert.deepEqual(data.byArticle['/s2/'], ['tmdb:12']);
});

test('distribution : crédits de saison prioritaires, plafonds identiques aux fiches', () => {
  const cast = Array.from({ length: 12 }, (_, i) => ({ id: i + 1, name: `Acteur ${i}`, order: i }));
  const films = [1, 2].map(i => ({ section: 'film', url: `/f${i}/`, cast: { cast } }));
  const series = [1, 2].map(i => ({ section: 'serie', url: `/s${i}/`, meta: { id: i }, hasSeasons: true, seasons: [{ aggregate_credits: { cast } }], cast: { cast: [{ id: 999, name: 'Hors saison' }] } }));
  const data = buildDiscovery([...films, ...series]);
  assert.equal(data.people['tmdb:8'].articles.length, 4);
  assert.equal(data.people['tmdb:10'].articles.length, 2);
  assert.equal(data.people['tmdb:11'], undefined);
  assert.equal(data.people['tmdb:999'], undefined);
});

test('CSV Hugo : virgules, guillemets, retours ligne et CRLF', () => {
  assert.deepEqual(parseCSV('path,title\r\na,"Un titre, avec ""citation""\net retour"\r\n'), [{ path: 'a', title: 'Un titre, avec "citation"\net retour' }]);
});

test('réalisateurs : identifiants stables, homonymes, doublons et seuil', () => {
  const film = (url, crew) => ({ section: 'film', url, page: url.slice(1), cast: { crew } });
  const director = (id, name = 'Même Nom') => ({ id, name, job: 'Director' });
  const data = buildDiscovery([
    film('/a/', [director(1), director(1), director(2)]),
    film('/b/', [director(1, 'Autre graphie'), { id: 3, name: 'Acteur', job: 'Actor' }]),
    film('/c/', [director(4)])
  ]);
  assert.deepEqual(Object.keys(data.people), ['tmdb:1']);
  assert.equal(data.people['tmdb:1'].articles.length, 2);
  assert.deepEqual(data.byArticle['/a/'], ['tmdb:1']);
});

test('URL lisibles pour tous les rôles et homonymes', () => {
  const credits = [{ id: 1, name: 'Matt Smith' }, { id: 2, name: 'Même Nom' }, { id: 3, name: 'Même Nom' }];
  const articles = [1, 2].flatMap(i => [
    { section: 'film', url: `/film/${i}/`, cast: { cast: credits, crew: [{ id: 4, name: 'Wes Anderson', job: 'Director' }] } },
    { section: 'serie', url: `/serie/${i}/`, meta: { id: i, created_by: [{ id: 5, name: 'Un Créateur' }] } },
    { section: 'livre', url: `/livre/${i}/`, meta: { authors: ['Yūsuke Kishi'] } },
    { section: 'album', url: `/album/${i}/`, meta: { artistId: 6, artistName: 'Un Groupe' } }
  ]);
  const { people } = buildDiscovery(articles);
  assert.equal(people['tmdb:1'].url, '/personnes/acteurs/matt-smith/');
  assert.equal(people['tmdb:4'].url, '/personnes/realisateurs/wes-anderson/');
  assert.equal(people['tmdb:5'].url, '/personnes/createurs/un-createur/');
  assert.equal(people['author:yūsuke kishi'].url, '/personnes/auteurs/yusuke-kishi/');
  assert.equal(people['artist:6'].url, '/personnes/artistes/un-groupe/');
  assert.equal(people['tmdb:2'].url, '/personnes/acteurs/meme-nom-2/');
  assert.equal(people['tmdb:3'].url, '/personnes/acteurs/meme-nom-3/');
  const reversed = buildDiscovery([...articles].reverse());
  for (const [key, person] of Object.entries(people)) assert.equal(reversed.people[key].url, person.url);
});

test('auteurs : espaces, coauteurs et collisions de slug', () => {
  const book = (url, authors) => ({ section: 'livre', url, page: url.slice(1), meta: { authors } });
  const data = buildDiscovery([
    book('/a/', ['Ursula Le Guin', 'René']),
    book('/b/', ['Ursula\u00a0Le Guin', 'René']),
    book('/c/', ['Rene']), book('/d/', ['Rene'])
  ]);
  assert.equal(data.people['author:ursula le guin'].articles.length, 2);
  assert.ok(data.people['author:ursula le guin'].names.includes('Ursula Le Guin'));
  assert.notEqual(data.people['author:rené'].url, data.people['author:rene'].url);
  assert.deepEqual(buildDiscovery([{ section: 'film', url: '/sans-meta/' }]).people, {});
});

test('génération réelle : brouillons, dates futures, expiration et suppression des pages obsolètes', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'blog-discovery-'));
  try {
    writeFileSync(path.join(root, 'hugo.toml'), 'baseURL = "https://example.test/"\n');
    const book = (slug, author, extra = {}) => {
      const dir = path.join(root, 'content/livre', slug);
      mkdirSync(dir, { recursive: true });
      writeFileSync(path.join(dir, 'index.md'), JSON.stringify({ title: slug, date: '2020-01-01', ...extra }) + '\nTexte');
      writeFileSync(path.join(dir, 'meta.json'), JSON.stringify({ authors: [author] }));
    };
    book('one', 'Publié'); book('two', 'Publié', { url: '/adresse-personnalisee/' });
    book('only', 'Masqué'); book('draft', 'Masqué', { draft: true });
    book('future', 'Masqué', { date: '2099-01-01' });
    book('expired', 'Masqué', { expiryDate: '2021-01-01' });
    const run = () => execFileSync(process.execPath, [fileURLToPath(new URL('../discovery.mjs', import.meta.url))], { cwd: root });
    run();
    const data = JSON.parse(readFileSync(path.join(root, '.cache/discovery/data/discovery.json')));
    assert.deepEqual(Object.keys(data.people), ['author:publié']);
    assert.ok(data.byArticle['/adresse-personnalisee/']);
    const generated = path.join(root, `.cache/discovery/content/pages/discovery-author-${data.people['author:publié'].suffix}/_index.md`);
    assert.ok(existsSync(generated));
    book('two', 'Publié', { draft: true }); run();
    assert.equal(existsSync(generated), false);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('Échap : résultat → champ ; champ → retour ; arrivée directe → accueil', () => {
  const callbacks = [];
  let back = 0, home = 0, focus = 0;
  const result = {};
  const input = { focus() { focus++; document.activeElement = this; } };
  const results = { contains: element => element === result, querySelectorAll: () => [result] };
  const document = { activeElement: result, referrer: 'https://blog.test/film/', querySelector: () => results, addEventListener: (_, fn) => callbacks.push(fn) };
  const context = { document, URL, location: { origin: 'https://blog.test', assign: () => home++ }, history: { back: () => back++ }, searchInput: input, searchResults: results };
  const backScript = readFileSync(new URL('../../themes/nicolasfurno/layouts/partials/back.html', import.meta.url), 'utf8').replace(/<\/?script>/g, '');
  const search = readFileSync(new URL('../../themes/nicolasfurno/static/js/search.js', import.meta.url), 'utf8');
  const start = search.indexOf('document.addEventListener("keydown", (event) => {');
  const end = search.indexOf('\n});', start) + 4;
  vm.runInNewContext(backScript, context);
  vm.runInNewContext(search.slice(start, end), context);
  const press = () => { const event = { key: 'Escape', defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } }; callbacks.forEach(fn => fn(event)); };
  press(); assert.equal(focus, 1); assert.equal(back, 0);
  press(); assert.equal(back, 1);
  document.referrer = ''; press(); assert.equal(home, 1);
});


test('recherche : fiches avant les critiques, filtres et tri chronologique conservés', () => {
  const source = readFileSync(new URL('../../themes/nicolasfurno/static/js/search.js', import.meta.url), 'utf8');
  const render = source.slice(source.indexOf('function renderResults() {'), source.indexOf('function updateFilters() {'));
  const element = () => ({ children: [], append(child) { this.children.push(child); } });
  const results = [];
  const result = (title, relevance, kind, category, date) => ({ data: { url: '/' + title, meta: { title, kind } }, relevance, category, date });
  const context = {
    document: { createElement: element },
    searchResults: { replaceChildren(...items) { results.splice(0, results.length, ...items); } },
    currentResults: [result('Critique', 0, undefined, 'film', 200), result('Personne', 1, 'person', undefined, 0), result('Autre critique', 2, undefined, 'film', 100)],
    activeCategory: null, sortMode: 'relevance', currentTerm: 'Personne'
  };
  vm.createContext(context);
  vm.runInContext(source.slice(source.indexOf('function personSearchPriority'), source.indexOf('async function searchPagefind')) + render, context);
  const titles = () => results.map(item => item.children[0].textContent);
  vm.runInContext('renderResults()', context);
  assert.deepEqual(titles(), ['Personne', 'Critique', 'Autre critique']);
  context.activeCategory = 'film';
  vm.runInContext('renderResults()', context);
  assert.deepEqual(titles(), ['Critique', 'Autre critique']);
  context.sortMode = 'oldest';
  vm.runInContext('renderResults()', context);
  assert.deepEqual(titles().filter(title => !/^\d{4}$/.test(title)), ['Autre critique', 'Critique']);
});


test('recherche de personne : accents, ordre des noms, préfixes et correspondance exacte', () => {
  const source = readFileSync(new URL('../../themes/nicolasfurno/static/js/search.js', import.meta.url), 'utf8');
  const context = vm.createContext({});
  vm.runInContext(source.slice(source.indexOf('function personSearchPriority'), source.indexOf('async function searchPagefind')), context);
  const score = (title, query) => context.personSearchPriority({ meta: { kind: 'person', title } }, query);
  assert.equal(score('Wes Anderson', 'Wes Anderson'), 2);
  assert.equal(score('Wes Anderson', 'Anderson Wes'), 1);
  assert.equal(score('Yūsuke Kishi', 'yusuke kishi'), 2);
  assert.equal(score('Matt Smith', 'matt smi'), 1);
  assert.equal(score('Peter Gabriel', 'Gabriel'), 1);
  assert.equal(score('Owen Wilson', 'Wes Anderson'), 0);
});


test('réseaux TV : identités séparées, séries dédoublonnées et seuil commun', () => {
  const network = { id: 213, name: 'Netflix' };
  const series = (url, id) => ({ section: 'serie', url, meta: { id, networks: [network, network], created_by: [{ id: 213, name: 'Une Personne' }], first_air_date: '2000-01-01' } });
  assert.equal(buildDiscovery([series('/s1/', 1), series('/s2/', 1)]).people['network:213'], undefined);
  const data = buildDiscovery([series('/s1/', 1), series('/s2/', 1), series('/other/', 2)]);
  const profile = data.people['network:213'];
  assert.equal(profile.url, '/reseaux/netflix/');
  assert.equal(profile.external, 'https://www.themoviedb.org/network/213');
  assert.equal(profile.workCount, 2);
  assert.equal(profile.articles.length, 3);
  assert.equal(profile.groups.length, 2);
  assert.equal(profile.sortName, 'Netflix');
  assert.ok(data.people['tmdb:213']);
  assert.ok(data.byArticle['/s2/'].includes('network:213'));
});
