//
//  PrecommitHookService.swift
//  Mimo
//
//  The pre-commit guardrail. Mimo can drop a small bash hook into a target
//  git repo that refuses commits when the active git identity doesn't match
//  what Mimo expects for that directory.
//
//  Detection rule: a Mimo hook contains the marker line
//      # Mimo guardrail hook v1
//  Anything else: we refuse to overwrite, refuse to uninstall.
//

import Foundation

enum PrecommitHookError: LocalizedError {
    case notAGitRepo(String)
    case existingNonMimoHook(String)
    case profileNotFound(UUID)
    case writeFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo(let path):
            return "No .git directory found at \(path). Is this a git repository?"
        case .existingNonMimoHook(let path):
            return "There's already a non-Mimo pre-commit hook at \(path). Move it aside first or merge them manually."
        case .profileNotFound(let id):
            return "Profile \(id.uuidString) is not in Mimo's profiles."
        case .writeFailed(let detail):
            return "Couldn't write the hook: \(detail)"
        case .readFailed(let detail):
            return "Couldn't read the hook: \(detail)"
        }
    }
}

@MainActor
final class PrecommitHookService {

    /// Marker line that identifies a Mimo-flavored hook. If a pre-commit hook
    /// already exists and does NOT contain this marker, we refuse to touch it.
    static let markerLine = "# Mimo guardrail hook v1"

    private let fileManager = FileManager.default

    /// Resolve the profile name from AppModel state at call time. The view
    /// passes a closure so the service stays free of UI dependencies.
    typealias ProfileNameLookup = (UUID) -> String?

    // MARK: - Public

    /// Returns whether a Mimo pre-commit hook is installed at this repo path.
    func isInstalled(at repoPath: String) -> Bool {
        let hookPath = hookFilePath(for: repoPath)
        guard fileManager.fileExists(atPath: hookPath) else { return false }
        return isMimoHook(at: hookPath)
    }

    /// Returns the absolute path to the hook script if installed and Mimo-flavored.
    func hookPath(for repoPath: String) -> String? {
        let path = hookFilePath(for: repoPath)
        guard fileManager.fileExists(atPath: path), isMimoHook(at: path) else { return nil }
        return path
    }

    /// Installs the Mimo guardrail hook at `<repoPath>/.git/hooks/pre-commit`.
    ///
    /// - Refuses (throws `.existingNonMimoHook`) if a non-Mimo pre-commit hook
    ///   is already in place.
    /// - Idempotent for Mimo-tagged hooks: re-installing overwrites cleanly.
    ///
    /// `profileName` is the user-facing Mimo profile label ("Personal", "Work"),
    /// embedded into the hook so its error message can name the profile.
    func install(at repoPath: String, profileID: UUID, profileName: String) throws {
        let hooksDir = hooksDirPath(for: repoPath)
        let hookPath = hookFilePath(for: repoPath)

        // Sanity: this must be a git repo.
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: gitDir) else {
            throw PrecommitHookError.notAGitRepo(repoPath)
        }

        // Make sure hooks dir exists (fresh clones may not have it pre-populated).
        if !fileManager.fileExists(atPath: hooksDir) {
            do {
                try fileManager.createDirectory(
                    atPath: hooksDir,
                    withIntermediateDirectories: true
                )
            } catch {
                throw PrecommitHookError.writeFailed(error.localizedDescription)
            }
        }

        // If a hook already exists, only proceed if it's already a Mimo hook.
        if fileManager.fileExists(atPath: hookPath) {
            guard isMimoHook(at: hookPath) else {
                throw PrecommitHookError.existingNonMimoHook(hookPath)
            }
        }

        let script = Self.renderScript(profileID: profileID, profileName: profileName)

        do {
            try script.write(toFile: hookPath, atomically: true, encoding: .utf8)
        } catch {
            throw PrecommitHookError.writeFailed(error.localizedDescription)
        }

