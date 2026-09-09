# Server-Side & Extraction Scripts — Audit Notes

## Finding (Sept 2026)

**No Node.js extraction scripts are present in this workspace.**

A full scan for `*.js` / `*.ts` / `*.mjs` / `*.cjs` files (excluding
platform runner scaffolding) found no scraping or extraction scripts. The
server-side component of FEB is a **Cloudflare Worker proxy** deployed
separately (see `lib/services/api_config.dart` — the primary worker at
`phonofilm-proxy.mela-media-2026.workers.dev`, with build-time mirror
injection via `--dart-define=PROXY_MIRRORS=...`). The worker source is **not
in this repository**, so no server-side HTML-parsing audit is possible from
here.

## If/when the Worker script is added to this repo

Apply the following guidance to keep extraction efficient and cheap:

1. **Prefer Cheerio over full browser rendering.**
   - Cheerio (or `linkedom`) parses HTML with a lightweight DOM, no browser
     engine, ~10–50× cheaper in CPU and memory than Playwright/Puppeteer.
   - Reserve Puppeteer/Playwright **only** for pages that genuinely require
     JavaScript execution to render the target data (check: is the data in
     the raw HTML? If yes, Cheerio is enough).
   - Example skeleton:

     ```js
     import * as cheerio from 'cheerio';

     export async function extractMediaUrls(html) {
       const $ = cheerio.load(html);
       const out = [];
       $('video source, video[src], iframe[src]').each((_, el) => {
         const src = $(el).attr('src');
         if (src) out.push(new URL(src, 'https://example.com').href);
       });
       return [...new Set(out)];
     }
     ```

2. **Cache aggressively at the edge.** Wrap upstream HTML fetches in
   Cloudflare Cache API with a short TTL (e.g., 5–15 min) keyed by URL, so
   repeated client requests never re-fetch/re-parse the same page.

3. **Stream and time-box upstream fetches** (`AbortSignal.timeout`), and
   cap response size so a huge page cannot balloon Worker memory.

4. **Never proxy the API key client-side.** Keep Wyzie/TMDB keys in Worker
   secrets and inject them server-side (the app already expects this).

5. **Return gzip/brotli-compressed JSON** from the Worker. Cloudflare
   Workers compress responses automatically when `Accept-Encoding` allows
   it; the Flutter client explicitly negotiates gzip (see
   `lib/services/compression_client.dart`) and `dart:io` decompresses
   transparently.