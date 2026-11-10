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
  result = [...new Map([...result, ...(record.permanentServices ?? [])].map(s => [s.id, s])).values()];
  const override = record.override ?? {};
  if (Object.hasOwn(override, 'services')) result = override.services;
  return result.filter(s => !(override.exclude ?? []).includes(s.id) && /^https:\/\//.test(s.link));
}
