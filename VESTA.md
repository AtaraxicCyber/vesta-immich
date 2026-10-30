# Vesta Cloud — fork notice and change log

This repository is a fork of [immich-app/immich](https://github.com/immich-app/immich),
kept under the same [AGPL-3.0](./LICENSE) license as upstream. It adapts Immich
into **Vesta Cloud**, a hosted, private family photo and file service.

Per AGPL-3.0, the full source of the modified apps and server stays public here,
and the apps link to it (mobile: profile menu → **Source code**). Vesta's
provisioning, billing and infrastructure code are separate programs that talk to
this one over the network. They live in Vesta's private repositories and are not
part of this fork.

"Immich" and the Immich logo are upstream's marks. The Vesta Cloud name and the
house-and-flame mark replace them everywhere users see them.

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | Untouched mirror of upstream `immich-app/immich` |
| `vesta/main` | Default branch. Vesta work, based on upstream tag `v3.3.5` |
| `vesta/<feature>` | Feature branches, merged into `vesta/main` by PR |
| `archive/phase1-app-pairing` | Earlier Vesta Vault QR/WiFi pairing work (Sept 2026), kept for reference |

Upstream sync: merge the next stable upstream tag into a `sync/vX.Y.Z` branch,
test, then merge into `vesta/main`. Never rebase `vesta/main`.

## Changes from upstream

### Branding (`vesta/rebrand`)

To keep upstream merges cheap, Immich's asset **file names are reused** and only
their contents change. Code that loads `assets/immich-logo.png` and similar
files is untouched.

- **Brand source:** `design/vesta/` holds the source mark
  (`vesta-mark-source.svg`), cleaned masters, and `build_brand.py`, which
  regenerates every icon, splash screen and logo below. After changing the logo,
  run `python3 design/vesta/build_brand.py` from the repo root. Don't edit the
  generated images by hand.
- **App identity**
  - Name: **Vesta Cloud** (Android `app_name`, iOS `CFBundleDisplayName`,
    share-sheet labels, web manifest and page titles).
  - Android `applicationId` is `com.vestavault.app`. The Kotlin `namespace`
    stays `app.alextran.immich` so upstream code doesn't move.
  - iOS bundle IDs (`ios/Signing.xcconfig`): `com.vestavault.app`,
    `com.vestavault.app.dev`, app group `group.com.vestavault.app.share`.
    `IMMICH_TEAM_ID` is blank until Vesta's Apple Developer account exists.
- **Icons and splash:** Android launcher, adaptive (vector), monochrome and
  notification icons; iOS AppIcon set and launch image; web favicons,
  touch icon and installable-app icons. App icons use a white background.
  Splash backgrounds are `#ffffff` (light) and `#0a0b0d` (dark).
- **Colours:** the default theme preset now renders Vesta orange
  (`#d65400` light, `#f07328` dark): `mobile/lib/constants/colors.dart` and
  `web/src/app.css`.
- **Logos in the apps:** the mobile wordmark and inline logos use the same file
  names. Web logos are swapped at startup via `logoManager.setLogo` in
  `web/src/lib/vesta-brand.ts`.
- **Text:** 25 end-user English strings in `i18n/en.json` now say Vesta Cloud,
  and one string was added (`report_an_issue`). Admin, self-hosting and
  purchase strings, and other languages, are unchanged for now.
- **Links:** the mobile "GitHub" link is relabelled "Source code" and points at
  this repository. The mobile crash screen sends bug reports to this
  repository's issues instead of Immich's Discord and GitHub.

### CI (`vesta/fork-ci`)

Upstream workflows assume Immich's own infrastructure. Each fork change is marked
with a `Vesta:` comment in the workflow file. Keep those comments when merging
upstream.

| Workflow | Change |
| --- | --- |
| `docker.yml` | Skipped outside `immich-app`. Its image names can't handle an uppercase owner, and it pushes to Immich's registries |
| `vesta-docker.yml` (new) | Builds `ghcr.io/<owner, lowercased>/vesta-server` from `server/Dockerfile`: build-only on PRs, pushed on `vesta/main` |
| `test.yml` (Lint Web) | `ubuntu-latest` instead of upstream's self-hosted `mich` runner, with an 8 GB Node heap for ESLint |
| `build-mobile.yml` (Android) | `ubuntu-latest` instead of `mich`. The APK is debug-signed until Vesta signing secrets (`KEY_JKS`, `ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`) are added |
| `static_analysis.yml` | Plain `dart analyze --fatal-infos`. Upstream's DCM linter needs a paid licence |
| `pr-label-validation.yml` | Skipped outside `immich-app`. The `changelog:*` labels are upstream's release process |

Upstream fixes ported early, so drop them when the upstream version arrives in a
sync:

- `server/test/medium/specs/sync/sync-album-user.spec.ts`: order-independent
  assertion for "should detect and sync a new shared user", from upstream `main`.

## Known Immich leftovers (to do)

- Web help modal, docs links and the version-announcement banner still point
  at immich.app.
- Admin, onboarding, purchase/"Buy Immich" and self-hosting screens. Most will
  be hidden for Vesta tenants rather than reworded.
- The mobile loading indicator spins the logo (it suited Immich's flower).
- The `immich://` deep-link scheme and Android Kotlin package names.
- Translations other than English.
