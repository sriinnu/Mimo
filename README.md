# Mimo

**Who do you want to be today?**

Mimo lives in your menu bar and takes on whoever you need to be for the repo in front of you — work you, personal you, the project-X you. One click, your git identity *(name, email, SSH key, signing key, credential helper)* swaps cleanly. No more accidental commits as the wrong person.

## What it does

- **Identity switching** — Toggle between git profiles from the menu bar. Active profile's name, email, SSH key, and signing config flow straight into `~/.gitconfig`.
- **Per-repo profiles** — Map a folder to a profile via `includeIf`. Walk into `~/work/`, you're work-you; walk into `~/projects/`, you're personal-you. Mimo writes the `includeIf` blocks for you.
- **SSH keys** — Generate, view, copy, and delete keys in `~/.ssh/` without dropping into the terminal. Per-profile host aliases in `~/.ssh/config` are managed for you.
- **Commit signing** — GPG or SSH signing per profile. Mimo finds your keys, wires `commit.gpgSign` / `gpg.format` / `gpg.program`.
- **Credential helpers** — osxkeychain, cache, store, or none — picked per profile.
- **Clone with identity** — Paste a repo URL, Mimo auto-detects the provider (GitHub / Azure DevOps / GitLab / Bitbucket / custom) and clones with the right identity.
- **Repo status at a glance** — Branch, dirty/clean, active profile right there in the menu bar popover.
- **Auto-updates** — Sparkle ships new versions quietly.

## Install

### Homebrew

```bash
brew tap sriinnu/tap
brew install --cask mimo
```

### Manual

Download the latest `.dmg` from [Releases](https://github.com/sriinnu/Mimo/releases), open it, drag **Mimo.app** into **Applications**.

## Security

Mimo's signed releases are notarized by Apple — no Gatekeeper warnings, no malware. If you build from source the binary is unnotarized; right-click → Open the first time.

## Build from source

Mimo is **SwiftUI** + **Tuist**.

```bash
git clone https://github.com/sriinnu/Mimo.git
cd Mimo
tuist generate
open Mimo.xcworkspace
```

Run the `Mimo` scheme.

### Local guardrails

Pre-commit + pre-push hooks (branch validator, secret scanner, `tuist generate` parse check) install with:

```bash
~/Sriinnu/Personal/domain-knowledge/security/hooks/install-guardrails.sh .
```

Re-run after every fresh clone.

## Credit

Forked from [Yefga's Switzy](https://github.com/yefga/Switzy) — rebranded, redesigned, extended. Original MIT license preserved alongside the new one.

## License

MIT — see [LICENSE](LICENSE).

---

Made by [Srinivas Pendela](https://github.com/sriinnu).
