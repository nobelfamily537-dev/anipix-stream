/**
 * AniPix Stream — Cloudflare Worker
 *   /api/vast     -> VAST ad tag proxy (server side, no CORS)
 *   /api/library  -> GET published library / POST publish to GitHub
 *   everything else -> static assets from ./dist
 */

const DEFAULT_TAG = 'https://youradexchange.com/video/select.php?r=12404346';
const ALLOWED_HOSTS = ['youradexchange.com', 'www.youradexchange.com'];

/* SHA-256 of the publish key. Only the hash lives in the repo, never the key. */
const PUBLISH_KEY_SHA256 = '30c38ee712884292eac60b027d59e55d58214a57f32678ff715473a6967941ef';

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

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

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
    const supplied = request.headers.get('x-publish-key') || '';
    const suppliedHash = supplied ? await sha256Hex(supplied) : '';
    const matchesEnv = env.PUBLISH_KEY && supplied === env.PUBLISH_KEY;
    const matchesHash = suppliedHash && suppliedHash === PUBLISH_KEY_SHA256;
    if (!matchesEnv && !matchesHash) {
      return json(JSON.stringify({
        ok: false,
        error: env.PUBLISH_KEY ? 'Wrong publish key.' : 'Wrong publish key (check it in the admin panel).',
      }), 401);
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

    /* snapshot the library before this publish so we can diff what is new */
    let prevLib = {};
    try {
      const prevRes = await fetch(
        `https://raw.githubusercontent.com/${REPO}/${BRANCH}/library.json?t=${Date.now()}`,
        { headers: { 'user-agent': 'anipix-publish', 'cache-control': 'no-cache' } });
      if (prevRes.ok) prevLib = await prevRes.json();
    } catch (e) { prevLib = {}; }

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
      /* tell the Telegram channel about anything newly added */
      try {
        let next = {};
        try { next = JSON.parse(body); } catch (e) { next = {}; }
        const prevIds = new Set(((prevLib.episodes) || []).map((e) => e.id));
        const fresh = ((next.episodes) || []).filter((e) => e && e.id && !prevIds.has(e.id));
        if (fresh.length) await notifyTelegram(env, next, fresh);
      } catch (e) { /* never block a publish */ }

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

/* ---------------- Telegram channel poster ---------------- */
const SITE = 'https://anipix-stream.animeloverclipedits.workers.dev';
const TG_CHAT_DEFAULT = '@Anipix_stream';
const APP_URL = 'https://anipix.itch.io/anipix-stream';
const GROUP_URL = 'https://t.me/lovelyanime2025';

async function tg(env, method, payload) {
  if (!env.TELEGRAM_TOKEN) return false;
  try {
    const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_TOKEN}/${method}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return res.ok;
  } catch (e) {
    return false;
  }
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function isHttp(url) {
  return typeof url === 'string' && /^https?:\/\//i.test(url);
}

function captionFor(playlist, eps) {
  const nums = eps.map((e) => e.n).sort((a, b) => a - b);
  const range = nums.length === 1 ? `EPISODE ${nums[0]}` : `EPISODE ${nums[0]}-${nums[nums.length - 1]}`;
  const season = eps[0].season || 1;
  const audio = (playlist.audio && playlist.audio.length ? playlist.audio : ['Hindi']).join(' • ');
  const genre = (playlist.genres || []).slice(0, 6).join(' • ');
  const title = playlist.title || 'New anime';
  const quality = [...new Set(eps.flatMap((e) => (e.sources || []).map((x) => x.q)).filter(Boolean))].join(' • ');

  const lines = [
    `🔥✨ ${range} ADDED! ✨🔥`,
    '',
    `🎬 <b>Title:</b> ${esc(title)}`,
    season > 1 ? `📺 <b>Season:</b> ${season}` : '',
    genre ? `🎭 <b>Genre:</b> ${esc(genre)}` : '',
    `🔊 <b>Audio:</b> ${esc(audio)}`,
    quality ? `📹 <b>Quality:</b> ${esc(quality)}` : '',
    '',
    `▶️ <b>Watch now on AniPix Stream</b>`,
  ].filter(Boolean);
  return lines.join('\n');
}

async function notifyTelegram(env, lib, newEps) {
  if (!env.TELEGRAM_TOKEN || !newEps.length) return;
  const chat = env.TELEGRAM_CHAT || TG_CHAT_DEFAULT;

  const byPlaylist = {};
  for (const e of newEps) {
    const pid = e.playlistId;
    if (!pid) continue;
    (byPlaylist[pid] = byPlaylist[pid] || []).push(e);
  }

  for (const [pid, eps] of Object.entries(byPlaylist)) {
    const playlist = (lib.playlists || []).find((p) => p.id === pid) || {};
    const url = `${SITE}/#/detail/${pid}`;
    const caption = captionFor(playlist, eps);

    const buttons = {
      inline_keyboard: [
        [{ text: '🍿 Watch & Download', url }],
        [{ text: '▶️ Watch Online', url }],
        [{ text: '📱 Open in AniPix Stream App', url: APP_URL }],
        [{ text: '💬 Join Our Group', url: GROUP_URL }],
      ],
    };

    const photo = isHttp(playlist.banner) ? playlist.banner
                : (isHttp(playlist.thumb) ? playlist.thumb : '');
    let sent = false;
    if (photo) {
      sent = await tg(env, 'sendPhoto', {
        chat_id: chat,
        photo,
        caption,
        parse_mode: 'HTML',
        reply_markup: buttons,
      });
    }
    if (!sent) {
      await tg(env, 'sendMessage', {
        chat_id: chat,
        text: caption,
        parse_mode: 'HTML',
        reply_markup: buttons,
        disable_web_page_preview: false,
      });
    }
  }
}

/* ---------------- media upload (thumbnails / banners) ---------------- */
async function handleMedia(request, env) {
  if (request.method !== 'POST') return json(JSON.stringify({ ok: false, error: 'POST only' }), 405);

  const supplied = request.headers.get('x-publish-key') || '';
  const suppliedHash = supplied ? await sha256Hex(supplied) : '';
  if (!(env.PUBLISH_KEY && supplied === env.PUBLISH_KEY) && suppliedHash !== PUBLISH_KEY_SHA256) {
    return json(JSON.stringify({ ok: false, error: 'Wrong publish key.' }), 401);
  }
  if (!env.GITHUB_TOKEN) return json(JSON.stringify({ ok: false, error: 'GITHUB_TOKEN missing' }), 500);

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json(JSON.stringify({ ok: false, error: 'Body must be JSON' }), 400);
  }

  const name = String(body.name || 'image.jpg').replace(/[^a-zA-Z0-9._-]/g, '_');
  const data = String(body.data || '');
  if (!data) return json(JSON.stringify({ ok: false, error: 'data (base64) required' }), 400);

  const path = `media/${Date.now()}-${name}`;
  const headers = {
    authorization: `Bearer ${env.GITHUB_TOKEN}`,
    accept: 'application/vnd.github+json',
    'user-agent': 'anipix-media',
    'content-type': 'application/json',
  };

  const put = await fetch(`https://api.github.com/repos/${REPO}/contents/${path}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify({ message: `media: ${name}`, content: data, branch: BRANCH }),
  });

  if (!put.ok) {
    const detail = await put.text();
    return json(JSON.stringify({ ok: false, error: `GitHub ${put.status}: ${detail.slice(0, 140)}` }), 502);
  }

  return json(JSON.stringify({
    ok: true,
    url: `https://raw.githubusercontent.com/${REPO}/${BRANCH}/${path}`,
  }));
}

