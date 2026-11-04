/**
 * Cloudflare Pages Function — VAST proxy.
 * Fetches the ad tag server-side so the browser never hits CORS.
 * Only the allowlisted ad host can be fetched (not an open proxy).
 */

const DEFAULT_TAG = 'https://youradexchange.com/video/select.php?r=12404346';
const ALLOWED_HOSTS = ['youradexchange.com', 'www.youradexchange.com'];

const XML_HEADERS = {
  'content-type': 'application/xml; charset=utf-8',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
};

const EMPTY_VAST = '<?xml version="1.0" encoding="UTF-8"?><VAST version="3.0"></VAST>';

export async function onRequest(context) {
  const url = new URL(context.request.url);
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
    return new Response(EMPTY_VAST, { headers: XML_HEADERS });
  }
}
