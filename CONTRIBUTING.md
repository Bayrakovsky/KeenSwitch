# Contributing to KeenSwitch

Thanks for your interest in improving KeenSwitch! This document collects everything
you need to know to set up a dev environment, run the tests, and ship a clean PR.

## Quick links

- **Bug?** Open an issue using the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) template.
- **Idea?** Open an issue using the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) template.
- **Question about a Keenetic router model not in the supported list?** Open an issue —
  if it runs KeeneticOS 3.x with the Network Policy component, it should work, and we
  want to grow that table.

## Requirements

- **macOS 14 Sonoma** or later to run; **macOS 26.6** or later to build
  (Xcode 27 installs only on Apple Silicon Macs running Tahoe 26.6+)
- **Xcode 27** — the project builds against the macOS 27 SDK in Swift 6 language mode.
  CI runs on the `xcode-27` runner image and keeps a `macos-26` / Xcode 26.3 job as a
  fallback while that image is in public preview — see `.github/workflows/ci.yml`
- A Keenetic router on the same network, for manual testing of the connection flow

## Building

```bash
git clone https://github.com/Bayrakovsky/KeenSwitch.git
cd KeenSwitch
open KeenSwitch.xcodeproj
# Product → Run  ⌘R
```

Or from the command line:

```bash
xcodebuild \
  -project KeenSwitch.xcodeproj \
  -scheme KeenSwitch \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Running tests

Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing)
(`@Test`, `#expect`) and live in `KeenSwitchTests/`. There are no network calls — every
test against the router goes through `MockRouterService`.

```bash
xcodebuild \
  -project KeenSwitch.xcodeproj \
  -scheme KeenSwitch \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  -only-testing:KeenSwitchTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

UI smoke tests live in `KeenSwitchUITests/`. They launch the app and verify the main
window appears — they intentionally don't exercise the Keychain or real router flow.

## Project layout

```
KeenSwitch/
├── Models/          # Plain value types (Sendable, Codable). No dependencies.
├── Services/        # Network, Keychain, login items, update checker, window mgmt.
├── ViewModels/      # @Observable coordinators. UI talks only to these.
├── Views/           # SwiftUI views — pure presentation.
├── Utilities/       # L10n, error helpers, Bundle extensions.
└── Localizable.xcstrings  # All user-facing strings (EN / RU).

KeenSwitchTests/     # Swift Testing unit tests.
KeenSwitchUITests/   # XCUI smoke tests.
.github/workflows/   # CI (build + test) and Release (tag → .app.zip).
```

## Forking the project

If you want to fork and ship your own build, update **one place**:

- `KeenSwitch/Utilities/AppConfiguration.swift` — change `githubRepoSlug` to point at
  your fork. The auto-updater uses this to fetch GitHub Releases.

The bundle identifier (`com.bayrakovskiy.KeenSwitch`) appears in a few more places
(Logger subsystems, the Keychain `service` constant in `KeychainStore`, the XPC service
name prefix in `LaunchAtLoginDetector`). Grep and replace before publishing your fork.

## Code style

- **Swift 5.9+ idioms**: prefer `@Observable` over `ObservableObject`, structured
  concurrency over `DispatchQueue` where reasonable, `@MainActor` on UI-touching types.
- **Comments**: explain *why*, not *what*. They're in Russian — that's a deliberate
  project choice; the README and these docs are English. If you contribute, write
  comments in whichever language you're comfortable with — we'll sort it out in review.
- **All user-facing strings go through `L10n.tr("Key")`** with entries in
  `Localizable.xcstrings` for both EN and RU. Never use `error.localizedDescription`
  directly for UI — use `error.userFacingMessage` from `Utilities/Error+UserMessage.swift`,
  which routes system errors through our L10n tables instead of the OS locale.
- **Tests**: when you add a feature, add a test. When you fix a bug, add a regression
  test. The `MockRouterService` makes router-side scenarios easy to construct.

## Adding a new router model

If you tested KeenSwitch on a model not in the table in [README.md](README.md),
please open a PR adding it. Format:

```markdown
| Series | KN-xxxx, KN-yyyy |
```

## Adding a localization

Today we ship EN and RU. To add a new language:

1. Open `KeenSwitch/Localizable.xcstrings` in Xcode and add the language in the inspector.
2. Translate every entry — Xcode flags untranslated keys.
3. Add a new case to `Models/AppLanguage.swift` and update the picker in
   `Views/SettingsView.swift`.
4. Test the language switch in the running app (Settings → Language).

## Pull request checklist

Before opening a PR:

- [ ] `xcodebuild ... build` passes locally.
- [ ] `xcodebuild ... test` passes locally (or you've added a test for your change).
- [ ] New user-facing strings are in `Localizable.xcstrings` with both EN and RU.
- [ ] Commit messages describe *why*. One concept per commit.
- [ ] If you touched the auto-updater or installer script (`Services/UpdateChecker.swift`),
      describe in the PR how you verified it doesn't break on a real install.

## Release process

For maintainers, see [`.github/workflows/release.yml`](.github/workflows/release.yml).
TL;DR: push a tag like `v1.2.3` → CI builds, signs ad-hoc, packages as `.zip`,
publishes a GitHub Release with SHA256.

## Security

KeenSwitch is **not sandboxed** (the auto-updater needs to replace its own `.app` bundle)
and connects to your router over HTTP by default (Keenetic routers don't ship with
trusted certificates out of the box). For the threat model and reporting flow see
[SECURITY.md](SECURITY.md).

## Code of Conduct

By participating in this project, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree your code will be released under the [MIT License](LICENSE).
