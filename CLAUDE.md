# Co-Stanza

Poetry network. Svbtle-shaped: one column, name, poems, nothing else. Live at costanza.heyitsmejosh.com.

- `web/` is the whole site. `index.html` landing, `app.html` the app (hash routes: `#/`, `#/p/<id>`, `#/by/<name>`, `#/write`, `#/account`, `#/forgot`, `#/reset`), `poem.js` pure helpers shared with `test.mjs`
- Backend: shared Supabase `spark` project (tjsxsqlxjmanwvmywwvw), table `stanza_poems`, RLS read-all / insert-own / delete-own. Migration name `stanza_poems`
- Deploy: `env -u CLOUDFLARE_API_TOKEN npx wrangler deploy`. A push deploys nothing
- Native: `ios/` + `macos/` (xcodegen, shared ContentView.swift, URLSession straight to PostgREST/GoTrue for email/password/Apple; supabase-swift added just for the Google/GitHub/X OAuth browser flow (PKCE), `costanza://` registered as the redirect scheme and in the spark allow-list), `watchos/` (xcodegen, own ContentView.swift, read-only feed, no sign-in), `kmp/` (Ktor client in shared, Compose in composeApp; CI builds msi/deb/apk, no JDK on this Mac)
- Auth: web and native both offer Apple/Google/GitHub/X plus email/password, deterministic pixel avatars (seeded from pen name, no schema/storage), account deletion via the shared spark `delete-account` Edge Function
- Design tokens from heyitsmejosh.com/tokens.css. Sans-serif only, no emojis, no purple
- Auth emails: authmail THEMES has a `stanza` row; redirect host is in the spark allow-list
