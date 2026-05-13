//
//  IncludeIfService.swift
//  Mimo
//

import Foundation

enum IncludeIfError: LocalizedError {
    case gitconfigNotFound
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitconfigNotFound:
            return "Could not locate ~/.gitconfig."
        case .writeFailed(let detail):
            return "Failed to update gitconfig: \(detail)"
        }
    }
}

actor IncludeIfService {

    private let fileManager = FileManager.default

    private var gitconfigPath: String {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitconfig").path
    }

    // MARK: - Apply

    func applyMapping(profile: GitProfile, directoryPath: String) async throws {
        let expandedDir = (directoryPath as NSString).expandingTildeInPath
        let configDir = mimoConfigDir()
        let profileConfigPath = configDir.appendingPathComponent("\(profile.id.uuidString).gitconfig")

        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("[user]")
        lines.append("\tname = \(profile.userName)")
        lines.append("\temail = \(profile.userEmail)")
        if let key = profile.signingKey, !key.isEmpty {
            lines.append("\tsigningkey = \(key)")
        }
        let newContent = lines.joined(separator: "\n")
        let beforeContent = (try? String(contentsOfFile: profileConfigPath.path, encoding: .utf8))
        try newContent.write(toFile: profileConfigPath.path, atomically: true, encoding: .utf8)

        // Audit — per-profile gitconfig file.
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: profile.id,
                profileName: profile.name,
                scope: .mimoProfiles,
                path: profileConfigPath.path,
                summary: "wrote profile config for \(directoryPath)",
                before: beforeContent,
                after: newContent
            )
        )

        try await ensureIncludeIfBlock(
            condition: "gitdir:\(expandedDir)/",
            path: profileConfigPath.path,
            profile: profile
        )
    }

    // MARK: - Remove

    func removeMapping(directoryPath: String) async throws {
        let expandedDir = (directoryPath as NSString).expandingTildeInPath
        try await removeIncludeIfBlock(
            condition: "gitdir:\(expandedDir)/",
            profile: nil
        )
    }

    func removeMapping(for profileID: UUID) async throws {
        let configDir = mimoConfigDir()
        let profileConfigPath = configDir.appendingPathComponent("\(profileID.uuidString).gitconfig")
        if fileManager.fileExists(atPath: profileConfigPath.path) {
            let beforeContent = try? String(contentsOfFile: profileConfigPath.path, encoding: .utf8)
            try fileManager.removeItem(at: profileConfigPath)
            // Audit removal so it can be restored.
            IdentityAuditLog.shared.record(
                AuditEntry(
                    profileID: profileID,
                    profileName: "Profile \(profileID.uuidString.prefix(8))",
                    scope: .mimoProfiles,
                    path: profileConfigPath.path,
                    summary: "deleted profile config file",
                    before: beforeContent,
                    after: nil
                )
            )
        }
        try await removeIncludeIfBlockContaining(path: profileConfigPath.path)
    }

    // MARK: - Read

    func readMappings() -> [(condition: String, path: String)] {
        guard let content = try? String(contentsOfFile: gitconfigPath, encoding: .utf8) else { return [] }
        var results: [(String, String)] = []
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[includeIf \"") {
                let start = trimmed.index(trimmed.firstIndex(of: "\"")!, offsetBy: 1)
                let end = trimmed.index(trimmed.lastIndex(of: "\"")!, offsetBy: -0)
                let condition = String(trimmed[start..<end])
                if i + 1 < lines.count {
                    let pathLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if pathLine.hasPrefix("path = ") {
                        results.append((condition, String(pathLine.dropFirst(7))))
                    }
                }
            }
            i += 1
        }
        return results
    }

    // MARK: - Private

    private func mimoConfigDir() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mimo/profiles")
    }

    /// Audited variant — captures the full ~/.gitconfig snapshot. We store
    /// the whole-file state (under .mimoProfiles scope on `path = gitconfig`)
    /// because the structured includeIf block is intertwined with the rest
    /// of the file and revert is safest as a verbatim restore.
    private func ensureIncludeIfBlock(condition: String, path: String, profile: GitProfile) async throws {
        let beforeGitconfig = try? String(contentsOfFile: gitconfigPath, encoding: .utf8)

        try await removeIncludeIfBlock(condition: condition, profile: nil, suppressAudit: true)
        let block = "\n[includeIf \"\(condition)\"]\n\tpath = \(path)\n"
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: gitconfigPath)) else { return }
        try handle.seekToEnd()
        handle.write(Data(block.utf8))
        try handle.close()

        let afterGitconfig = try? String(contentsOfFile: gitconfigPath, encoding: .utf8)
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: profile.id,
                profileName: profile.name,
                scope: .mimoProfiles,
                path: gitconfigPath,
                summary: "added includeIf for \(condition)",
                before: beforeGitconfig,
                after: afterGitconfig
            )
        )
    }

    private func removeIncludeIfBlock(condition: String, profile: GitProfile?, suppressAudit: Bool = false) async throws {
        guard let content = try? String(contentsOfFile: gitconfigPath, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        var filtered: [String] = []
        var skip = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[includeIf \"\(condition)\"]" {
                skip = true
                continue
            }
            if skip && trimmed.hasPrefix("path = ") {
                skip = false
                continue
            }
            skip = false
            filtered.append(line)
        }
        let newContent = filtered.joined(separator: "\n")
        guard newContent != content else { return }
        try newContent.write(toFile: gitconfigPath, atomically: true, encoding: .utf8)

        if !suppressAudit {
            IdentityAuditLog.shared.record(
                AuditEntry(
                    profileID: profile?.id,
                    profileName: profile?.name ?? "Mimo",
                    scope: .mimoProfiles,
                    path: gitconfigPath,
                    summary: "removed includeIf for \(condition)",
                    before: content,
                    after: newContent
                )
            )
        }
    }

    private func removeIncludeIfBlockContaining(path: String) async throws {
        guard let content = try? String(contentsOfFile: gitconfigPath, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        var filtered: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("path = ") && trimmed.contains(path) {
                if let last = filtered.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("[includeIf") {
                    filtered.removeLast()
                }
                continue
            }
            filtered.append(line)
        }
        let newContent = filtered.joined(separator: "\n")
        guard newContent != content else { return }
        try newContent.write(toFile: gitconfigPath, atomically: true, encoding: .utf8)

        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: nil,
                profileName: "Mimo",
                scope: .mimoProfiles,
                path: gitconfigPath,
                summary: "removed includeIf referencing \((path as NSString).lastPathComponent)",
                before: content,
                after: newContent
            )
        )
    }
}
