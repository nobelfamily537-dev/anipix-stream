# AniPix Stream

Static anime streaming site + Flutter app, no build step for the web part.

## Web
- `index.html` - the whole site (playlists, seasons, episodes, player, admin console)
- `netlify.toml` - headers, functions config
- `netlify/functions/library.mjs` - live library API (Netlify Blobs)

## App
- `app/` - Flutter client. Reads the same library, so content added on the
  website appears in the app without an app update.
- Build: GitHub Actions -> "Build APK" -> artifact `anipix-apk`.

## Publishing content
Admin -> Settings -> "Publish to site". Needs `PUBLISH_KEY` set in Netlify
environment variables. Published data is served from
`/.netlify/functions/library` (falls back to `library.json`).

> Demo build: accounts and watchlists are stored on the device only.
