# ios-ipa-decrypt — field notes

Notes on getting an IPA onto an Apple Silicon Mac and decrypting it host-side, **without a jailbroken device**.

This repository is **documentation, not a tool**. It describes the mechanism, the decision rules, the measurements, and the failure signatures — plus a handful of ≤20-line examples to make each claim checkable. There is no end-to-end script here on purpose: the interesting knowledge is ~5 KB of invariants, and wrapping those in 1000 lines of retries, fallbacks and cleanup only hides them.

## Two facts that carry the whole thing

1. **A token is not a credential.** A TestFlight session only grants the right to *download*. The right to *decrypt* is the account-level FairPlay credential, bound to the `user` + `key` fields inside each `SC_Info/*.sinf` — call that pair the **selector**. Same selector → one enrollment model decrypts every package, from any channel, forever. Different selector → that model is useless for this package, no matter how valid the session is.
2. **You do not exchange a session, you read one.** The TestFlight client stores the response of `POST /v1/session/authenticate` in its own CFNetwork cache. One read-only SQL query recovers `sessionId` and `accountId`. No GSA login, no root, no installed root CA, no system proxy.

## Evidence (one channel, one selector, three packages)

| Sample | Source | Encrypted | Decrypted | Cryptid |
| --- | --- | --- | --- | --- |
| A | TestFlight, server-side | 260,225,568 B | 173,156,713 B | `[0]` |
| B | TestFlight, local wrapper | 44,845,042 B | 45,057,814 B | `[0]` |
| C | TestFlight, local wrapper | 56,113,054 B | 56,147,264 B | `[0]` |

All three resolve to the same selector, i.e. the same enrollment model — which is the point: **the decryption step does not know or care which channel produced the package.** Identifiers, selectors and account data in the original measurements were redacted before publication.

## Where to read what

| File | Question it answers |
| --- | --- |
| [docs/01-sources.md](docs/01-sources.md) | Which of the three sources can give me this build, and what does each cost me? |
| [docs/02-session.md](docs/02-session.md) | Where is the session on disk, and why do `dsid` / `AMD-M` / storefront keep failing? |
| [docs/03-install.md](docs/03-install.md) | What exactly does install metadata contain, and why can't I just append a token? |
| [docs/04-sinf.md](docs/04-sinf.md) | Why does this package have no `.sinf`, and what is a selector? |
| [docs/05-decrypt.md](docs/05-decrypt.md) | Why is `sudo` needed once, and why must `setup --app` and `decrypt --ipa` be the same app? |
| [docs/06-verify.md](docs/06-verify.md) | Which three numbers actually prove the binary is plaintext? |
| [docs/07-troubleshooting.md](docs/07-troubleshooting.md) | The message says X; what is really wrong? |
| [docs/08-environment.md](docs/08-environment.md) | fake-ip DNS, user-agent, plist booleans, zip layout, version drift |
| [docs/flow.svg](docs/flow.svg) | The whole decision tree in one picture |
| [SKILL.md](SKILL.md) | Agent-facing form: decision table, stop conditions, failure signatures |

## What is explicitly out of scope

- **No beta seat, no package.** TestFlight is a seat, not a pass: the account must already have access to that beta. App Store is closer to a pass: acquiring the app once is enough for any later download.
- **No Apple Silicon enrollment, no host-side decryption.** An Intel Mac (or a Mac that never signed into the Mac App Store) has no `fpsd` enrollment, so no model can be built. The remaining route needs a jailbroken device to retrieve the 16-byte credential.
- **No selector match, no decryption.** A different selector means a different credential; the failure surfaces as `SINF authentication failed` and there is nothing to tune.
- **Decrypted ≠ installable.** Clearing `cryptid` invalidates the CodeDirectory hash; re-sign before installing.

## Requirements

macOS on Apple Silicon, Python 3.8+ (stdlib only), `curl zip unzip ditto plutil shasum`, a signed-in TestFlight client (or a Mac App Store account for the App Store path). Building the upstream decryption tool needs a C++20 toolchain and Homebrew packages; that build is out of scope here and only sketched in [docs/05-decrypt.md](docs/05-decrypt.md).

## Upstream

This work stands on two MIT-licensed projects and one store client:

- [unfairplay](https://github.com/DrWhax/unfairplay) — host-side FairPlay decryption and enrollment model recovery.
- [apple-auth](https://github.com/apple-auth/apple-auth) — device provisioning, anisette, GrandSlam and Store/TestFlight clients. Notes here reference `v0.1.3`; the local patch needed for Mac sessions is described in [docs/03-install.md](docs/03-install.md) and [docs/08-environment.md](docs/08-environment.md).
- [ipatool](https://github.com/majd/ipatool) — App Store acquisition/download.

No upstream binary is redistributed here.

## Status

Every fact in `docs/` carries its own *last verified* line with the macOS, client and upstream versions used. Facts rot silently; a date makes the rot visible. See [docs/07-troubleshooting.md](docs/07-troubleshooting.md) for the versions currently covered.

## License

MIT — see [LICENSE](LICENSE).
