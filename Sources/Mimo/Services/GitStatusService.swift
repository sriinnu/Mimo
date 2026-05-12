//
//  GitStatusService.swift
//  Mimo
//
// Created by Srinivas Pendela on 27/04/2026.
//

import Foundation

struct GitRepoStatus {
    let branch: String?
    let isDirty: Bool
    let ahead: Int
    let behind: Int
    let repoName: String?
}

actor GitStatusService {

    private let shell = ShellService()

    func status(for directory: String) async -> GitRepoStatus {
        let branch = (try? await shell.run(
            "git",
            arguments: ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
        )) ?? nil

        let porcelain = (try? await shell.run(
            "git",
            arguments: ["-C", directory, "status", "--porcelain"]
        )) ?? ""

        let isDirty = !porcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let repoRoot = (try? await shell.run(
            "git",
            arguments: ["-C", directory, "rev-parse", "--show-toplevel"]
        )) ?? nil

        let repoName = repoRoot.flatMap { URL(fileURLWithPath: $0).lastPathComponent }

        let ahead: Int
        let behind: Int
        if let branch, branch != "HEAD" {
            let tracking = (try? await shell.run(
                "git",
                arguments: ["-C", directory, "rev-list", "--left-right", "--count", "\(branch)...@{u}"]
            )) ?? nil
            let parts = tracking?.split(separator: "\t").compactMap { Int($0) }
            ahead = parts?[safe: 0] ?? 0
            behind = parts?[safe: 1] ?? 0
        } else {
            ahead = 0
            behind = 0
        }

        return GitRepoStatus(
            branch: branch,
            isDirty: isDirty,
            ahead: ahead,
            behind: behind,
            repoName: repoName
        )
    }

    func findGitRepo(in directory: String) async -> String? {
        var url = URL(fileURLWithPath: directory)
        let fm = FileManager.default
        while url.path != "/" {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
            url = url.deletingLastPathComponent()
        }
        if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
            return url.path
        }
        return nil
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
