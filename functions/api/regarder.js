import { selectServices } from '../../scripts/lib/regarder.mjs';

export async function onRequest({ request, env }) {
  const empty = () => Response.json({ services: [] }, { headers: { 'Cache-Control': 'private, no-store' } });
  if (request.method !== 'GET') return new Response(null, { status: 405 });
  const url = new URL(request.url);
  const source = url.searchParams.get('source');
  // Les anciennes pages sans source locale ne doivent plus appeler le fournisseur.
  if (!source) return empty();
  let decoded;
  try { decoded = decodeURIComponent(source); } catch { return new Response(null, { status: 400 }); }
  if (!/^\/(film|serie)\/[\p{L}\p{N}][\p{L}\p{N}+_.~-]*\/regarder\.json$/u.test(decoded)) return new Response(null, { status: 400 });
  const seasons = url.searchParams.get('saisons') || '';
  if (seasons && !/^\d{1,3}(,\d{1,3}){0,19}$/.test(seasons)) return new Response(null, { status: 400 });
  const country = request.cf?.country?.toLowerCase();
  if (!/^[a-z]{2}$/.test(country ?? '') || ['xx', 't1'].includes(country)) return empty();
  try {
    const response = await env.ASSETS.fetch(new URL(source, url.origin));
    if (!response.ok) return empty();
    const record = await response.json();
    // Les anciens imports partiels ne sont pas présentés comme des offres mondiales.
    if (![2, 3].includes(record.version) && !record.override) return empty();
    return Response.json({ services: selectServices(record, country, seasons ? seasons.split(',') : []) }, {
      headers: { 'Cache-Control': 'private, no-store' },
    });
  } catch { return empty(); }
}
