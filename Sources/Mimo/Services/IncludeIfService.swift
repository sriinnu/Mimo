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
        try lines.joined(separator: "\n").write(toFile: profileConfigPath.path, atomically: true, encoding: .utf8)

        try await ensureIncludeIfBlock(
            condition: "gitdir:\(expandedDir)/",
            path: profileConfigPath.path
        )
    }

    // MARK: - Remove

    func removeMapping(directoryPath: String) async throws {
        let expandedDir = (directoryPath as NSString).expandingTildeInPath
        try await removeIncludeIfBlock(condition: "gitdir:\(expandedDir)/")
    }

    func removeMapping(for profileID: UUID) async throws {
        let configDir = mimoConfigDir()
        let profileConfigPath = configDir.appendingPathComponent("\(profileID.uuidString).gitconfig")
        if fileManager.fileExists(atPath: profileConfigPath.path) {
            try fileManager.removeItem(at: profileConfigPath)
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

    private func ensureIncludeIfBlock(condition: String, path: String) async throws {
        try await removeIncludeIfBlock(condition: condition)
        let block = "\n[includeIf \"\(condition)\"]\n\tpath = \(path)\n"
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: gitconfigPath)) else { return }
        try handle.seekToEnd()
        handle.write(Data(block.utf8))
        try handle.close()
    }

    private func removeIncludeIfBlock(condition: String) async throws {
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
        try filtered.joined(separator: "\n").write(toFile: gitconfigPath, atomically: true, encoding: .utf8)
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
        try filtered.joined(separator: "\n").write(toFile: gitconfigPath, atomically: true, encoding: .utf8)
    }
}
