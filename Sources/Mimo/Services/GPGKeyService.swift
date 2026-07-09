//
//  GPGKeyService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 27/04/2026
//

import Foundation

struct GPGKeyInfo: Identifiable, Equatable {
    let id: UUID
    let keyID: String
    let userID: String
    let createdAt: Date?
}

actor GPGKeyService {

    private let shell = ShellService()

    /// List secret keys via gpg's machine-readable colon format.
    ///
    /// We use `--with-colons` because the human-readable format drifts across
    /// GPG versions (the 40-char fingerprint moved off the `sec` line in
    /// 2.2+), which broke the old "find a ≥40-hex token on the sec line"
    /// parser. Colon records are stable: `sec:...:KEYID:...`, the following
    /// `fpr:` line carries the fingerprint, and `uid:` lines carry the user
    /// id in field 9.
    func scanKeys() async throws -> [GPGKeyInfo] {
        let output = try await shell.run(
            "gpg",
            arguments: [
                "--list-secret-keys",
                "--keyid-format=long",
                "--with-colons",
                "--with-fingerprint",
            ]
        )

        guard !output.isEmpty else { return [] }

        var keys: [GPGKeyInfo] = []
        var currentKeyID: String?
        var currentCreatedAt: Date?
        var sawUID = false

        for line in output.components(separatedBy: .newlines) {
            // Keep empty fields — positions matter in colon records.
            let fields = line.split(separator: ":", omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 10 else { continue }

            switch fields[0] {
            case "sec":
                currentKeyID = fields[4].isEmpty ? nil : fields[4]
                currentCreatedAt = Self.date(fromEpoch: fields[5])
                sawUID = false
            case "fpr":
                // First fpr after a sec is the primary key fingerprint; we
                // don't surface it yet but keep the slot if needed later.
                _ = fields[9]
            case "uid":
                if let keyID = currentKeyID, !sawUID, !fields[9].isEmpty {
                    keys.append(GPGKeyInfo(
                        id: UUID(),
                        keyID: keyID,
                        userID: fields[9],
                        createdAt: currentCreatedAt
                    ))
                    sawUID = true
                }
            default:
                break
            }
        }

        return keys
    }

    func isGPGInstalled() async -> Bool {
        guard let result = try? await shell.run("which", arguments: ["gpg"]) else {
            return false
        }
        return !result.isEmpty
    }

    // MARK: - Helpers

    private static func date(fromEpoch field: String) -> Date? {
        guard let secs = TimeInterval(field), secs > 0 else { return nil }
        return Date(timeIntervalSince1970: secs)
    }
}
