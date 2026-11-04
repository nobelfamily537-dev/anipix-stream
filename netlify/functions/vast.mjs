/**
 * VAST proxy — fetches the ad tag server-side so the browser does not hit CORS.
 * Only allowlisted ad hosts can be fetched (no open proxy).
 *
 *   GET /.netlify/functions/vast            -> default AniPix tag
 *   GET /.netlify/functions/vast?u=<tag>    -> any allowlisted tag
 */

const DEFAULT_TAG = 'https://youradexchange.com/video/select.php?r=12400306';

const ALLOWED_HOSTS = [
  'youradexchange.com',
  'www.youradexchange.com',
];

function allowed(raw) {
  try {
    const u = new URL(raw);
    return u.protocol === 'https:' && ALLOWED_HOSTS.includes(u.hostname);
  } catch (e) {
    return false;
  }
}

export default async (req) => {
  const url = new URL(req.url);
  const tag = url.searchParams.get('u') || DEFAULT_TAG;

  if (!allowed(tag)) {
    return new Response('Tag host not allowed', { status: 403 });
  }

  try {
    const res = await fetch(tag, {
      headers: {
        'user-agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        accept: 'application/xml,text/xml,*/*',
      },
    });
    const body = await res.text();
    return new Response(body, {
      status: 200,
      headers: {
        'content-type': 'application/xml; charset=utf-8',
        'cache-control': 'no-store',
        'access-control-allow-origin': '*',
      },
    });
  } catch (err) {
    return new Response(
      '<?xml version="1.0" encoding="UTF-8"?><VAST version="3.0"></VAST>',
      { status: 200, headers: { 'content-type': 'application/xml', 'access-control-allow-origin': '*' } }
    );
  }
};
