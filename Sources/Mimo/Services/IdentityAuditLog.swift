//
//  IdentityAuditLog.swift
//  Mimo
//
//  Mimo's diary. Every config write she makes lands here as one line of
//  JSON in ~/.config/mimo/audit.jsonl. Append-only, mode 600, capped at
//  500 lines so it never grows wild. Reverts themselves get audited —
//  undoing an undo leaves a trail.
//
//  Two design choices worth flagging:
//
//  1. Logging is best-effort. If the disk's full or the file is locked,
//     the original git/ssh write must still succeed. We catch and print;
//     we never propagate.
//
//  2. Reverts are surfaced as new audit entries (with the inverse summary)
//     rather than mutating the original row. The original keeps its
//     `isReverted = true` flag so the UI can strike it through, but the
//     history stays append-only.
//

import Foundation
import Combine

/// Plain, non-isolated value used by background file I/O. The main-actor
/// store hands these out so disk work can run off the main thread without
/// reaching back into actor-isolated state.
private struct AuditPaths {
    let configDir: URL
    let logURL: URL

    static func resolve() -> AuditPaths {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mimo")
        return AuditPaths(
            configDir: dir,
            logURL: dir.appendingPathComponent("audit.jsonl")
        )
    }
}

@MainActor
final class IdentityAuditLog: ObservableObject {

    nonisolated(unsafe) static let shared = IdentityAuditLog()

    /// Soft cap. The newest 500 entries are kept; older ones drop off the
    /// bottom of the file on every write.
    private let maxEntries = 500

    /// Mirror of the on-disk log. Most-recent-first ordering — the view
    /// renders straight off this.
    @Published private(set) var entries: [AuditEntry] = []

    nonisolated private init() {}

    // MARK: - Recording

    /// Append an entry to the log. Safe to call from any actor — the work
    /// hops to a background queue so we never block the writer.
    ///
    /// Failure is swallowed (printed to console) so a broken disk never
    /// blocks the actual git/ssh write the caller just succeeded at.
    nonisolated func record(_ entry: AuditEntry) {
        let cap = 500
        Task.detached(priority: .utility) {
            await Self.persist(entry: entry, cap: cap)
            let loaded = Self.readAll(cap: cap)
            await MainActor.run {
                IdentityAuditLog.shared.entries = loaded
            }
        }
    }

    // MARK: - Loading

    func loadAll() -> [AuditEntry] {
        entries
    }

    /// Re-reads the entire log file into `entries`. Cheap relative to the
    /// 500-entry cap, expensive enough that we don't do it on every render
    /// — we do it once on launch and after every write.
    func reload() async {
        let cap = maxEntries
        let loaded = await Task.detached(priority: .utility) {
            Self.readAll(cap: cap)
        }.value
        entries = loaded
    }

    // MARK: - Clear

    func clear() {
        let paths = AuditPaths.resolve()
        do {
            if FileManager.default.fileExists(atPath: paths.logURL.path) {
                try FileManager.default.removeItem(at: paths.logURL)
            }
            entries = []
        } catch {
            print("[IdentityAuditLog] failed to clear log: \(error.localizedDescription)")
        }
    }

    // MARK: - Revert

