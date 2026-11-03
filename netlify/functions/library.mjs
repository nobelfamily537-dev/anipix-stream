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

/** Mirrors the library into the GitHub repo so the app can read it from there. */
async function commitToGitHub(body) {
  const token = process.env.GITHUB_TOKEN;
  if (!token) return 'skipped (GITHUB_TOKEN not set)';
  const repo = process.env.GITHUB_REPO || 'nobelfamily537-dev/anipix-stream';
  const url = `https://api.github.com/repos/${repo}/contents/library.json`;
  const headers = {
    authorization: `Bearer ${token}`,
    accept: 'application/vnd.github+json',
    'user-agent': 'anipix-publish',
    'content-type': 'application/json',
  };
  try {
    let sha;
    const current = await fetch(url, { headers });
    if (current.ok) {
      const meta = await current.json();
      sha = meta.sha;
    }
    const put = await fetch(url, {
      method: 'PUT',
      headers,
      body: JSON.stringify({
        message: 'Publish library.json from the admin panel',
        content: Buffer.from(body, 'utf8').toString('base64'),
        ...(sha ? { sha } : {}),
      }),
    });
    return put.ok ? 'committed' : `github ${put.status}`;
  } catch (err) {
    return 'github error: ' + err.message;
  }
}

export default async (req) => {
  const store = getStore(STORE);

  /* ---------------- read the published library ---------------- */
  if (req.method === 'GET' || req.method === 'HEAD') {
    try {
      const stored = await store.get(BLOB_KEY);
      if (stored) return json(stored);
    } catch (err) {
      /* fall through */
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
    } catch (err) {
      return json(JSON.stringify({ ok: false, error: 'Could not save: ' + err.message }), 500);
    }
    const github = await commitToGitHub(body);
    return json(JSON.stringify({ ok: true, bytes: body.length, github }));
  }

  return json(JSON.stringify({ ok: false, error: 'Method not allowed' }), 405);
};
