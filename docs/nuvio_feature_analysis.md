# NuvioMobile Feature Analysis → Flutter ("FEB") Integration Map

_Companion document for porting NuvioMobile (Kotlin Multiplatform / Compose) capabilities
into the Flutter streaming app in this repository (package `feb`, README title "mela",
build title "FEB / PhonoFilm")._

---

## 1. Executive summary

`NuvioMobile/` is a **complete, open-source (GPL-3.0) Stremio-style streaming app** built
with Kotlin Multiplatform + Compose Multiplatform, shipping to Android and iOS. Its core
idea is **"bring your own sources"**: the app contains no content — users install catalogs
and source scrapers (Stremio "addons" + JS "plugin" scrapers), and connect optional
torrent/debrid services to turn torrents into instant streams.

The Flutter app in this repo is a **server-curated streaming client**: content comes from
TMDB (through a Cloudflare-Worker proxy), sources are resolved server-side / via embed
scraping, and users get curated rows, search, details, a custom player, HLS downloads,
IPTV, Firebase auth and a Patreon-based subscription.

The two apps overlap on the "meta" layer (TMDB metadata, details pages, continue
watching, downloads, settings) but differ radically on the **source layer**: Nuvio's
addons / plugins / debrid / P2P / cloud-library / scrobbling stack has no equivalent in
the Flutter app today. That source layer is where the bulk of integration value (and
effort) sits.

This document inventories every Nuvio feature, marks what already exists in the Flutter
app, and proposes a phased integration roadmap.

---

## 2. NuvioMobile architecture

| Aspect | Detail |
|---|---|
| Platform | Android + iOS (Kotlin Multiplatform, Compose Multiplatform UI) |
| Modules | `composeApp` (shared KMP app), `androidApp` (launcher icons/activities), `iosApp`, `vendor` (MPVKit, libass-android) |
| Backend | **Supabase** (PostgREST, Auth, Functions, Storage) — account, per-profile sync, membership, cloud saves |
| Networking | Ktor client (OkHttp engine on Android, Darwin on iOS) |
| JSON | kotlinx.serialization |
| Images | Coil 3 (+SVG, cache-control); KMPalette for palette extraction |
| UI | Compose Material3, Navigation3, Haze (liquid glass), Compottie (Lottie), Reorderable |
| Logging | Kermit |
| Crash/observability | Sentry |
| Distribution flavors | **full** (Google Play-excluded: plugins/scrapers, P2P, MPV/libass player, updater, in-app trailers, foreground services) vs **playstore / appstore** (lightweight, policy-compliant). Selected per build; runtime gated via `AppFeaturePolicy` `expect/actual`. |
| Player (full) | ExoPlayer (Media3) + HLS/DASH/SS/RTSP + local **MPV engine** w/ libass (ASS/SSA rich subs); decoder `.aar`s vendored |
| Scripting (full) | **QuickJS** (`quickjs-kt`) + ksoup (HTML parsing) to run third-party JS scrapers |
| iOS full | "Nuvio Engine" C framework (cinterop), CommonCrypto |

**Source-set layout** (this is what you port from):
- `commonMain` — all shared feature code (bulk of port surface).
- `fullCommonMain` — shared "full flavor" code (plugin scraper runtime, scraping).
- `androidMain`/`iosMain` + `androidFull`/`androidPlaystore`/`iosFull`/`iosAppStore` — platform
  `expect/actual` implementations and distribution policy.

**Feature packages** (`composeApp/src/commonMain/kotlin/com/nuvio/app/features/`, ~370 files)
with rough file counts:

```
player (60)  settings (49)  details (37+comp)  simkl (27)  trakt (25)
streams (23) debrid (18)   watchprogress (18)  profiles (16)  library (16)
collection (14)  home (19+comp)  watching (11)  membership (10)  tracking (9)
watched (8)  addons (7)  search (7)  downloads (7)  notifications (5)  cloud (5)
catalog (5)  auth (4)  mdblist (4)  plugins (3)  p2p (3)  trailer (2)  updater (3)  tmdb (5)
```

---

## 3. Nuvio feature inventory

