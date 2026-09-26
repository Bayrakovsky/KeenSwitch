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
  delivered to every user. The auto-update flow does a `codesign --verify
  --deep --strict` check before swapping the bundle, but that only catches
  bit-rot, not a maliciously-signed bundle.
- **GitHub API token (if set) is stored in the macOS Keychain** under a
  separate account (`github-token`), with `kSecAttrAccessibleAfterFirstUnlock`.
- **Router password is stored in the macOS Keychain** under account
  `router-password`, same accessibility.
- **The auto-update installer is a shell script** generated at runtime and
  executed by `/bin/bash`. Paths in it are interpolated as Swift strings — if
  you find a way to influence those paths via user input or network response,
  that's a finding.

## Thanks

KeenSwitch is a solo open-source project. There's no bug bounty, but I take
reports seriously and respond fast.
