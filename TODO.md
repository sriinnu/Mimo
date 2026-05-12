# Mimo Roadmap

## Phase 1 — Provider Profiles
- [x] 1.1 Create `GitProvider` enum (github, azureDevOps, gitlab, bitbucket, custom)
- [x] 1.2 Add `provider` + `providerURL` fields to `GitProfile` model
- [x] 1.3 Create `ProviderConfigService` — generates `insteadOf` URL rewrites per provider
- [x] 1.4 Wire provider config into `GitConfigService.applyProfile()`
- [x] 1.5 Add provider picker to `ProfileFormView`
- [x] 1.6 Add provider icon/label to `ProfileRowView` and popover rows

## Phase 2 — Per-Repo Profiles (includeIf)
- [x] 2.1 Create `DirectoryProfile` model (directory path → profile ID mapping)
- [x] 2.2 Create `IncludeIfService` — manages `includeIf` blocks in `~/.gitconfig`
- [x] 2.3 Create `DirectoryProfileListView` + `DirectoryProfileFormView`
- [x] 2.4 Add "Directories" tab to `ManagementTab`
- [x] 2.5 Persist directory mappings in UserDefaults
- [x] 2.6 Wire apply/remove directory profiles through AppModel

## Phase 3 — Commit Signing
- [x] 3.1 Add signing fields to `ProfileFormView` (signing key, sign type: GPG/SSH/none)
- [x] 3.2 Extend `GitConfigService.applyProfile()` with `commit.gpgSign`, `gpg.format`, `gpg.program`
- [x] 3.3 Add GPG key scanner service (`gpg --list-secret-keys`)
- [x] 3.4 Add "Signing" tab to `ManagementTab`
- [x] 3.5 Show signing badge on profile rows

## Phase 4 — SSH Config Host Blocks
- [x] 4.1 Create `SSHConfigService` — parse + write `~/.ssh/config` entries
- [x] 4.2 Auto-generate `Host` alias per profile (e.g. `Host github.com-work`)
- [x] 4.3 Add SSH config section to provider profile form
- [x] 4.4 Cleanup stale entries on profile delete

## Phase 5 — Menu Bar Git Status
- [x] 5.1 Create `GitStatusService` — detect current repo, branch, dirty state
- [x] 5.2 Add status section to `MenuBarView` below profile list
- [x] 5.3 Show branch name, dirty/clean indicator, active profile
- [x] 5.4 Poll on popover open (not continuous)

## Phase 6 — Credential Helper Management
- [x] 6.1 Create `CredentialHelperService` — read/write `credential.helper` config
- [x] 6.2 Add credential helper picker to profile form (osxkeychain, cache, store, none)
- [x] 6.3 Wire into `applyProfile()`

## Phase 7 — Clone with Identity
- [x] 7.1 Create `CloneService` — detect provider from URL, pick profile, clone
- [x] 7.2 Add "Clone" button to menu bar popover
- [x] 7.3 Create `CloneView` — URL input + profile pre-selection
- [x] 7.4 Execute `git clone` with correct env (GIT_SSH_COMMAND, etc.)