    enum RevertError: LocalizedError {
        case alreadyReverted
        case unsupportedScope
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyReverted: return "This change was already undone."
            case .unsupportedScope: return "Mimo can't undo this kind of change yet."
            case .failed(let detail): return "Couldn't undo: \(detail)"
            }
        }
    }

    /// Apply the reverse of `entry`. Returns the *revert* as a new
    /// AuditEntry so the history captures the undo.
    ///
    /// Sequence note: reverts are independent — we don't check whether a
    /// later entry depended on this one. If the user reverts step N and
    /// step N+1 set the same key to something else, N+1 wins on disk and
    /// the revert is effectively a no-op visually. The UI surfaces both
    /// rows so they can choose which to undo first.
    func revert(_ entry: AuditEntry) async throws -> AuditEntry {
        if entry.isReverted { throw RevertError.alreadyReverted }

        let revertSummary: String
        let revertBefore = entry.after
        let revertAfter = entry.before

        do {
            switch entry.scope {
            case .gitConfigGlobal:
                try await revertGitConfigGlobal(entry)
                revertSummary = describeRevert(key: entry.configKey, before: entry.before, after: entry.after)

            case .gitConfigRepo(let repoPath):
                try await revertGitConfigRepo(entry, repoPath: repoPath)
                revertSummary = describeRevert(key: entry.configKey, before: entry.before, after: entry.after)

            case .sshConfig:
                try await revertSSHConfig(entry)
                revertSummary = "restored SSH config"

            case .mimoProfiles:
                try await revertMimoProfiles(entry)
                revertSummary = "restored profile file"
            }
        } catch let err as RevertError {
            throw err
        } catch {
            throw RevertError.failed(error.localizedDescription)
        }

        // Mark original as reverted — rewrite the log so the older row's
        // isReverted reflects new state (still append-only conceptually;
        // the original ID is preserved, only the flag flips).
        let cap = maxEntries
        await Task.detached(priority: .utility) {
            Self.flagAsReverted(id: entry.id, cap: cap)
        }.value

        let revertEntry = AuditEntry(
            profileID: entry.profileID,
            profileName: entry.profileName,
            scope: entry.scope,
            path: entry.path,
            summary: revertSummary,
            before: revertBefore,
            after: revertAfter,
            isReverted: false,
            configKey: entry.configKey
        )

        await Task.detached(priority: .utility) {
            await Self.persist(entry: revertEntry, cap: cap)
        }.value

        let loaded = await Task.detached(priority: .utility) {
            Self.readAll(cap: cap)
        }.value
        entries = loaded

        return revertEntry
    }

    private func describeRevert(key: String, before: String?, after: String?) -> String {
        // We're undoing — so "after" was the post-write state, and
        // "before" is what we want to restore.
        switch (before, after) {
        case (nil, _?):
            return "undid \(key) — restored to unset"
        case (let old?, nil):
            return "undid \(key) — restored to \(old)"
        case (let old?, let new?):
            return old == new
                ? "undid \(key) (no-op)"
                : "undid \(key) — restored \(old)"
        case (nil, nil):
            return "undid \(key)"
        }
    }

    // MARK: - Revert implementations

    private func revertGitConfigGlobal(_ entry: AuditEntry) async throws {
        let shell = ShellService()
        let key = entry.configKey
        guard !key.isEmpty else { throw RevertError.unsupportedScope }

        if let before = entry.before {
            _ = try await shell.run("git", arguments: ["config", "--global", key, before])
        } else {
            // Wasn't there before — unset it. Some keys may not exist after
            // the original write (e.g. it was already a no-op); ignore
            // exit-5 ("not set") by not throwing if unset fails.
            _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", key])
        }
    }

    private func revertGitConfigRepo(_ entry: AuditEntry, repoPath: String) async throws {
        let shell = ShellService()
        let key = entry.configKey
        guard !key.isEmpty else { throw RevertError.unsupportedScope }
        let configFile = (repoPath as NSString).appendingPathComponent(".git/config")

        if let before = entry.before {
            _ = try await shell.run("git", arguments: ["config", "-f", configFile, key, before])
        } else {
            _ = try? await shell.run("git", arguments: ["config", "-f", configFile, "--unset", key])
        }
    }

    private func revertSSHConfig(_ entry: AuditEntry) async throws {
        let sshPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config").path

        if let before = entry.before {
            try before.write(toFile: sshPath, atomically: true, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: sshPath) {
            // Didn't exist before — remove it.
            try FileManager.default.removeItem(atPath: sshPath)
        }
    }

    private func revertMimoProfiles(_ entry: AuditEntry) async throws {
        // path holds the per-profile include file. before/after = file contents.
        guard let path = entry.path else { throw RevertError.unsupportedScope }

        if let before = entry.before {
            try before.write(toFile: path, atomically: true, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Disk I/O (background, non-isolated)
    //
    // These run on Task.detached. They mustn't touch instance state — all
    // file paths are re-derived through AuditPaths.resolve() so we never
    // reach back into the main-actor.

    nonisolated(unsafe) private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private nonisolated static func persist(entry: AuditEntry, cap: Int) async {
        let paths = AuditPaths.resolve()
        let fm = FileManager.default

        do {
            // Ensure dir + file with 600 perms.
            if !fm.fileExists(atPath: paths.configDir.path) {
                try fm.createDirectory(
                    at: paths.configDir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            if !fm.fileExists(atPath: paths.logURL.path) {
                fm.createFile(
                    atPath: paths.logURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            } else {
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.logURL.path)
            }

            // Append.
            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

            let handle = try FileHandle(forWritingTo: paths.logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))

            // Cap.
            let all = readAll(cap: Int.max)
            if all.count > cap {
                try rewriteCapped(all: all, cap: cap, paths: paths)
            }
        } catch {
            print("[IdentityAuditLog] failed to record entry: \(error.localizedDescription)")
        }
    }

    private nonisolated static func readAll(cap: Int) -> [AuditEntry] {
        let paths = AuditPaths.resolve()
        let fm = FileManager.default

        guard fm.fileExists(atPath: paths.logURL.path) else { return [] }
        guard let content = try? String(contentsOfFile: paths.logURL.path, encoding: .utf8) else { return [] }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        var parsed: [AuditEntry] = []
        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            if let entry = try? decoder.decode(AuditEntry.self, from: data) {
                parsed.append(entry)
            }
        }
        parsed.sort { $0.timestamp > $1.timestamp }
        if parsed.count > cap {
            parsed = Array(parsed.prefix(cap))
        }
        return parsed
    }

    /// Atomically rewrite the log keeping only the most recent N entries.
    private nonisolated static func rewriteCapped(all: [AuditEntry], cap: Int, paths: AuditPaths) throws {
        let kept = Array(all.prefix(cap))
        // Reverse so the file stores oldest-first (matches append order).
        let ordered = Array(kept.reversed())
        var buf = ""
        for e in ordered {
            let data = try encoder.encode(e)
            if let line = String(data: data, encoding: .utf8) {
                buf.append(line)
                buf.append("\n")
            }
        }
        try buf.write(toFile: paths.logURL.path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.logURL.path
        )
    }

    /// Rewrite the log marking a specific entry's `isReverted = true`.
    private nonisolated static func flagAsReverted(id: UUID, cap: Int) {
        let paths = AuditPaths.resolve()
        let all = readAll(cap: Int.max)
        var didChange = false
        let updated: [AuditEntry] = all.map { entry in
            if entry.id == id, !entry.isReverted {
                didChange = true
                return AuditEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    profileID: entry.profileID,
                    profileName: entry.profileName,
                    scope: entry.scope,
                    path: entry.path,
                    summary: entry.summary,
                    before: entry.before,
                    after: entry.after,
                    isReverted: true,
                    configKey: entry.configKey
                )
            }
            return entry
        }
        guard didChange else { return }
        try? rewriteCapped(all: updated, cap: cap, paths: paths)
    }
}