        // chmod +x — git won't run it otherwise.
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: hookPath
            )
        } catch {
            throw PrecommitHookError.writeFailed("chmod +x failed: \(error.localizedDescription)")
        }

        print("[Mimo] installed pre-commit guardrail at \(hookPath)")
    }

    /// Removes the Mimo hook. Refuses (throws `.existingNonMimoHook`) if the
    /// hook is non-Mimo, so we never wipe a user's own script.
    func uninstall(at repoPath: String) throws {
        let hookPath = hookFilePath(for: repoPath)
        guard fileManager.fileExists(atPath: hookPath) else { return }
        guard isMimoHook(at: hookPath) else {
            throw PrecommitHookError.existingNonMimoHook(hookPath)
        }
        do {
            try fileManager.removeItem(atPath: hookPath)
        } catch {
            throw PrecommitHookError.writeFailed(error.localizedDescription)
        }
        print("[Mimo] removed pre-commit guardrail at \(hookPath)")
    }

    // MARK: - Path helpers

    private func hooksDirPath(for repoPath: String) -> String {
        ((repoPath as NSString)
            .appendingPathComponent(".git") as NSString)
            .appendingPathComponent("hooks")
    }

    private func hookFilePath(for repoPath: String) -> String {
        (hooksDirPath(for: repoPath) as NSString).appendingPathComponent("pre-commit")
    }

    private func isMimoHook(at path: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return content.contains(Self.markerLine)
    }

    // MARK: - Hook script

    /// The hook script template. Two placeholders get interpolated at install:
    ///   __MIMO_EXPECTED_PROFILE_NAME__
    ///   __MIMO_EXPECTED_PROFILE_ID__
    /// Everything else is static POSIX bash — runs without Mimo, runs on any
    /// user's machine, only depends on `git` being on PATH.
    nonisolated static func renderScript(profileID: UUID, profileName: String) -> String {
        // Single-quote-escape the profile name for safe bash interpolation.
        let safeName = profileName.replacingOccurrences(of: "'", with: "'\\''")
        return scriptTemplate
            .replacingOccurrences(of: "__MIMO_EXPECTED_PROFILE_NAME__", with: safeName)
            .replacingOccurrences(of: "__MIMO_EXPECTED_PROFILE_ID__", with: profileID.uuidString)
    }

    nonisolated private static let scriptTemplate: String = #"""
#!/usr/bin/env bash
# Mimo guardrail hook v1
# Refuses commits when the active git identity doesn't match what Mimo
# expects for this directory. Works even when Mimo isn't running — it only
# reads files. Safe to remove with `rm .git/hooks/pre-commit` or via Mimo.

set -e

MIMO_EXPECTED_PROFILE_NAME='__MIMO_EXPECTED_PROFILE_NAME__'
MIMO_EXPECTED_PROFILE_ID='__MIMO_EXPECTED_PROFILE_ID__'

MIMO_PROFILES_DIR="$HOME/.config/mimo/profiles"
MIMO_GITCONFIG="$HOME/.gitconfig"

# If Mimo's state isn't on this machine at all, don't block. The hook was
# probably installed via a checkout from another machine — let the commit
# through rather than holding it hostage.
if [ ! -d "$MIMO_PROFILES_DIR" ] && [ ! -f "$MIMO_GITCONFIG" ]; then
  exit 0
fi

# ANSI colors — only when stderr is a TTY, so CI logs stay clean.
if [ -t 2 ]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=''; YEL=''; DIM=''; BOLD=''; RST=''
fi

# Active identity — what git is about to commit as.
ACTIVE_EMAIL=$(git config user.email 2>/dev/null || echo "")
ACTIVE_NAME=$(git config user.name 2>/dev/null || echo "")

# Repo root, used to find the right includeIf entry in ~/.gitconfig.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# Find the expected profile gitconfig path. Strategy:
#   1) Scan ~/.gitconfig for `[includeIf "gitdir:..."]` whose path is a
#      prefix of REPO_ROOT. Take its `path = ...` value.
#   2) Fall back to ~/.config/mimo/profiles/<expected-uuid>.gitconfig — the
#      profile this hook was installed for.
EXPECTED_CONFIG=""