/* ---------------- view counter (stored in the repo, no KV needed) ---------------- */
const VIEWS_PATH = 'views.json';
let viewCache = {};          // in-memory counters for this isolate
let viewsFetchedAt = 0;
let lastFlushAt = 0;
const FLUSH_EVERY_MS = 3 * 60 * 1000;

async function readViews(env) {
  if (Date.now() - viewsFetchedAt < 60 * 1000) return viewCache;
  try {
    const res = await fetch(`https://raw.githubusercontent.com/${REPO}/${BRANCH}/${VIEWS_PATH}?t=${Date.now()}`);
    if (res.ok) {
      const j = await res.json();
      viewCache = (j && typeof j === 'object') ? j : {};
    }
  } catch (e) { /* ignore */ }
  viewsFetchedAt = Date.now();
  return viewCache;
}

async function flushViews(env) {
  if (!env.GITHUB_TOKEN) return;
  const headers = {
    authorization: `Bearer ${env.GITHUB_TOKEN}`,
    accept: 'application/vnd.github+json',
    'user-agent': 'anipix-views',
    'content-type': 'application/json',
  };
  const api = `https://api.github.com/repos/${REPO}/contents/${VIEWS_PATH}`;
  let sha;
  try {
    const cur = await fetch(api, { headers });
    if (cur.ok) {
      const meta = await cur.json();
      sha = meta.sha;
    }
  } catch (e) { /* ignore */ }

  const body = JSON.stringify(viewCache);
  try {
    await fetch(api, {
      method: 'PUT',
      headers,
      body: JSON.stringify({
        message: 'views: update counters',
        content: toBase64(body),
        branch: BRANCH,
        ...(sha ? { sha } : {}),
      }),
    });
    lastFlushAt = Date.now();
  } catch (e) { /* ignore */ }
}

