# mela

A Flutter streaming client.

## Build configuration (env vars)

All secrets and deploy targets are injected via `--dart-define` at build
time. See `.env.example` for the full list.

```bash
flutter build apk \
  --dart-define=PROXY_PRIMARY_URL=https://your-worker.dev \
  --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com \
  --dart-define=VERIFY_ET_API_KEY=... \
  --release
```

The Dart `String.fromEnvironment(...)` constants live in:

- `lib/services/api_config.dart` — `PROXY_PRIMARY_URL`, `PROXY_MIRRORS`
- `lib/services/auth_service.dart` — `GOOGLE_WEB_CLIENT_ID`
- `lib/services/payment_service.dart` — `VERIFY_ET_API_KEY`, `PATREON_URL`,
  `PATREON_CREATOR_TOKEN`, `PATREON_VERIFY_URL`

## Secret scanning

CI runs [gitleaks](https://github.com/gitleaks/gitleaks) on every push and
PR via `.github/workflows/secret-scan.yml` using `.gitleaks.toml`. Any
leaked credential blocks the merge.

## Firebase public keys — by design

`android/app/google-services.json` and `lib/firebase_options.dart` contain
Firebase project IDs, OAuth client IDs, and Android/iOS `api_key` values.
**These are not secrets.** Firebase API keys are public identifiers;
security is enforced by:

1. **Firebase App Check** — only requests from a registered, attested app
   are accepted.
2. **Google Cloud API-key restrictions** — the key is locked to specific
   Android package + SHA-1 fingerprints and to specific APIs.
3. **Security Rules** — Firestore / RTDB / Storage rules deny client
   access that bypasses Auth + App Check.

See the Google Cloud Console for `mela-backend` to review or rotate.

## Architecture overview

- Flutter client (this repo) talks to a Cloudflare Worker (separate repo)
  via `ApiConfig.proxyBaseUrl`. The Worker fronts TMDB, Patreon,
  Verify.et, and app remote-config (KV).
- Firebase Auth is used directly from the client. ID tokens are sent to
  the Worker as `Authorization: Bearer <idToken>` for any privileged
  endpoint.
- Local persistence: Hive (movie caches, continue-watching) +
  SharedPreferences (lightweight state) + `SecurePrefs` (AES-256-GCM
  encrypted values like subscription tx IDs).

## License

This project is licensed under the **GNU General Public License v3.0** — see
[`LICENSE`](./LICENSE).

The Stremio add-on stack in `lib/services/addon_*` and the add-ons UI in
`lib/screens/addon_*`, `lib/widgets/addons_rails.dart` are ported from
[NuvioMobile](https://github.com/NuvioMedia/NuvioMobile), also GPL-3.0;
per-file SPDX headers name the original source.

## Resources

- [Flutter docs](https://docs.flutter.dev/)
- [Firebase Auth docs](https://firebase.google.com/docs/auth)
- [Cloudflare Workers docs](https://developers.cloudflare.com/workers/)
- [Stremio add-on protocol](https://stremio.github.io/stremio-addon-sdk/)
- [NuvioMobile (feature reference)](https://github.com/NuvioMedia/NuvioMobile)
