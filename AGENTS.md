# AGENTS.md — mela / NuvioMobile

## Repository Structure

- **NuvioMobile/** — Kotlin Multiplatform + Compose Multiplatform app (Android / iOS / Desktop)
- **claude-mem/workers/sync-hub/** — Cloudflare Workers + Durable Objects (TypeScript)
- **gstack/** — gstack skill suite (local vendored copy)
- **CLAUDE.md** — Agentic OS Kernel instructions (COO role, agent registry, gstack skills)

---

## NuvioMobile (Kotlin Multiplatform)

### Key Commands

| Task | Command |
|------|---------|
| Android Debug (full) | `./gradlew :androidApp:assembleFullDebug` |
| Android Debug (playstore) | `./gradlew :androidApp:assemblePlaystoreDebug` |
| Android Release (full) | `./gradlew :androidApp:assembleFullRelease` |
| Android Release (playstore) | `./gradlew :androidApp:assemblePlaystoreRelease` |
| iOS Simulator (full) | `env NUVIO_IOS_DISTRIBUTION=full xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp -configuration Debug -sdk iphonesimulator -derivedDataPath build/ios-derived-full-simulator CODE_SIGNING_ALLOWED=NO build` |
| iOS Device (appstore) | Uses `NUVIO_IOS_DISTRIBUTION=appstore` (default) |
| Generate runtime configs | `./gradlew :composeApp:generateRuntimeConfigs` (auto-runs before Kotlin compilation) |

### Required Setup

**`local.properties`** at `NuvioMobile/` root (not committed). Required keys:
```
NUVIO_SUPABASE_URL=
NUVIO_SUPABASE_ANON_KEY=
NUVIO_SUPABASE_FALLBACK_URL=
SENTRY_DSN=
TRAKT_CLIENT_ID=
TRAKT_CLIENT_SECRET=
TRAKT_REDIRECT_URI=nuvio://auth/trakt
SIMKL_CLIENT_ID=
SIMKL_REDIRECT_URI=nuvio://auth/simkl
SIMKL_APP_NAME=nuvio
INTRODB_API_URL=
IMDB_RATINGS_API_BASE_URL=
IMDB_TAPFRAME_API_BASE_URL=
PREMIUMIZE_CLIENT_ID=
CONTRIBUTIONS_URL=
DONATIONS_BASE_URL=
DONATIONS_DONATE_URL=
NUVIO_IOS_DISTRIBUTION=full|appstore
NUVIO_ANDROID_DISTRIBUTION=full|playstore
NUVIO_RELEASE_STORE_FILE=
NUVIO_RELEASE_STORE_PASSWORD=
NUVIO_RELEASE_KEY_ALIAS=
NUVIO_RELEASE_KEY_PASSWORD=
```

### Build Quirks

- **Two Android distributions**: `full` (includes QuickJS, KSoup, P2P, plugins) vs `playstore` (store-compliant). Controlled by `NUVIO_ANDROID_DISTRIBUTION` or task name (`assembleFullDebug` vs `assemblePlaystoreDebug`).
- **Two iOS distributions**: `full` (includes NuvioEngine, QuickJS) vs `appstore`. Controlled by `NUVIO_IOS_DISTRIBUTION` env var.
- **Runtime configs generated at build time**: `generateRuntimeConfigs` task writes Kotlin constants to `build/generated/runtime-config/kotlin/` — all Kotlin compilation depends on it.
- **Gradle configuration cache enabled** (`org.gradle.configuration-cache=true` in gradle.properties).
- **ProGuard rules** in `composeApp/proguard-rules.pro` — keeps Supabase, Ktor, Media3, MPV, QuickJS, NuvioEngine JNI classes.

### Testing

- No standard unit test suite visible in composeApp.
- Android host tests in `androidHostTest` source set (Robolectric, mockwebserver).
- No ktlint/detekt configs found.

### Strict Contribution Policy (from CONTRIBUTING.md)

- **PRs only for**: reproducible bug fixes, UI glitch fixes (with before/after proof), behavior bug fixes, small maintenance, docs fixes, translations.
- **No PRs for**: new features, UX/UI redesigns, cosmetic changes, refactors without maintenance need, dependency/architecture changes without approval.
- **UI PRs require**: linked bug issue, explanation, before/after screenshots/video, minimal fix.
- **Behavior PRs require**: old vs broken vs new behavior, how tested, linked bug or approved feature request.
- **Large changes require**: feature request issue + explicit maintainer approval before PR.

---

## claude-mem/workers/sync-hub (Cloudflare Workers)

### Key Commands

```bash
cd claude-mem/workers/sync-hub
bun install --frozen-lockfile
bun run test           # vitest run (excludes ws.test.ts)
bun run test:ws        # vitest run --maxWorkers=1 --no-isolate test/ws.test.ts
bun run lint           # eslint .
bunx tsc --noEmit      # typecheck
bun run deploy         # wrangler deploy
bun run dev            # wrangler dev
bun run cf-typegen     # wrangler types --strict-vars=false
```

### Architecture

- **Stateless front Worker** (`src/index.ts`) + **one SQLite-backed Durable Object per user** (`src/do/SyncHub.ts`).
- **KV namespace** `AUTH_CACHE` (id in wrangler.jsonc): `verdict:<sha256>` (token cache, 60s TTL) + `control:kill-switch` (emergency brake).
- **Two crons**: `7 * * * *` (hourly watchdog), `*/5 * * * *` (control-plane uptime probe).
- **Secrets** (via `wrangler secret put`): `CMEM_INTERNAL_PROJECTOR_SECRET`, `ANALYTICS_API_TOKEN`, `DISCORD_WEBHOOK_URL`.

### Durable Object Anti-Patterns (enforced by ESLint)

- ❌ `setTimeout`/`setInterval` in DO — use `ctx.storage.setAlarm()`
- ❌ Outbound `fetch()` from DO — verification/upstream calls live in front Worker
- ❌ `server.accept()` — use `ctx.acceptWebSocket()`

### Deploy Checklist (from DEPLOY.md)

```bash
cd claude-mem/workers/sync-hub
bun install --frozen-lockfile
bun run test && bun run test:ws && bun run lint && bunx tsc --noEmit
wrangler secret put CMEM_INTERNAL_PROJECTOR_SECRET  # first deploy / rotation only
wrangler deploy --dry-run
wrangler deploy
```

Post-deploy: verify cron in dashboard, run threshold-trip rehearsal (§5 in DEPLOY.md), confirm canary logging `"converged":true,"sync_mode":"live"`.

### Canary

```bash
CANARY_HUB_URL=https://sync-hub.<account>.workers.dev \
CANARY_USER_ID=canary-user \
CANARY_TOKEN=<real cmem.ai token> \
bun canary/canary.ts >> ~/.claude-mem/logs/sync-canary.jsonl
```

---

## gstack Skills (Local)

Available via `/skillname` or `/gstack` router. Key skills:
- `/investigate` — systematic debugging (use when user reports errors/bugs)
- `/qa` / `/qa-only` — test web app + fix bugs / report-only
- `/ship` — ship workflow (test, review, bump version, changelog, PR)
- `/review` — pre-landing PR review
- `/plan-eng-review` / `/plan-ceo-review` / `/plan-design-review` — plan reviews
- `/design-review` — live visual QA
- `/browse` — real browser automation
- `/autoplan` — full auto-review pipeline

---

## Agent Registry (from CLAUDE.md)

| Agent | Trigger |
|-------|---------|
| @dev | "build", "fix", "refactor", "feature" (Flutter/Dart — but this repo is KMP) |
| @writer | "write", "draft", "doc", "blog" |
| @researcher | "research", "analyze", "compare", "find" |
| @ops | "deploy", "CI", "release", "server" |

**Note**: @dev trigger mentions Flutter/Dart but this repo is Kotlin Multiplatform + TypeScript Workers. Adjust routing accordingly.

---

## Quick Reference

- **Version catalog**: `NuvioMobile/gradle/libs.versions.toml` (Kotlin 2.4.10, AGP 9.2.0, Compose 1.12.0)
- **Gradle JVM args**: 12G heap, 2G metaspace, config cache + build cache enabled
- **Kotlin daemon**: 8G, native 16G
- **iOS version source**: `iosApp/Configuration/Version.xcconfig` (MARKETING_VERSION, CURRENT_PROJECT_VERSION)