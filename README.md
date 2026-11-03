# AniPix Stream

Anime streaming site (static) + Flutter app. Content lives in this repo.

## How content flows
1. Admin panel (website) -> Settings -> **Publish to site**
2. `netlify/functions/library.mjs` commits `library.json` to this repo
3. The website and the app both read
   `https://raw.githubusercontent.com/nobelfamily537-dev/anipix-stream/main/library.json`
   so new episodes show up without an app update.

## Env vars (Netlify)
- `PUBLISH_KEY` - shared secret sent by the admin panel
- `GITHUB_TOKEN` - fine-grained token, Contents: Read and write (secret)

## App
`app/` - Flutter. Build via GitHub Actions -> "Build APK" -> artifact `anipix-apk`.
