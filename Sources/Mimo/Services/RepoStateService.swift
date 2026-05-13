//
//  RepoStateService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 13/05/2026.
//
//  Foundation service that publishes a snapshot of the foreground app's
//  working-directory + git context. Powers (future) auto-detect mismatch
//  warnings, mascot wince on wrong identity, and identity-narration tooltips.
//
//  Permission note: on first foreground-detection of Terminal.app, iTerm2,
//  Finder, or Xcode, macOS will prompt the user to grant Mimo *Automation*
//  permission for that app. Until granted, those probes silently return nil
//  and Mimo simply reports `cwd = nil` for that app. No crash, no nag.
//

import AppKit
import Combine
import Foundation

// MARK: - Published State

struct ForegroundRepoState: Equatable {
    var cwd: URL?
    var repoRoot: URL?
    var branch: String?
    var isDirty: Bool
    var expectedProfileID: UUID?
    var activeProfileID: UUID?

    var hasMismatch: Bool {
        expectedProfileID != nil && expectedProfileID != activeProfileID
    }

    static let empty = ForegroundRepoState(
        cwd: nil,
        repoRoot: nil,
        branch: nil,
        isDirty: false,
        expectedProfileID: nil,
        activeProfileID: nil
    )
}

// MARK: - Service

@MainActor
final class RepoStateService: ObservableObject {

    // MARK: Published

    @Published private(set) var state: ForegroundRepoState = .empty

    // MARK: Tuning

    /// Polling cadence. Spec: between 2s and 5s; default 3s.
    private let pollInterval: TimeInterval = 3.0

    // MARK: Dependencies

    private let foreground = ForegroundCWDDetector()
    private let gitStatus = GitStatusService()

    // MARK: Inputs (snapshot of AppModel)

    /// Latest directory mappings (longest-prefix-match against cwd).
    private var directoryProfiles: [DirectoryProfile] = []
    /// Latest active profile id.
    private var activeProfileID: UUID?

    // MARK: Internal

    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    deinit {
        pollTask?.cancel()
    }

    /// Start observing `appModel` and begin the poll loop.
    /// Call once from `AppDelegate.applicationDidFinishLaunching`.
    func start(observing appModel: AppModel) {
        // Mirror inputs we need for matching.
        appModel.$directoryProfiles
            .sink { [weak self] in self?.directoryProfiles = $0 }
            .store(in: &cancellables)

        appModel.$activeProfileID
            .sink { [weak self] in self?.activeProfileID = $0 }
            .store(in: &cancellables)

        // Push our state changes back into AppModel.
        $state
            .removeDuplicates()
            .sink { [weak appModel] newState in
                appModel?.foregroundRepoState = newState
            }
            .store(in: &cancellables)

        // Fire an immediate refresh, then start the poll loop.
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        cancellables.removeAll()
    }

    // MARK: Core refresh

    /// One poll cycle. Detects cwd, resolves git context, computes mismatch.
    /// Cheap when nothing changed (a couple of stat()s plus one git call).
    private func refresh() async {
        // 1. Foreground cwd (off-main via actor).
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let cwdString = await foreground.cwd(forBundleID: frontBundleID, pid: frontPID)
        let cwdURL = cwdString.map { URL(fileURLWithPath: $0) }

        // 2. Git context.
        var repoRoot: URL?
        var branch: String?
        var isDirty = false

        if let cwdString {
            if let root = await gitStatus.findGitRepo(in: cwdString) {
                repoRoot = URL(fileURLWithPath: root)
                let status = await gitStatus.status(for: root)
                branch = status.branch
                isDirty = status.isDirty
            }
        }

        // 3. Expected profile (longest-prefix match on either cwd or repoRoot).
        let probePath = repoRoot?.path ?? cwdURL?.path
        let expected = probePath.flatMap { Self.expectedProfile(for: $0, in: directoryProfiles) }

        // 4. Publish.
        let next = ForegroundRepoState(
            cwd: cwdURL,
            repoRoot: repoRoot,
            branch: branch,
            isDirty: isDirty,
            expectedProfileID: expected,
            activeProfileID: activeProfileID
        )
        if next != state {
            state = next
        }
    }

    // MARK: Matching

