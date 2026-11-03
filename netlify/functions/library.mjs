import { getStore } from '@netlify/blobs';

const BLOB_KEY = 'library.json';
const STORE = 'anipix';

const json = (body, status = 200) =>
  new Response(body, {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
    },
  });

export default async (req) => {
  const store = getStore(STORE);

  /* ---------------- read the published library ---------------- */
  if (req.method === 'GET' || req.method === 'HEAD') {
    try {
      const stored = await store.get(BLOB_KEY);
      if (stored) return json(stored);
    } catch (err) {
      /* fall through to the static file */
    }
    try {
      const fallback = await fetch(new URL('/library.json', req.url));
      if (fallback.ok) return json(await fallback.text());
    } catch (err) {
      /* ignore */
    }
    return json(JSON.stringify({ version: 0, playlists: [], episodes: [], seasons: [] }));
  }

  /* ---------------- publish a new library ---------------- */
  if (req.method === 'POST') {
    const expected = process.env.PUBLISH_KEY;
    if (!expected) {
      return json(JSON.stringify({ ok: false, error: 'PUBLISH_KEY is not set in Netlify environment variables.' }), 500);
    }
    if ((req.headers.get('x-publish-key') || '') !== expected) {
      return json(JSON.stringify({ ok: false, error: 'Wrong publish key.' }), 401);
    }
    let body;
    try {
      body = await req.text();
      JSON.parse(body);
    } catch (err) {
      return json(JSON.stringify({ ok: false, error: 'Body is not valid JSON.' }), 400);
    }
    try {
      await store.set(BLOB_KEY, body);
      return json(JSON.stringify({ ok: true, bytes: body.length }));
    } catch (err) {
      return json(JSON.stringify({ ok: false, error: 'Could not save: ' + err.message }), 500);
    }
  }

  return json(JSON.stringify({ ok: false, error: 'Method not allowed' }), 405);
};