### 3.1 App shell, navigation, settings, core UI
- **4-tab shell** — Home / Search / Library / Profile(Settings). Tablet layouts (≥768dp)
  switch to a floating top bar; classic vs liquid-glass bottom nav styles; adaptive
  expand/collapse on scroll (`MainTabsDestination.kt`, `NavBarStyle`).
- **Profiles** are a first-class tab surface: profile switcher + avatar + name in nav.
- **Settings** (~49 files) — themes (incl. supporter-exclusive themes), nav-bar style,
  poster/card display style, content language, player defaults, downloads, notifications,
  community pages, accounts (Trakt/Simkl/Debrid), about/updater.
- **Core UI kit** — 50 files: shared buttons/cards/sheets, native bottom sheets & tabs on
  Android/iOS, back-handler, exit-app, image loader, insets, haptics, toast controller,
  shared transitions, shimmer/skeletons.
- **Deeplinks** (`core/deeplink`) and **AppGate/AppGateController** (maintenance/session gate).

### 3.2 Accounts & sync backend
- **Supabase auth** (`core/auth`): email/social via Supabase; `DeviceLinkAuthSection` lets a
  second device link to the account; `DeviceSessionRegistration` registers sessions.
- **Server connections** (`features/auth`, `core/network`): endpoint discovery + fallback
  URLs, network-status monitoring, rate-limit tracking (`BackendRateLimit`), custom-server
  connections (full flavor).
- **Sync layer** (`core/sync` + per-feature `*SyncAdapter`s): `SyncManager` coordinates
  background sync of per-profile settings, provider credentials (Trakt/Simkl/debrid keys),
  watched state, library, and progress; `AppForegroundMonitor` re-syncs on foreground;
  `ProfileSettingsCredentialPolicy` restricts which credentials sync server-side.
- **Storage**: profile-scoped local keys (`ProfileScopedKey`), `LocalAccountDataCleaner`
  wipes local data on logout.

### 3.3 Profiles (`features/profiles`)
- Multiple **profiles per account**: name, PIN (with crypto + cache), avatar (server &
  local), profile backgrounds; per-profile local state, per-profile server sync,
  selection routing & switcher, hover haptics (desktop).

### 3.4 Home (`features/home`)
- Sectioned home: **hero** (with trailer background), **continue watching** row (see
  watchprogress), **collection rows** (curated catalog rails driven by server settings),
  poster grids, **state cards**, skeletons.
- `HomeCatalogSettingsRepository` + server sync: which rows appear is configurable per
  profile, synced from the server.
- Catalog data resolved through addon catalogs **and** TMDB/collections.

### 3.5 Search, Catalog, Details
- **Search** (`features/search`): TMDB search + genre/category **discover** rails +
  multi-provider (addon catalog search is also supported) + per-profile search history.
- **Catalog** (`features/catalog`): addon `type:id` catalogs browsed as rails/grids with
  paging; `CatalogTarget` abstraction over addon vs TMDB vs collection sources.
- **Details** (`features/details`, 37 files): meta-details fetch/parse/merge across
  providers (addons' meta, TMDB details incl. extra metadata such as IMDB episode
  ratings, production info); hero with backdrop-palette image + **hero trailer player**
  (in-app, full flavor) + trailer selector; cast rows (shared transitions), poster rails,
  production section; **series content** = season/episode navigation with per-season view
  modes and **episode watched action sheet**; person detail pages; TMDB entity browse;
  comments section (Trakt comments — see 3.13); related content rails.
- **Mdblist** (`features/mdblist`): optional MDBList account used as an additional
  catalog/list source for home rows.

### 3.6 Addons — catalogs & metadata (Stremio protocol)
- `AddonManifestParser` implements the **Stremio addon manifest** (id, name, version,
  resources: `catalog`/`meta`/`stream`/`subtitles`, types: movie/series/…, idPrefixes,
  catalogs with extra properties, behaviorHints incl. `p2p`/`adult`/`configurable`).
- Users install addons by manifest URL (or from a directory screen); addons are
  enabled/disabled individually; per-addon config surface (configurable addons); adult
  content flagged; transport URLs stored for direct HTTP calls (`AddonHttpClient`).
