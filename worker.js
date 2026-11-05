/**
 * AniPix Stream — Cloudflare Worker
 *   /api/vast     -> VAST ad tag proxy (server side, no CORS)
 *   /api/library  -> GET published library / POST publish to GitHub
 *   everything else -> static assets from ./dist
 */

const DEFAULT_TAG = 'https://youradexchange.com/video/select.php?r=12404346';
const ALLOWED_HOSTS = ['youradexchange.com', 'www.youradexchange.com'];

const REPO = 'nobelfamily537-dev/anipix-stream';
const BRANCH = 'main';
const RAW_URL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/library.json`;
const API_URL = `https://api.github.com/repos/${REPO}/contents/library.json`;

const XML_HEADERS = {
  'content-type': 'application/xml; charset=utf-8',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
};

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

/* ---------------- VAST proxy ---------------- */
async function handleVast(request) {
  const url = new URL(request.url);
  const tag = url.searchParams.get('u') || DEFAULT_TAG;
  try {
    const target = new URL(tag);
    if (target.protocol !== 'https:' || !ALLOWED_HOSTS.includes(target.hostname)) {
      return new Response('Tag host not allowed', { status: 403 });
    }
    const res = await fetch(tag, {
      headers: {
        'user-agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        accept: 'application/xml,text/xml,*/*',
      },
    });
    return new Response(await res.text(), { headers: XML_HEADERS });
  } catch (err) {
    return new Response('<?xml version="1.0" encoding="UTF-8"?><VAST version="3.0"></VAST>', {
      headers: XML_HEADERS,
    });
  }
}

/* ---------------- library ---------------- */
async function handleLibrary(request, env) {
  if (request.method === 'GET' || request.method === 'HEAD') {
    try {
      const res = await fetch(RAW_URL, { cf: { cacheTtl: 0 } });
      if (res.ok) return json(await res.text());
    } catch (err) {
      /* ignore */
    }
    return json(JSON.stringify({ version: 0, playlists: [], episodes: [], seasons: [] }));
  }

  if (request.method === 'POST') {
    if (!env.PUBLISH_KEY) {
      return json(JSON.stringify({
        ok: false,
        error: 'PUBLISH_KEY is missing on this Worker deployment'
          + ' (GITHUB_TOKEN ' + (env.GITHUB_TOKEN ? 'present' : 'missing') + ').'
          + ' Add it under Settings -> Variables and Secrets, then redeploy.',
      }), 500);
    }
    if ((request.headers.get('x-publish-key') || '') !== env.PUBLISH_KEY) {
      return json(JSON.stringify({ ok: false, error: 'Wrong publish key.' }), 401);
    }
    if (!env.GITHUB_TOKEN) {
      return json(JSON.stringify({ ok: false, error: 'GITHUB_TOKEN is not set in Worker secrets.' }), 500);
    }

    let body;
    try {
      body = await request.text();
      JSON.parse(body);
    } catch (err) {
      return json(JSON.stringify({ ok: false, error: 'Body is not valid JSON.' }), 400);
    }

    const headers = {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
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

  return json(JSON.stringify({ ok: false, error: 'Method not allowed' }), 405);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/api/health') {
      return json(JSON.stringify({
        ok: true,
        publishKey: !!env.PUBLISH_KEY,
        githubToken: !!env.GITHUB_TOKEN,
        version: 'v1.6',
      }));
    }
    if (url.pathname === '/api/vast') return handleVast(request);
    if (url.pathname === '/api/library') return handleLibrary(request, env);

    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response('Not found', { status: 404 });
  },
};