async function handleView(request, env) {
  await readViews(env);

  if (request.method === 'POST') {
    let body;
    try { body = await request.json(); } catch (e) { body = null; }
    const id = body && String(body.id || '');
    if (!id) return json(JSON.stringify({ ok: false, error: 'id required' }), 400);

    viewCache[id] = (parseInt(viewCache[id] || '0', 10) || 0) + 1;

    /* write to the repo at most every few minutes */
    if (Date.now() - lastFlushAt > FLUSH_EVERY_MS) {
      lastFlushAt = Date.now();
      await flushViews(env);
    }
    return json(JSON.stringify({ ok: true, id, views: viewCache[id] }));
  }

  return json(JSON.stringify({ ok: true, views: viewCache }));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/api/health') {
      return json(JSON.stringify({
        ok: true,
        publishKey: !!(env.PUBLISH_KEY || PUBLISH_KEY_SHA256),
        githubToken: !!env.GITHUB_TOKEN,
        version: 'v1.6',
      }));
    }
    if (url.pathname === '/api/test-tg') {
      const key = url.searchParams.get('key') || '';
      const kh = key ? await sha256Hex(key) : '';
      const okKey = (env.PUBLISH_KEY && key === env.PUBLISH_KEY) || kh === PUBLISH_KEY_SHA256;
      if (!okKey) return json(JSON.stringify({ ok: false, error: 'wrong key' }), 401);
      if (!env.TELEGRAM_TOKEN) return json(JSON.stringify({ ok: false, error: 'TELEGRAM_TOKEN missing' }));

      const chat = env.TELEGRAM_CHAT || TG_CHAT_DEFAULT;
      const wantPlaylist = url.searchParams.get('playlist');

      let payload;
      let method = 'sendMessage';

      if (wantPlaylist) {
        let lib = {};
        try {
          const r = await fetch(`https://raw.githubusercontent.com/${REPO}/${BRANCH}/library.json?t=${Date.now()}`);
          if (r.ok) lib = await r.json();
        } catch (e) { lib = {}; }

        const playlists = lib.playlists || [];
        const eps = lib.episodes || [];
        const pl = playlists.find((p) => p.id === wantPlaylist)
                || playlists.find((p) => String(p.title || '').toLowerCase().includes(String(wantPlaylist).toLowerCase()));

        if (!pl) return json(JSON.stringify({ ok: false, error: 'playlist not found', playlists: playlists.map((p) => p.title) }));

        const mine = eps.filter((e) => e.playlistId === pl.id).sort((a, b) => (a.season - b.season) || (a.n - b.n));
        if (!mine.length) return json(JSON.stringify({ ok: false, error: 'this playlist has no episodes' }));

        const seasons = [...new Set(mine.map((e) => e.season))];
        const nums = mine.map((e) => String(e.n).padStart(2, '0'));
        const audio = (pl.audio && pl.audio.length ? pl.audio : ['Hindi']).join(' • ');
        const genre = (pl.genres || []).slice(0, 6).join(' • ');
        const quality = [...new Set(mine.flatMap((e) => (e.sources || []).map((x) => x.q)).filter(Boolean))].join(' • ');
        const url2 = `${SITE}/#/detail/${pl.id}`;

        const caption = [
          `🎬 <b>${esc(pl.title)}</b>`,
          '',
          `📺 <b>Season:</b> ${seasons.join(', ')}`,
          `🎞 <b>Episodes:</b> ${nums.join(', ')}  <i>(${mine.length} total)</i>`,
          genre ? `🎭 <b>Genre:</b> ${esc(genre)}` : '',
          `🔊 <b>Audio:</b> ${esc(audio)}`,
          quality ? `📹 <b>Quality:</b> ${esc(quality)}` : '',
          '',
          '▶️ <b>Watch now on AniPix Stream</b>',
        ].filter(Boolean).join('\n');

        const kb = { inline_keyboard: [
          [{ text: '🍿 Watch & Download', url: url2 }],
          [{ text: '▶️ Watch Online', url: url2 }],
          [{ text: '📱 Open in AniPix Stream App', url: APP_URL }],
          [{ text: '💬 Join Our Group', url: GROUP_URL }],
        ] };

        const photo = isHttp(pl.banner) ? pl.banner : (isHttp(pl.thumb) ? pl.thumb : '');
        if (photo) {
          method = 'sendPhoto';
          payload = { chat_id: chat, photo, caption, parse_mode: 'HTML', reply_markup: kb };
        } else {
          payload = { chat_id: chat, text: caption, parse_mode: 'HTML', reply_markup: kb };
        }
      } else {
        payload = {
          chat_id: chat,
          text: '✅ <b>AniPix Stream</b>\n\nBot connected. Naya episode publish karte hi post yahan aayega.',
          parse_mode: 'HTML',
          reply_markup: { inline_keyboard: [
            [{ text: '▶️ Open AniPix Stream', url: SITE }],
            [{ text: '📱 Open in AniPix Stream App', url: APP_URL }],
            [{ text: '💬 Join Our Group', url: GROUP_URL }],
          ] },
        };
      }

      const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_TOKEN}/${method}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const body = await res.text();
      return json(JSON.stringify({ ok: res.ok, method, chat, telegram: body.slice(0, 400) }));
    }
    if (url.pathname === '/api/media') return handleMedia(request, env);
    if (url.pathname === '/api/view') return handleView(request, env);
    if (url.pathname === '/api/vast') return handleVast(request);
    if (url.pathname === '/api/library') return handleLibrary(request, env);

    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response('Not found', { status: 404 });
  },
};
