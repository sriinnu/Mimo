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
        }
    }

    private func buildBlock(for profile: GitProfile, provider: GitProvider, allProfiles: [GitProfile]) -> String {
        let providerProfiles = allProfiles.filter { $0.provider == provider }
        let host: String
        if providerProfiles.count <= 1 {
            host = provider.defaultHost
        } else {
            host = "\(provider.defaultHost)-\(profile.name.lowercased().replacingOccurrences(of: " ", with: "-"))"
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

    private func readContent() throws -> String {
        try String(contentsOfFile: sshConfigPath, encoding: .utf8)
    }

    private func writeContent(_ content: String) throws {
        try content.write(toFile: sshConfigPath, atomically: true, encoding: .utf8)
    }

    private func extractBlock(for id: UUID, from content: String) -> String? {
        let tag = marker(for: id)
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
        try ensureConfigExists()
        let block = buildBlock(for: profile, provider: provider, allProfiles: allProfiles)
        var content = try readContent()
        if let existing = extractBlock(for: profile.id, from: content) {
            content = content.replacingOccurrences(of: existing, with: block)
        } else {
            content += "\n\n\(block)"
        }
        try writeContent(content)
    }

    func removeHostBlock(for profile: GitProfile) throws {
        var content = try readContent()
        guard let block = extractBlock(for: profile.id, from: content) else { return }
        content = content.replacingOccurrences(of: block, with: "")
        try writeContent(content.collapsingBlankLines())
    }

    func removeAllHostBlocks() throws {
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
        try writeContent(filtered.joined(separator: "\n").collapsingBlankLines())
    }
}

private extension String {
    func collapsingBlankLines() -> String {
        replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
