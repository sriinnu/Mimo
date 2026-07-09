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
        return Self.parseMappings(from: content)
    }

    // MARK: - Private

    private func mimoConfigDir() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mimo/profiles")
    }

    /// Make sure ~/.gitconfig exists before we try to open a FileHandle to it.
    /// Without this, `FileHandle(forWritingTo:)` returns nil on a fresh
    /// machine and the includeIf block is silently dropped — the mapping
    /// appears to apply but never takes effect.
    private func ensureGitconfigExists() throws {
        guard !fileManager.fileExists(atPath: gitconfigPath) else { return }
        // git would normally create this on first `git config --global`; we
        // touch it ourselves so the append below has a file to write to.
        try "".write(toFile: gitconfigPath, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: gitconfigPath)
    }

    /// Audited variant — captures the full ~/.gitconfig snapshot. We store
    /// the whole-file state (under .mimoProfiles scope on `path = gitconfig`)
    /// because the structured includeIf block is intertwined with the rest
    /// of the file and revert is safest as a verbatim restore.
    private func ensureIncludeIfBlock(condition: String, path: String, profile: GitProfile) async throws {
        let beforeGitconfig = try? String(contentsOfFile: gitconfigPath, encoding: .utf8)

        try ensureGitconfigExists()
        try await removeIncludeIfBlock(condition: condition, profile: nil, suppressAudit: true)

        let block = "\n[includeIf \"\(condition)\"]\n\tpath = \(path)\n"
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: gitconfigPath)) else {
            throw IncludeIfError.writeFailed("could not open ~/.gitconfig for writing")
        }
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
        let newContent = Self.removeBlock(condition: condition, from: content)
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
        let newContent = Self.removeBlockContaining(path: path, from: content)
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

// MARK: - Pure transforms (visible to tests)

extension IncludeIfService {

    /// Parse `[includeIf "..."]` + `path = ...` pairs out of gitconfig
    /// content. Tolerates blank lines between header and path, and never
    /// force-unwraps on malformed input. Visible to tests.
    static func parseMappings(from content: String) -> [(condition: String, path: String)] {
        let lines = content.components(separatedBy: .newlines)
        var results: [(String, String)] = []
        var pendingCondition: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[includeIf") {
                pendingCondition = conditionString(from: trimmed) ?? pendingCondition
                continue
            }
            if let condition = pendingCondition {
                if trimmed.isEmpty { continue }          // tolerate blank lines
                if let path = pathValue(from: trimmed) {
                    results.append((condition, path))
                    pendingCondition = nil
                } else {
                    // A non-blank, non-path line ends this includeIf block
                    // without a path — drop the pending condition.
                    pendingCondition = nil
                }
            }
        }
        return results
    }

    /// Remove the `[includeIf "condition"]` block (header + its path line)
    /// from content. Visible to tests.
    static func removeBlock(condition: String, from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var filtered: [String] = []
        var skip = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !skip, trimmed.hasPrefix("[includeIf"),
               conditionString(from: trimmed) == condition {
                skip = true
                continue
            }
            if skip {
                if trimmed.isEmpty { continue }          // swallow trailing blanks
                if pathValue(from: trimmed) != nil {
                    skip = false
                    continue                              // drop the path line
                }
                skip = false                              // malformed: keep the line
            }
            filtered.append(line)
        }
        return filtered.joined(separator: "\n")
    }

    /// Remove any includeIf block whose `path =` references `path`. Visible to tests.
    static func removeBlockContaining(path: String, from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var filtered: [String] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[includeIf") {
                // Find this block's path line (next non-blank line).
                var j = i + 1
                while j < lines.count,
                      lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1
                }
                if j < lines.count,
                   let p = pathValue(from: lines[j].trimmingCharacters(in: .whitespaces)),
                   p.contains(path) {
                    // Match — drop the header, the blank lines, and the path line.
                    i = j + 1
                    continue
                }
                // No match — keep the header verbatim.
                filtered.append(lines[i])
                i += 1
                continue
            }
            filtered.append(lines[i])
            i += 1
        }
        return filtered.joined(separator: "\n")
    }

    /// Pull the condition string out of a `[includeIf "..."]` header.
    /// Returns nil if the line isn't a well-formed header.
    private static func conditionString(from headerLine: String) -> String? {
        guard let firstQuote = headerLine.firstIndex(of: "\""),
              let lastQuote = headerLine.lastIndex(of: "\""),
              firstQuote < lastQuote else { return nil }
        let start = headerLine.index(after: firstQuote)
        return String(headerLine[start..<lastQuote])
    }

    /// Pull the value out of a `path = ...` (or `path=...`) line.
    private static func pathValue(from line: String) -> String? {
        guard line.hasPrefix("path") else { return nil }
        var s = line.dropFirst(4)             // drop "path"
        s = s.drop(while: { $0 == " " || $0 == "\t" })  // drop spaces/tabs
        if s.first == "=" { s = s.dropFirst() }
        s = s.drop(while: { $0 == " " || $0 == "\t" })
        return s.isEmpty ? nil : String(s)
    }
}