    /// Longest-prefix match. A mapping of `~/work` matches `~/work/repo-a/foo`
    /// but not `~/work-stuff/foo`. Tilde-expanded; case-sensitive (HFS+/APFS-tolerant).
    static func expectedProfile(
        for path: String,
        in mappings: [DirectoryProfile]
    ) -> UUID? {
        let target = (path as NSString).standardizingPath
        var best: (depth: Int, profileID: UUID)?

        for mapping in mappings {
            let expanded = (mapping.directoryPath as NSString).expandingTildeInPath
            let normalized = (expanded as NSString).standardizingPath
            let prefix = normalized.hasSuffix("/") ? normalized : normalized + "/"
            let targetWithSlash = target.hasSuffix("/") ? target : target + "/"

            guard targetWithSlash == prefix || targetWithSlash.hasPrefix(prefix) else { continue }

            let depth = normalized.split(separator: "/").count
            if best == nil || depth > best!.depth {
                best = (depth, mapping.profileID)
            }
        }
        return best?.profileID
    }
}

// MARK: - Foreground CWD Detection

/// Pure I/O actor: takes the foreground app's bundle id / pid and returns its
/// "current working directory" if we know how to ask. Handles Terminal.app,
/// iTerm2, Finder, and Xcode. Everything else returns nil.
///
/// Terminal-cwd resolution uses AppleScript to read TTY/path metadata, then
/// (for Terminal.app) a tiny `lsof` shell-out to map TTY → shell pid → cwd.
/// All work happens here, off the main thread.
actor ForegroundCWDDetector {

    func cwd(forBundleID bundleID: String?, pid: pid_t?) async -> String? {
        guard let bundleID else { return nil }

        switch bundleID {
        case "com.apple.Terminal":
            return terminalAppCWD()
        case "com.googlecode.iterm2":
            return iTerm2CWD()
        case "com.apple.finder":
            return finderCWD()
        case "com.apple.dt.Xcode":
            return xcodeCWD()
        default:
            // Best-effort terminals that expose cwd via AppleScript variables.
            // Warp / Ghostty / Alacritty / kitty don't have a stable
            // AppleScript surface for this — punt.
            return nil
        }
    }

    // MARK: Terminal.app

    /// Terminal.app exposes the front window's TTY device path. We resolve
    /// that to a shell pid via `lsof`, then read the shell's cwd via `lsof -d cwd`.
    private func terminalAppCWD() -> String? {
        let ttyScript = """
        tell application "Terminal"
            if (count of windows) is 0 then return ""
            return tty of selected tab of front window
        end tell
        """
        guard
            let tty = runAppleScript(ttyScript)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !tty.isEmpty
        else { return nil }

        // tty → foreground process pid → cwd
        guard let pidStr = runProcess(
            "/usr/sbin/lsof",
            args: ["-t", tty]
        )?.split(separator: "\n").last.map(String.init),
              let pid = Int(pidStr.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        return cwdOfPID(pid)
    }

    /// `lsof -a -d cwd -p <pid> -F n` → "p<pid>\nn<cwd>"
    private func cwdOfPID(_ pid: Int) -> String? {
        guard let out = runProcess(
            "/usr/sbin/lsof",
            args: ["-a", "-d", "cwd", "-p", String(pid), "-F", "n"]
        ) else { return nil }
        for line in out.components(separatedBy: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    // MARK: iTerm2

    /// iTerm2 exposes `path` directly on the current session.
    private func iTerm2CWD() -> String? {
        let script = """
        tell application "iTerm2"
            if (count of windows) is 0 then return ""
            tell current session of current window
                return variable named "session.path"
            end tell
        end tell
        """
        let path = runAppleScript(script)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    // MARK: Finder

    /// Finder's front window target as a POSIX path. Returns nil for the
    /// desktop or when no window is open.
    private func finderCWD() -> String? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        let path = runAppleScript(script)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    // MARK: Xcode

    /// Xcode's active workspace document path. Falls back to the folder of
    /// that path so the git lookup walks up from a directory, not a file.
    private func xcodeCWD() -> String? {
        let script = """
        tell application "Xcode"
            if (count of workspace documents) is 0 then return ""
            return path of active workspace document
        end tell
        """
        guard let raw = runAppleScript(script)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        let url = URL(fileURLWithPath: raw)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? url.path : url.deletingLastPathComponent().path
    }

    // MARK: AppleScript / Process helpers

    /// Runs the given AppleScript synchronously. Returns the result's string
    /// value or nil on any error (including denied automation permission).
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if errorDict != nil { return nil }
        return descriptor.stringValue
    }

    /// Runs a process synchronously and returns trimmed stdout. We don't use
    /// `ShellService` here because we want fixed absolute paths (`/usr/sbin/lsof`)
    /// rather than `/usr/bin/env` lookup — these are bundle-stable on macOS.
    private func runProcess(_ executable: String, args: [String]) -> String? {
        let process = Process()
        let outPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
