# Architecture

Costanza is a place to post poems and read other people's. There is no algorithm sorting anything and no scores. Poems sit in one list in the order they were written.

Everything lives in a single database table, and the database itself decides who is allowed to read or change each row, so there is no server code in between. The website is one HTML file. The iPhone, Mac, Watch, Android, and desktop apps all talk to that same database directly.

## How it runs

Clients talk directly to Supabase PostgREST (poems table) and GoTrue (auth). The web app is a static file hash-routed in `app.html`; native apps use URLSession (Swift) or Ktor (Kotlin) against the same public endpoints. A poem is title, pen name, body, timestamp. Pages are simple queries: newest fifty, author match, or single poem by ID. Row-level security enforces read-all, insert-own, delete-own. Email/password and social sign-in (Apple, Google, GitHub, X) share the same auth flow.

| File | What it owns |
|---|---|
| `web/index.html` | Landing page and explainer. |
| `web/app.html` | Sole app file. Hash routes: `#/` (feed), `#/p/<id>` (poem), `#/by/<name>` (author), `#/write`, `#/account`, `#/forgot`, `#/reset`. Loads Supabase JS SDK from CDN. Inline CSS. |
| `web/poem.js` | Pure helpers (parse stanzas, format text, validate inputs). Shared by `app.html` and `test.mjs`. |
| `test.mjs` | Unit tests for poem parsing and validation. |
| `ios/` + `macos/` | SwiftUI, xcodegen project. Shared ContentView.swift for iOS and macOS (just different window sizes). URLSession to PostgREST/GoTrue. UserDefaults for session token. |
| `watchos/` | watchOS app. Read-only poem feed, no sign-in. |
| `kmp/` | Kotlin Multiplatform. `shared/` has Ktor HTTP client (mirrors Swift HTTP logic). `composeApp/` renders the same layout in Compose. CI builds msi, deb, apk. |
| `wrangler.toml` | Cloudflare Worker for static file serving. No worker.js needed. |

## Storage

Table `stanza_poems` on the shared Supabase `spark` project (tjsxsqlxjmanwvmywwvw):

- Columns: id (UUID), user_id, title, name (pen name), body, created_at
- Row-level security: SELECT * (public read), INSERT with user_id = current user, DELETE only own rows
- Constraints: title, name, body length limits enforced at DB, not client

Auth is handled by Supabase GoTrue (email/password, Apple, Google, GitHub, X OAuth). Every platform sends the same anon key and uses the user's session token.

## Clients

All platforms are stateless: query the DB, get results, render. No polling, no websockets. Pagination handled by the client (top 50 for feed). Session token persists in browser localStorage (web) or UserDefaults (iOS/macOS) or SharedPreferences (Android).
