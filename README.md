# AniPix Stream

Anime streaming site + Android app. Content lives in this repo.

## Hosting
- **Cloudflare Workers** (main): `anipix-stream.animeloverclipedits.workers.dev`
  - static files from `./dist`
  - `/api/library` - read + publish library.json
  - `/api/vast` - VAST ad tag proxy
- Netlify: legacy host, deploys are credit limited.

## Worker setup
Build command:
```
mkdir -p dist && cp index.html robots.txt sw.js dist/ && (cp library.json dist/ 2>/dev/null || true)
```
Deploy command: `npx wrangler deploy`

Variables:
- `PUBLISH_KEY` - shared secret sent by the admin panel
- `GITHUB_TOKEN` - fine-grained token, Contents: Read and write (secret)

## App
- `app/` - Flutter client (v1.0.3)
- `webview/` - lightweight WebView app (v1.0.4)
- Both read the same `library.json`, so new episodes appear without an app update.
