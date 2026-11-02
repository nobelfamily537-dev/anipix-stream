# AniPix Stream

Static anime streaming site — single-file front end, no build step.

- `index.html` — the whole app (playlists, seasons, episodes, player, admin console)
- `netlify.toml` — headers + cache rules
- `library.json` — optional: published library (exported from Admin → Settings), baked in at deploy time

Deployed on Netlify. All data lives in the browser (localStorage); `library.json` is what makes
the catalogue visible to every visitor.

> Demo build: accounts, admin roles and the library are client-side only.
