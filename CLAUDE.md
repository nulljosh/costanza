# Co-Stanza

Poetry network. Svbtle-shaped: one column, name, poems, nothing else. Live at costanza.jaybulb.com. App Store: ASC 6829546496 (Co-Stanza; "Costanza" is taken), iOS, iPad and Mac 1.0 submitted 2026-11-01. Ship: archive `ios/` and `macos/`, export with `ExportOptions.plist`, metadata in `metadata/`.

- `web/` is the whole site. `index.html` landing, `app.html` the app (hash routes: `#/`, `#/p/<id>`, `#/by/<name>`, `#/write`, `#/account`, `#/forgot`, `#/reset`), `poem.js` pure helpers shared with `test.mjs`
- Backend: jaybulb-api (api.jaybulb.com, D1), table `stanza_poems`: read public, insert signed-in, update and delete owner. The old Supabase `spark` project is no longer used by web or native
- Deploy: `env -u CLOUDFLARE_API_TOKEN npx wrangler deploy`. A push deploys nothing
- Native: `ios/` + `macos/` (xcodegen, shared ContentView.swift, URLSession straight to jaybulb-api for email/password and Apple, no SDK; refresh token in the Keychain; report, hide and block on every poem; launch flags `-shotPoem YES` and `-shotAuthor YES` drive store screenshots), `watchos/` (xcodegen, own ContentView.swift, read-only feed, no sign-in), `kmp/` (Ktor client in shared, Compose in composeApp; CI builds msi/deb/apk, no JDK on this Mac)
- Auth: web offers Apple/Google/GitHub/X plus email/password, native offers Apple plus email/password, deterministic pixel avatars (seeded from pen name, no schema/storage), account deletion via jaybulb-api `DELETE /auth/user`, which removes every poem too
- Design tokens from heyitsmejosh.com/tokens.css. Sans-serif only, no emojis, no purple
- Auth emails: authmail THEMES has a `stanza` row; redirect host is in the spark allow-list
