# Changelog

All notable changes to KeenSwitch are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Changes that will land in the next release will be listed here._

## [1.0.0] — 2026-05-20

First public release.

### Features

- Menu bar app for switching IP routing policies on Keenetic routers.
- Main window with a list of network devices: pinned / online / offline groups,
  per-device policy switcher, current routing summary.
- Menu bar dropdown with a compact device picker and one-click policy switch.
- Settings window with five panes: Connection, Routing, Language, Launch, Updates.
- HTTP and HTTPS connection to the router, with optional custom port.
- Password stored in the macOS Keychain (account `router-password`, accessible
  after first unlock).
- Auto-refresh when the network connection is restored.
- Launch at login via `SMAppService`, with an optional **quiet start** mode
  (menu bar only, no Dock icon, no main window).
- Built-in auto-update from GitHub Releases — manual "Check for Updates" and
  one-click install. Code signature of the downloaded bundle is verified
  (`codesign --verify --deep --strict`) before replacement.
- Interface localization: English and Russian. Language can be switched at
  runtime without restarting the app.
- All error messages (including system `URLError` / TLS / DNS errors) are
  routed through the app's L10n tables — no leakage of the macOS system
  locale into the UI.
- Support for KeeneticOS 3.x and newer (Network Policy component required).
  Tested on Giga, Ultra, Viva, Giant, Peak, Hero 4G/4G+, Duo, City, Extra,
  Air and Lite series.

### Engineering

- Swift 5.9+, SwiftUI, Swift Concurrency. Built with Xcode 16+ on macOS 14+.
- Layered architecture: Models / Services / ViewModels / Views / Utilities.
- `RouterServiceProtocol` + `actor KeeneticService` — fully mockable for tests.
- ~70 unit tests using Swift Testing (`@Test`, `#expect`), covering the RCI
  JSON parser (multiple firmware response shapes), connection manager state,
  task cancellation semantics, Keychain round-trips, localization storage
  thread safety, version comparison, and auth-flow password hashing with
  known test vectors.
- UI smoke tests verifying the app launches and the main window appears.
- GitHub Actions: CI (build + test on every PR), Release workflow (push a
  `vX.Y.Z` tag → builds, ad-hoc signs, packages as `.zip`, publishes a GitHub
  Release with SHA256).

---

[Unreleased]: https://github.com/Bayrakovsky/KeenSwitch/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Bayrakovsky/KeenSwitch/releases/tag/v1.0.0
