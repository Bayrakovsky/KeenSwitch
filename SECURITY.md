# Security Policy

Thanks for taking the time to disclose security issues responsibly.

## Reporting a vulnerability

**Please do NOT open a public GitHub issue for security problems.** Public issues are
indexed by search engines and watched by anyone — that gives an attacker a head start
between disclosure and a fix being shipped.

Use one of these channels instead:

### Preferred — GitHub Private Vulnerability Reporting

1. Go to the [Security tab](https://github.com/Bayrakovsky/KeenSwitch/security)
   of this repository.
2. Click **Report a vulnerability**.
3. Fill out the form. Only repository maintainers will see it.

### Fallback — email

If you can't use the GitHub flow, email:

**stanislav.job@gmail.com**

(Use the subject line `[KeenSwitch security]` so it doesn't get lost.)

## What to include

A useful report has:

- **Affected version(s)** — KeenSwitch app version and macOS version.
- **Impact** — what an attacker can do (read Keychain? hijack auto-update? leak
  router credentials over the network?).
- **Steps to reproduce** — minimal, deterministic. Logs help (filter `Console.app`
  by `subsystem:com.bayrakovskiy.KeenSwitch`).
- **Proof of concept** — code, screenshots, network captures. Optional but speeds
  things up.
- **Suggested fix** — optional.

## What happens next

- **Within 72 hours**: I acknowledge the report.
- **Within 7 days**: I confirm whether it's reproducible and assign a severity.
- **Fix timeline**:
  - Critical (RCE, credential leak, silent-update hijack): patched and released
    ASAP, typically within a week.
  - High (privilege escalation, sandbox escape): within two weeks.
  - Lower severity: in the next regular release.
- **Credit**: with your permission, I'll credit you in the release notes and the
  CHANGELOG. If you'd rather stay anonymous, just say so.

## Scope

In scope:

- The **KeenSwitch macOS app** — code in this repository.
- The **auto-update flow** (`Services/UpdateChecker.swift`, the installer shell
  script it generates, code signature verification).
- The **Keychain integration** (`Services/KeychainStore.swift`).
- The **RCI HTTP client** (`Services/KeeneticRCIClient.swift`) — auth flow,
  TLS handling, password hashing.
- The **GitHub Actions workflows** (`.github/workflows/`) — anything that runs
  with repository write or release-publishing permissions.

Out of scope:

- Vulnerabilities in **KeeneticOS** itself or the router web interface — report
  those to [Keenetic support](https://help.keenetic.com/).
- Issues that require physical access to an unlocked Mac (we trust the macOS
  account at that point).
- Reports that boil down to "the app uses HTTP by default" — this is a
  documented limitation. Keenetic routers don't ship with trusted certificates
  out of the box, so HTTPS is opt-in. Users who care can flip the toggle in
  Settings → Connection. A report is welcome if you find a *new* way this is
  exploitable beyond the obvious LAN MITM.
- Social-engineering and phishing scenarios that don't involve a code-level bug.

## Known security context

A few things every contributor and reporter should know up front:

- **App Sandbox is OFF.** The auto-updater replaces its own `.app` bundle in
  `/Applications`, which requires entitlements no sandboxed app gets. This is a
  deliberate trade-off documented in CONTRIBUTING.md.
- **Releases are signed ad-hoc, not with a Developer ID** and not notarized.
  Gatekeeper blocks the first launch; users approve the app once via
  System Settings → Privacy & Security → **Open Anyway**, or clear the quarantine
  flag with `xattr -dr com.apple.quarantine`. (Control-click → Open no longer
  bypasses Gatekeeper — Apple removed that in macOS 15 Sequoia.)
  This means a compromised GitHub release token = arbitrary code
  delivered to every user. The auto-update flow does run `codesign --verify
  --deep --strict` on the downloaded bundle before swapping it in, but with
  ad-hoc signatures there is no identity to pin to: that check only proves the
  bundle is internally consistent, so it catches a truncated or tampered
  download, not a bundle an attacker signed ad-hoc themselves.
- **No GitHub token is used.** The updater reads the public Releases API
  anonymously. Every token path — the `Authorization` header in
  `Services/UpdateChecker.swift` and the field in the Settings UI — is commented
  out, and `KeychainStore.githubTokenAccount` (`github-token`) is an unused
  constant kept in case the repository goes private again. A build that sends an
  `Authorization` header to `api.github.com` would itself be a finding.
- **Router password is stored in the macOS Keychain** under service
  `com.bayrakovskiy.KeenSwitch.router`, account `router-password`, with
  `kSecAttrAccessibleAfterFirstUnlock` — so a quiet launch at login can read it
  before the user unlocks the Keychain interactively. It is never written to
  `UserDefaults`.
- **The auto-update installer is a shell script** generated at runtime and
  executed by `/bin/bash` with the user's privileges. Paths are **not**
  interpolated into the script text: they are passed as positional arguments
  (`$1`…`$6`) and quoted at every use, so a path containing quotes, spaces or
  apostrophes cannot break out of its argument. (This was not always true — paths
  were interpolated before 1.0.1.)

  Still worth probing: the `.app` bundle the script installs is whichever
  directory ending in `.app` is found inside the downloaded ZIP, and the staged
  and backup paths are derived from the running bundle's own path. A way to make
  the script act on a path outside the current bundle's directory, or to get a
  bundle other than the intended one picked out of the archive, is a finding.

## Thanks

KeenSwitch is a solo open-source project. There's no bug bounty, but I take
reports seriously and respond fast.