- Everything downstream (home rows, search, details meta, stream fetch, subtitles) is
  **addon-aware**: content ids are namespaced (`addon:...`, type/id) and requests are
  routed to the addon's HTTP endpoints.

### 3.7 Plugins — JS source scrapers (full flavor only)
- A **plugin repository** is a manifest URL listing **scrapers** (id, name, languages,
  supported types movie/tv, formats, platforms, logos, settings).
- Scraper **code is JS** fetched from the repo and executed in an embedded **QuickJS**
  runtime on Android/iOS; HTML parsing via ksoup for scraper output; network access from
  JS. Results are normalized into `PluginRuntimeResult` (title/url/quality/size/language/
  infoHash/headers/subtitles…).
- UI: install repos, enable/disable scrapers, per-scraper toggles & settings, "test
  scraper", group streams by repository; code is cached on disk; repo refresh cadence 6h.

### 3.8 Streams aggregation (`features/streams`)
- One stream-picking surface gathers results from **addon `stream` resources**, **plugin
  scrapers**, and special built-in sources (debrid instant streams, cloud library).
  Grouped by addon/provider with per-group loading/error, filter by addon, badges
  (quality/HDR/audio/seeders/…) with settings-driven badge rules.
- Rich `StreamItem` model understands: direct http(s) URLs, `.m3u8`, magnet links,
  `torrent://infoHash/fileIdx`, `externalUrl` (open externally), infoHash + file index,
  trackers, behaviorHints (binge group, filename/size, proxy headers), debrid cache
  status, per-stream external subtitles.