if [ -f "$MIMO_GITCONFIG" ] && [ -n "$REPO_ROOT" ]; then
  # Normalize REPO_ROOT to end with a slash for prefix matching.
  REPO_ROOT_SLASH="${REPO_ROOT%/}/"

  current_condition=""
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    # Trim leading whitespace.
    line="${raw_line#"${raw_line%%[![:space:]]*}"}"

    case "$line" in
      '[includeIf "gitdir:'*'"]')
        # Strip the wrapper to get the gitdir glob.
        gd="${line#'[includeIf "gitdir:'}"
        gd="${gd%'"]'}"
        # Drop trailing slash — we'll prefix-match the slashy form below.
        case "$gd" in
          */) current_condition="$gd" ;;
          *)  current_condition="${gd}/" ;;
        esac
        ;;
      path\ =\ *|path=*)
        # Extract the path value.
        p="${line#path}"
        p="${p# }"
        p="${p#=}"
        p="${p# }"
        # Expand a leading ~ to $HOME.
        case "$p" in
          '~/'*) p="$HOME/${p#'~/'}" ;;
          '~')   p="$HOME" ;;
        esac
        if [ -n "$current_condition" ]; then
          case "$REPO_ROOT_SLASH" in
            "$current_condition"*)
              EXPECTED_CONFIG="$p"
              ;;
          esac
          current_condition=""
        fi
        ;;
      '['*)
        # Any other section header resets the includeIf context.
        current_condition=""
        ;;
    esac
  done < "$MIMO_GITCONFIG"
fi

# Fallback: use the profile UUID baked into this hook at install time.
if [ -z "$EXPECTED_CONFIG" ] && [ -f "$MIMO_PROFILES_DIR/$MIMO_EXPECTED_PROFILE_ID.gitconfig" ]; then
  EXPECTED_CONFIG="$MIMO_PROFILES_DIR/$MIMO_EXPECTED_PROFILE_ID.gitconfig"
fi

# If we can't find an expected config, Mimo hasn't claimed this repo. Let it
# through rather than guess.
if [ -z "$EXPECTED_CONFIG" ] || [ ! -f "$EXPECTED_CONFIG" ]; then
  exit 0
fi

# Pull `email = ...` out of the per-profile gitconfig. Tolerate tabs/spaces.
EXPECTED_EMAIL=""
while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  case "$line" in
    email\ =\ *|email=*)
      v="${line#email}"
      v="${v# }"
      v="${v#=}"
      v="${v# }"
      EXPECTED_EMAIL="$v"
      break
      ;;
  esac
done < "$EXPECTED_CONFIG"

if [ -z "$EXPECTED_EMAIL" ]; then
  # Nothing to compare against — don't block.
  exit 0
fi

# Compare. If it matches, we're good.
if [ "$ACTIVE_EMAIL" = "$EXPECTED_EMAIL" ]; then
  exit 0
fi

# Mismatch — block the commit with a friendly, Mimo-flavored message.
{
  printf "%s\n" ""
  printf "%s%sMimo guardrail: wrong git identity for this repo.%s\n" "$RED" "$BOLD" "$RST"
  printf "%s  active:  %s <%s>%s\n"   "$DIM" "${ACTIVE_NAME:-?}" "${ACTIVE_EMAIL:-?}" "$RST"
  printf "%s  expected: %s <%s>%s\n"  "$DIM" "$MIMO_EXPECTED_PROFILE_NAME" "$EXPECTED_EMAIL" "$RST"
  printf "\n"
  printf "%sOpen Mimo and click %s%s%s to switch, then commit again.%s\n" \
    "$YEL" "$BOLD" "$MIMO_EXPECTED_PROFILE_NAME" "$RST$YEL" "$RST"
  printf "%s(to bypass: git commit --no-verify — but don't.)%s\n" "$DIM" "$RST"
  printf "\n"
} 1>&2

exit 1
"""#
}
