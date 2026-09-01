# Vesta Vault mobile client — fork notice

This repository is a fork of [immich-app/immich](https://github.com/immich-app/immich),
kept under the same [AGPL-3.0](./LICENSE) license as upstream. It exists to
adapt Immich's mobile client (`mobile/`) into a white-labeled Vesta Vault
app: rebranding, and a device-pairing flow that lets a Vesta Vault unit be
set up by scanning a QR code instead of typing a WiFi password into a
captive portal.

Per AGPL-3.0, the full source of this modified client — including the
pairing flow added here — stays public in this repository. The pairing
flow's actual decision logic (claim validation, account creation, fraud
checks) lives server-side in Vesta's Cloudflare backend, which is a
separate, independent program this app talks to over HTTPS — not part of
this repository and not implicated by this app's license.

Nothing here is Vesta-proprietary infrastructure: no backend code, no
appliance firmware, no infrastructure credentials. Those live in Vesta's
private repositories and are unaffected by this fork being public.

Upstream is tracked via the `upstream` remote
(`https://github.com/immich-app/immich.git`) so this fork can be rebased
onto new Immich releases rather than drifting from them.

## Status

Scaffolding only as of this commit. The rebrand (app name, icon, bundle
identifiers, `i18n/en.json` strings, `AndroidManifest.xml` /
`Info.plist`) and the pairing flow itself have not been implemented yet —
both require a real Flutter/Xcode/Android toolchain and real hardware to
build and test, which is being done separately from where this notice was
committed.