- **Auto-play policies**: next-episode auto-play stream selection (`StreamAutoPlaySelector`,
  binge-group cache keyed by addon's `behaviorHints.bingeGroup`), autoplay from detail
  screen, and a stream-link cache (reuse last good stream URL).

### 3.9 Debrid (`features/debrid`, 18 files)
- Providers: **Torbox, Premiumize** (visible UI; device-code + API-key auth) and
  **Real-Debrid** (hidden, used only for "client resolve" hints coming from addon stream
  payloads). Capability model per provider: `ClientResolve`, `LocalTorrentCacheCheck`,
  `LocalTorrentResolve`, `CloudLibrary`.
- **Instant / cached playback**: streams that carry a `clientResolve` payload get
  resolved to the debrid CDN (cached → instant); non-cached magnet/torrent streams can be
  sent to the provider for remote download then streamed (**"local torrent resolve"**),
  with file selectors for multi-file torrents.
- Cache-status chips shown on stream cards (checking/cached/not-cached) via provider APIs.
- Stream formatting/templating layer turns provider results into named, quality-tagged
  stream entries (`DebridStreamTemplateEngine` + defaults).

### 3.10 P2P torrent streaming (`features/p2p`, full flavor)
- In-app torrent engine: start playback from infoHash (magnet build incl. trackers,
  v1 `btih`/v2 `btmh`), live state (connecting phases, down/up speed, peers/seeds,
  buffering progress, cache disk usage), per-file index.
- Settings: enable/disable, seeding toggle, torrent profile (soft/balanced/fast), cache
  size (off/2/5/10 GB), hide stats; consent dialog; overlays in player; clear cache.

### 3.11 Cloud library (`features/cloud`)
- Browse the connected debrid provider's **cloud drive** (Torbox / Premiumize): items of
  type torrent / usenet / web-download / file, with per-file playable detection, playback
  URLs, size; drives appear as browsable content and stream entries; local cache checks.

### 3.12 Player (`features/player`, 60 files)
- Full-screen player: gestures (seek/volume/brightness), standard controls, gestures on
  surface, overlays; **episodes panel** for series with next-episode card, **autoplay
  next**; sources panel; side panel (tablet); parental guide overlay; launch external
  players; "watch with…" style flow.
- Engine layer: ExoPlayer (Media3) tracks/seek/playback; **MPV engine + libass** (rich
  ASS/SSA rendering) in full flavor; platform playback data-source factory incl. HLS/DASH/
  SS/RTSP/MP4 + headers; media-item providers.
- **Subtitle pipeline** (`SubtitleRepository`, `SubtitleForwarder`, `SubtitleCacheProvider`,
  cue parser, matching, SDH filter, style panel, per-language preferences): addon/plugin/
  debrid-provided external subs are downloaded/cached and (MPV) rendered as rich ASS;
  SSA/ASS styling; SDH cleanup; audio-track selection + modal.
- **Skip intro / credits**: `SkipIntroApi` + `IntroDB` (config URL) to fetch intro/credits
  timestamps per episode, skip button overlay, and a **"submit intro" dialog** to report
  timestamps upstream.
- Track preference storage; subtitle/audio language prefs from device + user overrides;
  HDR/quality notes; per-stream quality & connectivity-aware decisions live in the
  Flutter app already — Nuvio keeps it in settings + stream badges.

### 3.13 Tracking: Trakt & Simkl + unified layer
- **Tracking abstraction** (`features/tracking`): one API to read/write watched/library/
  progress/scrobble across providers, each item attributed to a provider.
- **Trakt** (`features/trakt`, 25 files): OAuth (client id/secret from config), library
  sync (watched/watchlist/ratings), progress sync, **scrobble** (start/pause/stop),
  **comments** shown on details (own + community), related/recommendations rails, public
  lists as home-row sources, watched-show snapshots, episode id mapping, image utils,
  storage + settings.
- **Simkl** (`features/simkl`, 27 files): OAuth w/ **PKCE**, full sync engine
  (library + watched two-way reconciliation with mutation receipts), scrobble
  reconciliation, anime id preferences & fallback mapping (Simkl ids → TMDB), watch
  diagnostics, refresh policy, storage.
- Nuvio also writes its **own server-side progress** (Supabase) and treats Trakt/Simkl
  as additional sources into the same unified watch-progress model
  (`watchprogress`), so continue watching is consistent across local + Nuvio sync +
  Trakt + Simkl.

### 3.14 Watched, library, watch progress
- `features/watched`: local per-profile watched store (items/episodes), bulk badge
  resolver, episode actions; synced to server via adapters.
- `features/library`: local library (add/remove content) + **Supabase library sync** with
  paging and reconciler, display settings (grid style), saved-content section.
- `features/watchprogress`: single **continue-watching** model that merges local + server +
  Trakt playback/history/show-progress + Simkl playback into rows; rules (90% completion
  threshold, resume positions, dedupe by `progressKey`), per-content next-up rows with
  **release alerts** (unaired next episodes / new-season release), resume prompt on
  launch, hide content, sorting modes (default/streaming-style/split-upcoming), styles
  (card/wide/poster) and preferences, thumbnail/artwork enrichment cache.
- `features/collection`: **user-created collections/folders** of content, editor +
  management screens, resolver over TMDB collection endpoints, sync service.

### 3.15 Downloads (`features/downloads`)
- Download content (from direct URLs or debrid) with platform downloader abstraction:
  Android = WorkManager worker + notification actions + transfer job/foreground service,
  live status, resume, storage. (Compare to the Flutter app's own Dart downloader.)

### 3.16 Notifications (`features/notifications`)
- **Episode-release notifications**: for followed shows, schedule a local notification on
  the release day (9:00 local) with deep link + artwork; permission handling; test
  notification; enable/disable. (Android WorkManager; iOS local notifications.)

### 3.17 Membership (`features/membership`)
- **Member tiers** `SUPPORTER` / `SUPPORTER_PLUS` from Supabase remote data source;
  entitlements = cosmetic only today: gold/jade/rose-gold/arctic-blue/graphite themes,
  profile backgrounds, avatars. Supporter wall, donation progress bar, community pages.

### 3.18 Updater (`features/updater`)
- **In-app updater** (full flavor): checks the GitHub release channel for the current
  branch, compares versions, downloads the right APK asset (ABI-aware), shows a banner +
  dialog with release notes, handles "install unknown sources" flow, ignore-version,
  progress UI; platform APIs for download/install; debug "fake update" tester.

### 3.19 Trailers (`features/trailer`)
- Resolve a title's trailer to a playable source and play **in-app** (hero trailer on
  details + trailer popup) — full flavor; otherwise external YouTube intent.

### 3.20 Misc.
- IntroDB skip + submit (player), IMDb episode-ratings (details), comments (details),
  haptics/perf niceties, GPL-3.0 assets/license, `store.json` for release automation,
  Docs/Stremio-addon-refer folder holds the Stremio addon protocol docs used as reference.

---

## 4. Flutter app ("FEB") — current capability snapshot

Stack: Flutter (Android/iOS/desktop/web), Firebase Auth (Google + Apple), a
Cloudflare-Worker proxy (`phonofilm-proxy...` → TMDB + config + misc), Hive (caches,
continue-watching, library), SharedPreferences + encrypted prefs, `video_player` +
`youtube_player_flutter` + `flutter_inappwebview`, custom HTTP downloader with segment
resume, `cached_network_image`, local notifications, ffmpeg remux (min-gpl), fonts,
screen_brightness / volume control, wakelock, connectivity.

| Area | What exists in lib/ |
|---|---|
| Shell/nav | Home screen w/ floating bottom nav, morphing search dock, drawer/sheets; responsive layouts |
| Home | Curated rails ("dev picks", trending, top-10, collections, continue watching), hero cards, glassmorphism cards, category filter bar |
| Search | TMDB search + discover + history (morphing dock), view-more rails |
| Details | Movie + TV detail screens (3.1k LOC), episode drawer, season browsing, actor/person pages, credits, list detail, similar titles, trailers (youtube + header trailer), add-to-list sheets |
| Player | Custom player (4.7k LOC): HLS/MP4/video_player + YouTube, subtitle pickers (incl. wyzie), skip-intro detector (local heuristics), adaptive quality engine, gestures, connectivity-aware capping, resume, cast? |
| Library | Downloads tab + My Lists tab (user library + custom lists), continue watching (Hive) |
| Downloads | Full custom downloader (m3u8 segment resume, notifications, wakelock, gallery save via ffmpeg remux) |
| IPTV | IPTV channel list + player, telegram channels, server selector |
| Accounts | Firebase Auth (+ Google/Apple), profile screen, account details, manage subscription (Patreon/Verify.et), legal consent, review prompt |
| Content sources | Backend-curated (worker) + embed-scrape `.m3u8` (headless WebView + regex) + wyzie subtitles + IPTV playlists |
| Ops | Remote app config, maintenance gate, turnstile gate, update banner (OTA), endpoint pool w/ mirrors, compression client |
| Design | Tokens/design system, motion, screen metrics, app buttons/cards/loaders |

**Verified absent from lib/:** Trakt, Simkl, debrid providers (Real-Debrid/Premiumize/
Torbox), torrent/magnet/P2P, addons/Stremio manifests, JS plugin scraping, cloud library,
profiles w/ PIN, episode-release notifications, membership tiers/themes, in-app APK
updater, Supabase sync.

---

## 5. Overlap & gap matrix

Legend: ✅ native/equivalent exists · ◐ partial · ❌ absent.

| Capability | Nuvio | FEB (Flutter) | Gap & port effort |
|---|---|---|---|
| TMDB metadata + images | ✅ (details/tmdb) | ✅ (worker-proxied) | — |
| Home rails / curated rows | ✅ addon+server-driven | ✅ server-driven | ◐ replace/append with addon catalogs (M) |
| Search + discover | ✅ | ✅ | ◐ add catalog-source search (S) |
| Continue watching + resume | ✅ multi-source | ✅ Hive local | ◐ enrich w/ next-up + release alerts (M) |
| Season/episode browsing | ✅ | ✅ | ◐ (S) |
| Subtitles | ✅ addon + wyzie-like + ASS/libass | ◐ pickers, no ASS | port subtitle fetch/cache + styles (M–L) |
| Skip intro | ✅ IntroDB (server timestamps + submit) | ◐ local heuristic detector | port IntroDB client + skip button (M) |
| Downloads (direct/HLS) | ✅ | ✅ (stronger segment resume) | — |
| **Addon catalogs + meta** (Stremio) | ✅ | ❌ | port models/parser/repo + screens (M) |
| **Addon streams + aggregation UI** | ✅ | ❌ | port models + streams screen (M) |
| **Plugin JS scrapers** | ✅ QuickJS full-only | ❌ | needs JS engine on device or server-side scraping worker (XL) |
| **Debrid instant/cached resolve** | ✅ TB/PM/RD | ❌ | port provider APIs + settings + resolve (L) |
| **P2P torrent streaming** | ✅ full-only | ❌ | native engine via platform channels/plugin (XL) |
| **Cloud library (TB/PM drives)** | ✅ | ❌ | rides on debrid work (M) |
| **Trakt sync + scrobble + comments** | ✅ | ❌ | OAuth + adapters + UI (L) |
| **Simkl sync + scrobble** | ✅ | ❌ | OAuth(PKCE) + sync engine (L) |
| **Profiles w/ PIN + avatars** | ✅ | ❌ (single user) | local-first port (M) |
| **Cross-device account sync** | ✅ Supabase | ❌ (Firebase auth only) | re-point adapters to Firebase/own backend (L, backend work) |
| Episode-release notifications | ✅ | ❌ | local scheduling port (M) |
| Collections/folders | ✅ | ◐ lists exist | unify (S–M) |
| Member tiers/themes | ✅ | ◐ subscription gating exists | reuse FEB Patreon model (M) |
| In-app updater (APK) | ✅ | ◐ OTA update banner exists | replace w/ GitHub-release updater (M) |
| In-app trailers (hero) | ✅ full-only | ◐ youtube header trailer | (S) |
| External player launch | ✅ | ❌ | (S) |
| IPTV | ❌ (no IPTV) | ✅ | n/a |
| Watch party | ❌ | ✅ wyzie | n/a |

Effort scale is for a Dart port of the **concept + structure** (S ≤ ~2d, M ~1–2w,
L ~3–6w, XL >6w for one engineer).

---

## 6. Licensing & architecture notes (important)

1. **GPL-3.0.** NuvioMobile is GPLv3. Copying or closely translating its code into the
   Flutter app makes the app a derivative work — if you distribute the app, it must be
   GPLv3-compatible (source disclosure, same license). Re-implementing features from the
   protocol/behavior level (Stremio manifest spec, Trakt/Simkl/debrid public APIs) does
   **not** force GPL. Decide the stance before writing code:
   - **Option A – GPL**: fastest, lift code directly (keep attributions + LICENSE).
   - **Option B – clean-room re-implementation**: keep FEB's license; use this analysis +
     public API docs; no code copying. Slower but safe. This repo currently has no
     LICENSE file, so Option A would impose GPL on whatever is distributed.
2. **Different backends.** Nuvio's profile/sync/watched/library server layer is Supabase.
   FEB's is Firebase + a Cloudflare Worker. Server-sync features should be re-pointed
   onto FEB's backend rather than ported verbatim.
3. **Native engines.** Plugin JS scrapers (QuickJS), MPV/libass, and the P2P torrent
   engine are C/Java native code with `expect/actual` wrappers — in Flutter these become
   platform plugins / FFI / server-side equivalents, which dominate effort.
4. **Policy split.** Nuvio ships a compliant "store" flavor and a "full" flavor. Store
   policies (torrent/P2P, third-party JS) matter on Google Play / App Store; plan the
   same gating in Flutter if you target the stores.
5. **Naming/content ids.** Nuvio content ids are provider namespaced (`addon:...`,
   `debrid:...`, `cloud:...`, `type:id`). FEB ids are bare TMDB ids. Any port needs an id
   strategy that lets both coexist (prefix/content-type field on `Movie`-equivalent).

---

## 7. Recommended integration roadmap (Flutter)

Assumes the goal is "give FEB Nuvio's bring-your-own-sources layer". Phases are ordered by
value-per-effort and dependencies; each is independently shippable.

- **Phase 0 — Decisions.** License stance (A/B above); target platforms
  (Android-only lowers native costs); whether cross-device sync is required (adds
  backend work); which debrid/tracking providers to support first.
- **Phase 1 — Addon catalogs & metadata (foundation).**
  Port `AddonManifestParser`, models, repository, HTTP transport, Addons manage screen;
  make FEB's home rails / search / details able to read catalog+meta rows from addons
  alongside TMDB. Content-id namespacing introduced here. *Unlocks everything else.*
- **Phase 2 — Addon streams + Streams screen.**
  Port `StreamItem` model, `StreamsRepository`, per-group fetch UI, badges; port
  `StreamLinkCache` + binge-group caching. Wire addon stream fetch + existing embed
  scrapers as "sources" behind one picker.
- **Phase 3 — Debrid instant resolve.**
  Port provider auth (Torbox/Premiumize device-code) + settings + API clients; implement
  `ClientResolve` handling + cache-status checks; non-cached → send to debrid ("remote
  torrent") w/ file selection. Ride-on: **cloud library** tab for connected providers.
- **Phase 4 — Tracking providers.**
  Trakt + Simkl OAuth, scrobble on play/pause/stop, library/watched two-way sync adapted
  to FEB's Hive models; feed unified continue-watching; details comments & related from
  Trakt; (Simkl anime mapping only if anime is in scope).
- **Phase 5 — Watch-progress polish.**
  Next-up episodes, release/new-season alerts, resume-on-launch prompt, hide/dismiss
  rows, display styles on top of the existing continue-watching row.
- **Phase 6 — Player depth.**
  Skip-intro via IntroDB (+ submit), external-player launch, subtitle download/cache +
  SDH filter + style panel (video_player-compatible: SRT/VTT/WebVTT; ASS needs a
  converter or native lib), next-episode autoplay.
- **Phase 7 — Profiles (local-first).**
  Multiple profiles + PIN + avatars/backgrounds; per-profile Hive scopes; then
  (optionally) sync via Firebase.
- **Phase 8 — Release notifications, updater, membership themes.**
  Episode-release local notifications; GitHub-release in-app APK updater replacing the
  OTA banner; gate cosmetic themes behind the existing Patreon subscription.
- **Phase 9 — Heavy/native (only if required & licensed-in).**
  Plugin JS scrapers (QuickJS plugin or scrape-server), P2P torrent engine (native
  plugin), MPV/libass player swap. Each is a standalone project-sized effort.

**Suggested first milestone:** Phase 1 + 2 = "browse and watch from any Stremio addon,
catalogs on Home/Search, unified stream picker with badges." This demonstrates the whole
pipeline with pure-Dart code and no native work.

---

## 8. Key Nuvio files to port (index)

- Addons: `features/addons/AddonManifestParser.kt`, `AddonModels.kt`,
  `AddonRepository.kt`, `AddonHttpClient.kt`, `AddonTransportUrls.kt`, `AddonsScreen.kt`
- Streams: `features/streams/StreamModels.kt`, `StreamsRepository.kt`, `StreamParser.kt`,
  `StreamLinkCacheRepository(+Storage)`, `BingeGroupCache*`, `StreamAutoPlay*`
- Debrid: `features/debrid/DebridProvider(+Apis).kt`, `DebridSettings*`,
  `DirectDebridResolver.kt`, `DirectDebridStreamPreparer.kt`, `LocalDebrid*`,
  `DebridFileSelectors.kt`, `DebridStreamFormatter*.kt`, `DebridApiClients/Models.kt`
- Cloud: `features/cloud/*`
- Plugins (reference only): `features/plugins/PluginModels.kt`, `PluginRepository.kt`
  + `androidFull/.../PluginPlatform.android.kt`, `PluginScraperCodeFileStore.android.kt`
- P2P (reference only): `features/p2p/P2pStreaming.kt` + android/iOS engines
- Watch/progress: `features/watchprogress/*`, `features/watched/*`,
  `features/watching/*`
- Library/collections: `features/library/*`, `features/collection/*`
- Tracking: `features/tracking/*`, `features/trakt/*`, `features/simkl/*`
- Player: `features/player/SubtitleRepository.kt`, `SkipIntroApi.kt`,
  `SkipIntroRepository.kt`, `PlayerNextEpisodeAutoPlay.kt`, `SubtitleSdhFilter.kt`
- Notifications: `features/notifications/*`
- Profiles: `features/profiles/*` (PIN crypto, storage, routing)
- Updater: `features/updater/AppUpdater*.kt`
- Membership: `features/membership/*`
- Home/settings/search/catalog/details/tmdb: as listed in §3 — port models/repos first,
  adapt screens to existing FEB widgets.

---

_Generated from a static review of `NuvioMobile/` (commonMain + android/ios source sets)
and `lib/`. File counts approximate._
