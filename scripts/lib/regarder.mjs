export function services(options) {
  const found = new Map();
  for (const item of options ?? []) {
    if (item.type !== 'subscription' || item.addon || !item.service?.id || !item.service?.name) continue;
    try {
      const url = new URL(item.link);
      if (url.protocol === 'https:' && !found.has(item.service.id)) found.set(item.service.id, { id: item.service.id, name: item.service.name, link: url.href });
    } catch { /* Offre invalide. */ }
  }
  return [...found.values()];
}

function netflixPath(link) {
  try {
    const url = new URL(link);
    if (url.protocol === 'https:' && /^(www\.)?netflix\.com$/.test(url.hostname)) {
      return url.pathname.match(/^\/(?:[a-z]{2}(?:-[a-z]{2})?\/)?(title|watch)\/(\d+)\/?$/i);
    }
  } catch { /* Lien invalide. */ }
}

export function netflixTitleForRecord(record) {
  const candidates = [
    ...(record.override?.services ?? []), ...(record.permanentServices ?? []), ...(record.offers ?? []),
    ...(record.version === 3 ? [] : Object.values(record.streamingOptions ?? {}).flat().flatMap(item => services([item]))),
  ];
  for (const service of candidates) {
    const path = netflixPath(service.link);
    if (path?.[1].toLowerCase() === 'title') return `https://www.netflix.com/title/${path[2]}`;
  }
}

export function normalizeNetflixService(service, titleLink) {
  const path = netflixPath(service.link);
  if (!path) return service;
  if (path[1].toLowerCase() === 'title') return { ...service, link: `https://www.netflix.com/title/${path[2]}` };
  // Un identifiant de lecture peut désigner un épisode : ne pas inventer sa fiche.
  return titleLink ? { ...service, link: titleLink } : null;
}

export function localizePermanentService(service, country) {
  if (!/^[a-z]{2}$/.test(country)) return service;
  try {
    const url = new URL(service.link);
    if (url.hostname === 'tv.apple.com' && /^\/[a-z]{2}(?:-[a-z]{2})?\//i.test(url.pathname)) {
      url.pathname = url.pathname.replace(/^\/[a-z]{2}(?:-[a-z]{2})?\//i, `/${country}/`);
      return { ...service, link: url.href };
    }
  } catch { /* Le filtrage des liens reste effectué avant l'affichage. */ }
  return service;
}

export function selectServices(record, country, seasons = []) {
  const resolve = options => record.version === 3
    ? (options ?? []).map(index => record.offers[index])
    : services(options);
  let result = resolve(record.streamingOptions?.[country]);
  const selected = seasons.map(String).filter(s => s !== '0');
  if (selected.length) {
    const lists = selected.map(s => resolve(record.seasons?.[s]?.[country]));
    result = (lists[0] ?? []).filter(s => lists.every(list => list.some(other => other.id === s.id)));
  }
  const permanent = (record.permanentServices ?? []).map(service => localizePermanentService(service, country));
  result = [...new Map([...result, ...permanent].map(s => [s.id, s])).values()];
  const override = record.override ?? {};
  if (Object.hasOwn(override, 'services')) result = override.services;
  const titleLink = netflixTitleForRecord(record);
  return result.map(service => ({ ...service, link: override.links?.[service.id] ?? service.link }))
    .map(service => normalizeNetflixService(service, titleLink))
    .filter(s => s && !(override.exclude ?? []).includes(s.id) && /^https:\/\//.test(s.link));
}
