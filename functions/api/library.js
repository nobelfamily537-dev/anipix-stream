/**
 * Cloudflare Pages Function — library read + publish.
 *
 *   GET  /api/library  -> returns library.json from the GitHub repo
 *   POST /api/library  -> commits library.json to the repo
 *
 * Environment variables (Cloudflare Pages -> Settings -> Environment variables):
 *   PUBLISH_KEY   shared secret the admin panel sends
 *   GITHUB_TOKEN  fine-grained token, Contents: Read and write
 */

const REPO = 'nobelfamily537-dev/anipix-stream';
const BRANCH = 'main';
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

function toBase64(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

export async function onRequestGet() {
  try {
    const res = await fetch(RAW_URL, { cf: { cacheTtl: 0 } });
    if (res.ok) return json(await res.text());
  } catch (err) {
    /* fall through */
  }
  return json(JSON.stringify({ version: 0, playlists: [], episodes: [], seasons: [] }));
}

export async function onRequestPost({ request, env }) {
  const expected = env.PUBLISH_KEY;
  if (!expected) return json(JSON.stringify({ ok: false, error: 'PUBLISH_KEY is not set in Cloudflare environment variables.' }), 500);
  if ((request.headers.get('x-publish-key') || '') !== expected) return json(JSON.stringify({ ok: false, error: 'Wrong publish key.' }), 401);

  const token = env.GITHUB_TOKEN;
  if (!token) return json(JSON.stringify({ ok: false, error: 'GITHUB_TOKEN is not set in Cloudflare environment variables.' }), 500);

  let body;
  try {
    body = await request.text();
    JSON.parse(body);
  } catch (err) {
    return json(JSON.stringify({ ok: false, error: 'Body is not valid JSON.' }), 400);
  }

  const headers = {
    authorization: `Bearer ${token}`,
    accept: 'application/vnd.github+json',
    'user-agent': 'anipix-publish',
    'content-type': 'application/json',
  };

  try {
    let sha;
    const current = await fetch(API_URL, { headers });
    if (current.ok) {
      const meta = await current.json();
      sha = meta.sha;
    }
    const put = await fetch(API_URL, {
      method: 'PUT',
      headers,
      body: JSON.stringify({
        message: 'Publish library from the admin panel',
        content: toBase64(body),
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
