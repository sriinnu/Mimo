//
//  SSHConfigService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 12/05/2026
//

import Foundation

struct SSHConfigEntry: Identifiable, Equatable {
    var id: UUID
    var host: String
    var hostName: String
    var identityFile: String
    var user: String
}

enum SSHConfigError: LocalizedError {
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let detail): "Failed to read SSH config: \(detail)"
        case .writeFailed(let detail): "Failed to write SSH config: \(detail)"
        }
    }
}

actor SSHConfigService {

    private var sshConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config").path
    }

    private func marker(for id: UUID) -> String { "# Mimo:\(id.uuidString)" }

    private func ensureConfigExists() throws {
        let dir = (sshConfigPath as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if !fm.fileExists(atPath: sshConfigPath) {
            try "".write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sshConfigPath)
        }
    }

    private func buildBlock(for profile: GitProfile, provider: GitProvider, allProfiles: [GitProfile]) -> String {
        let providerProfiles = allProfiles.filter { $0.provider == provider }
        let host: String
        if providerProfiles.count <= 1 {
            host = provider.defaultHost
        } else {
            let suffix = String(profile.id.uuidString.prefix(4))
            // Slug the profile name so a newline / `#` / space can't break out
            // of the Host line and corrupt the rest of ~/.ssh/config.
            host = "\(provider.defaultHost)-\(Self.hostSlug(for: profile.name))-\(suffix)"
        }
        let key = profile.sshKeyPath ?? ""
        return """
        \(marker(for: profile.id))
        Host \(host)
            HostName \(provider.defaultHost)
            IdentityFile \(key)
            User git
        """
    }

    /// Reduce an arbitrary profile name to a hostname-safe slug: lowercase
    /// alphanumerics + dashes, collapsed and trimmed. Falls back to "profile"
    /// if the name is entirely unsafe. Visible to tests.
    static func hostSlug(for name: String) -> String {
        var slug = String(name.lowercased().unicodeScalars.compactMap { scalar -> Character? in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "profile" : slug
    }

    private func readContent() throws -> String {
        try String(contentsOfFile: sshConfigPath, encoding: .utf8)
    }

    /// Returns nil if the file doesn't exist — used for audit before-state.
    private func readContentOrNil() -> String? {
        guard FileManager.default.fileExists(atPath: sshConfigPath) else { return nil }
        return try? readContent()
    }

    private func writeContent(_ content: String) throws {
        try content.write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: sshConfigPath
        )
    }

    /// Visible to tests via `@testable import`.
    static func extractBlock(for id: UUID, from content: String) -> String? {
        let tag = "# Mimo:\(id.uuidString)"
        let lines = content.components(separatedBy: .newlines)
        guard let startIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == tag }) else { return nil }
        var endIdx = startIdx + 1
        while endIdx < lines.count {
            let trimmed = lines[endIdx].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { break }
            endIdx += 1
        }
        return lines[startIdx..<endIdx].joined(separator: "\n")
    }

    private func extractBlock(for id: UUID, from content: String) -> String? {
        Self.extractBlock(for: id, from: content)
    }

    /// Remove a marker-identified block from arbitrary config content. Visible to tests.
    static func removeBlock(for id: UUID, from content: String) -> String {
        guard let block = extractBlock(for: id, from: content) else { return content }
        return content.replacingOccurrences(of: block, with: "")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Parse host entries from arbitrary config content. Visible to tests.
    static func parseConfig(_ content: String) -> [(host: String, hostName: String)] {
        let lines = content.components(separatedBy: .newlines)
        var results: [(String, String)] = []
        var cur: (host: String, hostName: String)?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Host ") {
                if let c = cur { results.append(c) }
                let hostPattern = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if hostPattern == "*" || hostPattern.contains("*") { cur = nil; continue }
                cur = (host: hostPattern, hostName: "")
            } else if cur != nil {
                let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                if parts[0].lowercased() == "hostname" { cur?.hostName = parts[1] }
            }
        }
        if let c = cur { results.append(c) }
        return results
    }

    func readConfig() throws -> [SSHConfigEntry] {
        let content = try readContent()
        let lines = content.components(separatedBy: .newlines)
        var entries: [SSHConfigEntry] = []
        var cur: (host: String, hostName: String, identityFile: String, user: String)?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Host ") {
                if let c = cur { entries.append(.init(id: UUID(), host: c.host, hostName: c.hostName, identityFile: c.identityFile, user: c.user)) }
                cur = (host: String(trimmed.dropFirst(5)), hostName: "", identityFile: "", user: "")
            } else if cur != nil {
                let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0].lowercased() {
                case "hostname": cur?.hostName = parts[1]
                case "identityfile": cur?.identityFile = parts[1]
                case "user": cur?.user = parts[1]
                default: break
                }
            }
        }
        if let c = cur { entries.append(.init(id: UUID(), host: c.host, hostName: c.hostName, identityFile: c.identityFile, user: c.user)) }
        return entries
    }

    func applyHostBlock(for profile: GitProfile, provider: GitProvider, allProfiles: [GitProfile]) throws {
        // Refuse to write a host block when inputs would yield empty Host
        // or IdentityFile lines — SSH treats those as parse errors and
        // refuses the whole config. If a stale block already exists for
        // this profile, scrub it so the file doesn't keep a broken trace.
        let keyPath = (profile.sshKeyPath ?? "").trimmingCharacters(in: .whitespaces)
        let providerHost = provider.defaultHost.trimmingCharacters(in: .whitespaces)
        guard !keyPath.isEmpty, !providerHost.isEmpty else {
            try? removeHostBlock(for: profile)
            return
        }

        // Snapshot before for audit. Captures whole-file state so revert
        // can restore it verbatim — block-level diffs are too fragile here
        // (ordering, neighboring blocks, whitespace).
        let beforeSnapshot = readContentOrNil()

        try ensureConfigExists()
        let block = buildBlock(for: profile, provider: provider, allProfiles: allProfiles)
        var content = try readContent()
        if let existing = extractBlock(for: profile.id, from: content) {
            content = content.replacingOccurrences(of: existing, with: block)
        } else {
            content += "\n\n\(block)"
        }
        try writeContent(content)

        recordAudit(
            profile: profile,
            summary: "added SSH host block for \(provider.defaultHost)",
            before: beforeSnapshot,
            after: content
        )
    }

    func removeHostBlock(for profile: GitProfile) throws {
        let beforeSnapshot = readContentOrNil()

        var content = try readContent()
        guard let block = extractBlock(for: profile.id, from: content) else { return }
        content = content.replacingOccurrences(of: block, with: "")
        let final = content.collapsingBlankLines()
        try writeContent(final)

        recordAudit(
            profile: profile,
            summary: "removed SSH host block",
            before: beforeSnapshot,
            after: final
        )
    }

    func removeAllHostBlocks() throws {
        let beforeSnapshot = readContentOrNil()

        try ensureConfigExists()
        let lines = try readContent().components(separatedBy: .newlines)
        var filtered: [String] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# Mimo:") {
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty || t.hasPrefix("#") { break }
                    i += 1
                }
            } else {
                filtered.append(lines[i])
                i += 1
            }
        }
        let final = filtered.joined(separator: "\n").collapsingBlankLines()
        try writeContent(final)

        // No specific profile — record under a synthetic system entry.
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: nil,
                profileName: "Mimo",
                scope: .sshConfig,
                path: sshConfigPath,
                summary: "cleared all Mimo SSH host blocks",
                before: beforeSnapshot,
                after: final
            )
        )
    }

    private func recordAudit(profile: GitProfile, summary: String, before: String?, after: String?) {
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: profile.id,
                profileName: profile.name,
                scope: .sshConfig,
                path: sshConfigPath,
                summary: summary,
                before: before,
                after: after
            )
        )
    }
}

private extension String {
    func collapsingBlankLines() -> String {
        var s = self
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
