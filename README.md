<img src="icon.svg" width="80" alt="">

# Co-Stanza

![version](https://img.shields.io/badge/version-1.0.0-111) ![license](https://img.shields.io/badge/license-MIT-111) [![github](https://img.shields.io/badge/github-nulljosh%2Fco--stanza-111)](https://github.com/nulljosh/costanza)

Live at [costanza.heyitsmejosh.com](https://costanza.heyitsmejosh.com).

![screenshot](screenshots/landing.png)

A poetry network with no likes, no ranking, no follower count. Sign in, pick a name, publish. Each poem gets its own page. Your name gets a page with all of them. The front page is everyone's, newest first. Nobody is counting.

v1 adds following and a quiet way to say "I read this". The business is a small yearly fee for a custom domain on your author page.

<img src="progress.svg" width="460">

## Architecture

<img src="architecture.svg" width="600">

## Features

- Write, read, delete your own. Blank line between stanzas, single newlines kept
- Author pages by pen name, poem pages by id
- Sign in with Apple, Google, GitHub, X, or email and password, shared with the rest of the fleet
- Deterministic pixel avatar, click to reshuffle
- Delete your account whenever you want
- Web, iPhone, iPad, Mac, Apple Watch, Android, Windows, Linux

## Run it

```
# web: one static folder
env -u CLOUDFLARE_API_TOKEN npx wrangler deploy

# tests
node --test test.mjs

# apple
cd ios && xcodegen generate && open Stanza.xcodeproj
cd macos && xcodegen generate && open Stanza.xcodeproj
cd watchos && xcodegen generate && open StanzaWatch.xcodeproj

# android / windows / linux (CI builds these; needs JDK 17)
cd kmp && ./gradlew :composeApp:run
```

Backend is the shared Supabase project. One table, `stanza_poems`, row-level security: anyone reads, you insert and delete your own.
