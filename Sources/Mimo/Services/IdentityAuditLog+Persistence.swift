//
//  IdentityAuditLog+Persistence.swift
//  Mimo
//
//  File I/O layer extracted from IdentityAuditLog.swift.
//  All disk operations are nonisolated static methods designed to run on
//  Task.detached — they never reach back into main-actor instance state.
//

import Foundation

// MARK: - Serial write actor

/// Serializes all audit-log file I/O so concurrent writes never interleave.
/// Each `write(entry:cap:)` call fully persists and reloads before the next
/// one begins, eliminating the race where a reload can miss a prior write.
actor AuditLogWriter {
    static let shared = AuditLogWriter()

    func write(entry: AuditEntry, cap: Int) async {
        await IdentityAuditLog.persist(entry: entry, cap: cap)
        let loaded = IdentityAuditLog.readAll(cap: cap)
        await MainActor.run {
            IdentityAuditLog.shared.entries = loaded
        }
    }
}

// MARK: - Coders

extension IdentityAuditLog {

    nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Write / Read / Cap

extension IdentityAuditLog {

    nonisolated static func persist(entry: AuditEntry, cap: Int) async {
        let paths = AuditPaths.resolve()
        let fm = FileManager.default

        do {
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

            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

            let handle = try FileHandle(forWritingTo: paths.logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))

            let all = readAll(cap: Int.max)
            if all.count > cap {
                try rewriteCapped(all: all, cap: cap, paths: paths)
            }
        } catch {
            print("[IdentityAuditLog] failed to record entry: \(error.localizedDescription)")
        }
    }

    nonisolated static func readAll(cap: Int) -> [AuditEntry] {
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
    nonisolated static func rewriteCapped(all: [AuditEntry], cap: Int, paths: AuditPaths) throws {
        let kept = Array(all.prefix(cap))
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
    nonisolated static func flagAsReverted(id: UUID, cap: Int) {
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

    /// Rewrite the log without a specific entry. Deleting an entry only
    /// erases the timeline record — the underlying config change Mimo
    /// already made stays. The caller is responsible for confirming.
    nonisolated static func deleteFromLog(id: UUID, cap: Int) {
        let paths = AuditPaths.resolve()
        let all = readAll(cap: Int.max)
        let filtered = all.filter { $0.id != id }
        guard filtered.count != all.count else { return }
        try? rewriteCapped(all: filtered, cap: cap, paths: paths)
    }
}
