# Roadmap

- [x] (11-01: web live. jaybulb-api stanza_kudos, primary key poem and reader, you read only your own rows; rpc stanza_kudos_count answers the author alone, 403 for anyone else; account deletion clears both sides. Poem page: Give kudos / Kudos given toggle for readers, "N kudos, seen only by you" for the author, a sign-in line for guests. test/stanza.mjs covers it. Native apps follow their move to api.jaybulb.com) Kudos (one table, unique on poem+user, no count shown to anyone but the author)
- [x] (11-01: web live. Follow / Following on a poet's page (not your own), a Yours link for signed-in readers, #/yours lists the newest poems from the pen names you follow; jaybulb-api stanza_follows is private to you and cleared with the account; test/stanza.mjs covers it. Native follows their move to api.jaybulb.com) Following and a "yours" feed
- [ ] (11-01: web live, Edit beside Delete on your own poem opens #/write/<id> prefilled and saves in place; jaybulb-api stanza_poems now allows owner updates, id and created_at read-only, smoke test covers author edits and a stranger blocked. Left: iPhone, Mac and Kotlin, which still talk to the old Supabase project; their edit lands with their move to api.jaybulb.com, where the update rule already is) Edit a poem
- [ ] Persist the native session on Android/desktop (multiplatform-settings)
- [ ] TUI feed reader (thin fetch, like wordroot's)
- [ ] ASC record + first submit
- [ ] Custom domains for author pages (the business)

## Ingested 2026-10-30

## Landing pass, 2026-10-30

- [ ] New icon.
