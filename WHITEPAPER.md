# Co-Stanza Technical Whitepaper

**v1.0** | September 2026

Most poetry sites turn into a popularity contest: likes, follows, algorithmic feeds, the poem competing with its own metrics. Co-Stanza exists to strip that back to just the writing. It is a poetry network with one table and no ranking, because a like count changes what people write toward. Poems are rows. Pages are queries over those rows. Every client, web or native, talks straight to the database through row-level security, because a poem and a comment thread do not need a server in between deciding who gets to read what; the database's own row-level security already knows.

## The core mechanic

A poem is a title, a pen name, a body and a timestamp, owned by an account. The body is plain text, because a poem does not need bold or a font picker, and giving it one would turn writing time into formatting time. Blank lines separate stanzas; single newlines are kept as line breaks, matching how poems actually get typed. That rule is the only formatting Co-Stanza has, and it lives in one function shared by the web app and its test, so the web and every native client render a poem exactly the same way.

Three pages fall out of one table:

- The front page: newest fifty poems.
- An author page: poems where the pen name matches.
- A poem page: one row by id.

There is no like, follow, comment or count. The order is time, because time is the one ordering that cannot be gamed and does not reward whoever posts loudest. That is deliberate and it is most of the design.

## Storage

One Postgres table, `stanza_poems`, on the shared Supabase project the rest of the fleet uses, because a one-table app does not earn its own database. Row-level security does the authorization: any request may read, an authenticated user may insert rows carrying their own id, and may delete only those. Length checks on title, name and body are database constraints, not client code, so every platform gets them for free instead of five different clients re-implementing the same validation and drifting apart.

## Clients

The web app is a single static HTML file plus a small module of pure functions. It loads the Supabase JS client from a CDN and routes on the URL hash. Accounts are email and password; confirmation mail is branded by the fleet's authmail Worker.

The iOS and macOS apps share one SwiftUI file, because they are the same product on two Apple screen sizes and a second file would only be a second place to fix the same bug. They use URLSession against the PostgREST and GoTrue endpoints directly, with the same anon key that ships in the web bundle, since the key is already public in the browser and hiding it again behind a native client would add a hop for no real secrecy. The session token is kept in UserDefaults.

Android, Windows and Linux come from one Kotlin Multiplatform module. A Ktor client in `shared` mirrors the Swift store; a Compose screen in `composeApp` mirrors the web layout. GitHub Actions builds the msi, deb and apk.

## Hosting

Cloudflare Workers serves the `web/` folder as static assets on `costanza.heyitsmejosh.com`. Deploys are one wrangler command. There is nothing to run.

## What is left out, and why

No server means no moderation queue, no rate limit beyond Supabase's, no search. Those come when there are enough poems to need them, not before, since building them early would be guessing at a shape nobody has stress-tested yet. Kudos, in the Svbtle sense, is the first feature on the list because it is the smallest possible acknowledgment a reader can give without becoming a like count; it is one more table and a unique constraint.

MIT 2026 Joshua Trommel
