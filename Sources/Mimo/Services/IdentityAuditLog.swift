//
//  IdentityAuditLog.swift
//  Mimo
//
//  Mimo's diary. Every config write she makes lands here as one line of
//  JSON in ~/.config/mimo/audit.jsonl. Append-only, mode 600, capped at
//  500 lines so it never grows wild. Reverts themselves get audited —
//  undoing an undo leaves a trail.
//

import Foundation
import Combine

/// Plain, non-isolated value used by background file I/O. The main-actor
/// store hands these out so disk work can run off the main thread without
/// reaching back into actor-isolated state.
struct AuditPaths {
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
    let maxEntries = 500

    /// Mirror of the on-disk log. Most-recent-first ordering — the view
    /// renders straight off this.
    @Published var entries: [AuditEntry] = []

    nonisolated private init() {}

    // MARK: - Recording

    /// Append an entry to the log. Safe to call from any actor — the work
    /// hops to a background queue so we never block the writer.
    ///
    /// Failure is swallowed (printed to console) so a broken disk never
    /// blocks the actual git/ssh write the caller just succeeded at.
    nonisolated func record(_ entry: AuditEntry) {
        let cap = 500
        Task(priority: .utility) {
            await AuditLogWriter.shared.write(entry: entry, cap: cap)
        }
    }

    // MARK: - Loading

    func loadAll() -> [AuditEntry] {
        entries
    }

    /// Re-reads the entire log file into `entries`.
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

    // Revert and persistence logic lives in extension files:
    //   IdentityAuditLog+Revert.swift
    //   IdentityAuditLog+Persistence.swift
}
