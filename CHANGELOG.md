# Changelog

All notable changes to KeenSwitch are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Changes that will land in the next release will be listed here._

## [1.0.1] — 2026-05-21

### Fixed
- **Adding any preference field would have silently reset all settings on upgrade.**
  `AppPreferences` used synthesized decoding, so JSON missing a key failed to decode and
  fell back to defaults, wiping language / launch-at-login / quiet-start. Decoding now
  fills missing fields from defaults instead of discarding everything.
- **Keychain password migration could be lost on a locked-Keychain quiet launch.** The
  legacy-account marker was cleared even when the Keychain read failed transiently,
  permanently skipping the migration. The marker is now kept on transient failures and
  retried on the next launch.
- **Wrong password showed a raw "HTTP 401" instead of a friendly message.** The auth POST
  went through the path that throws on any non-2xx status before the credentials check
  could run, so invalid credentials surfaced as an HTTP error. Authentication failures now
  map to the localized "Invalid credentials" message.
- **The main window's toolbar Refresh button didn't recover credentials after a quiet
  launch** (it still called the bare refresh). All Refresh buttons now go through the same
  credential-reloading path.
- **The app could block macOS logout, restart, and shutdown.** `applicationShouldTerminate`
  cancelled every termination except an explicit Quit, which also cancelled
  system-initiated shutdowns. It now allows termination on
  `NSWorkspace.willPowerOffNotification` (logout/restart/shutdown) while still hiding to
  the menu bar on window close / Dock Quit.
- **Setting a device back to the default (segment) policy showed a false "mismatch"
  warning** and didn't mark the default option as active. A device with no explicit IP
  policy inherits the segment default; the active-policy lookup now maps that state to
  the built-in "Default segment policy" instead of returning nothing.
- **Auto-update could delete the app without replacing it.** The installer removed the
  current `.app` before copying the new one, so any failure (full disk, permissions,
  cleared temp) left no app at all. Replacement is now atomic with a backup: the new
  bundle is staged and verified first, the old one is only removed after the swap
  succeeds, and a failed swap restores the backup. Installer paths are now passed as
  arguments instead of being interpolated into the shell script (handles paths with
  quotes/apostrophes).
- **Refresh did nothing after a quiet (login) launch.** If the Keychain was still locked
  at startup, credentials weren't loaded and Refresh silently bailed out. Refresh now
  reloads credentials first; opening the menu bar or main window recovers automatically.
- **Auto-refresh on network restore now works in menu-bar-only mode.** It was wired only
  to the main window, so it never fired when the app ran without a window. The handler
  moved to the app-lifetime view model.
- **Router address pasted from a browser now works.** `http://192.168.1.1`,
  `192.168.1.1/`, and `192.168.1.1:8080` are normalized into host / port / HTTPS instead
  of producing an "invalid address" error. An empty or zero port falls back to the
  scheme default.

### Changed
- Refresh and apply-policy operations now cancel each other to avoid a race on the device
  list.
- Policy discovery skips the 16-slot probe (`Policy0…Policy15`) when the main endpoints
  already returned the full table — fewer requests, faster refresh on slow links.

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

[Unreleased]: https://github.com/Bayrakovsky/KeenSwitch/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Bayrakovsky/KeenSwitch/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Bayrakovsky/KeenSwitch/releases/tag/v1.0.0
