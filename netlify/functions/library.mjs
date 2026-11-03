/**
 * AniPix publish endpoint — keeps the library in the GitHub repo.
 * No npm dependencies (Node 18+ global fetch only), so nothing can fail to bundle.
 *
 *   GET  /.netlify/functions/library   -> returns the repo's library.json
 *   POST /.netlify/functions/library   -> commits library.json to the repo
 *
 * Environment variables (Netlify -> Project configuration -> Environment variables):
 *   PUBLISH_KEY   shared secret the admin panel sends
 *   GITHUB_TOKEN  fine-grained token with Contents: Read and write on the repo
 *   GITHUB_REPO   optional, defaults to nobelfamily537-dev/anipix-stream
 */

const REPO = process.env.GITHUB_REPO || 'nobelfamily537-dev/anipix-stream';
const BRANCH = process.env.GITHUB_BRANCH || 'main';
const RAW_URL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/library.json`;
const API_URL = `https://api.github.com/repos/${REPO}/contents/library.json`;

const json = (body, status = 200) =>
  new Response(body, {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
    },
  });

function ghHeaders(token) {
  return {
    authorization: `Bearer ${token}`,
    accept: 'application/vnd.github+json',
    'user-agent': 'anipix-publish',
    'content-type': 'application/json',
  };
}

export default async (req) => {
  /* ---------------- read ---------------- */
  if (req.method === 'GET' || req.method === 'HEAD') {
    try {
      const res = await fetch(RAW_URL, { headers: { 'cache-control': 'no-cache' } });
      if (res.ok) return json(await res.text());
      return json(JSON.stringify({ version: 0, playlists: [], episodes: [], seasons: [], error: `raw ${res.status}` }), 200);
    } catch (err) {
      return json(JSON.stringify({ version: 0, playlists: [], episodes: [], seasons: [], error: err.message }), 200);
    }
  }

  /* ---------------- publish ---------------- */
  if (req.method === 'POST') {
    const expected = process.env.PUBLISH_KEY;
    if (!expected) return json(JSON.stringify({ ok: false, error: 'PUBLISH_KEY is not set in Netlify environment variables.' }), 500);
    if ((req.headers.get('x-publish-key') || '') !== expected) return json(JSON.stringify({ ok: false, error: 'Wrong publish key.' }), 401);

    const token = process.env.GITHUB_TOKEN;
    if (!token) {
      return json(JSON.stringify({
        ok: false,
        error: 'GITHUB_TOKEN is not set. Add it in Netlify environment variables (Contents: Read and write).',
      }), 500);
    }

    let body;
    try {
      body = await req.text();
      JSON.parse(body);
    } catch (err) {
      return json(JSON.stringify({ ok: false, error: 'Body is not valid JSON.' }), 400);
    }

    try {
      let sha;
      const current = await fetch(API_URL, { headers: ghHeaders(token) });
      if (current.ok) {
        const meta = await current.json();
        sha = meta.sha;
      }
      const put = await fetch(API_URL, {
        method: 'PUT',
        headers: ghHeaders(token),
        body: JSON.stringify({
          message: 'Publish library from the admin panel',
          content: Buffer.from(body, 'utf8').toString('base64'),
          branch: BRANCH,
          ...(sha ? { sha } : {}),
        }),
      });
      if (!put.ok) {
        const detail = await put.text();
        return json(JSON.stringify({ ok: false, error: `GitHub ${put.status}: ${detail.slice(0, 180)}` }), 502);
      }
      const out = await put.json();
      return json(JSON.stringify({
        ok: true,
        bytes: body.length,
        commit: out.commit && out.commit.sha ? out.commit.sha.slice(0, 7) : null,
      }));
    } catch (err) {
      return json(JSON.stringify({ ok: false, error: 'GitHub request failed: ' + err.message }), 502);
    }
  }

  return json(JSON.stringify({ ok: false, error: 'Method not allowed' }), 405);
};
