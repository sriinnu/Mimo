//
//  GPGKeyService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 27/04/2026.
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

    func scanKeys() async throws -> [GPGKeyInfo] {
        let output = try await shell.run(
            "gpg",
            arguments: ["--list-secret-keys", "--keyid-format", "long"]
        )

        guard !output.isEmpty else { return [] }

        var keys: [GPGKeyInfo] = []
        var currentKeyID: String?
        var currentCreatedAt: Date?

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("sec") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                for part in parts {
                    if part.count >= 40, part.allSatisfy({ $0.isHexDigit }) {
                        currentKeyID = part
                    } else if part.count == 40, part.contains("/") == false {
                        currentKeyID = part
                    }
                }
                currentCreatedAt = parseDate(from: trimmed)
            }

            if trimmed.hasPrefix("uid"), let keyID = currentKeyID {
                let uidPart = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let userID = extractUserID(from: uidPart)
                keys.append(GPGKeyInfo(
                    id: UUID(),
                    keyID: keyID,
                    userID: userID,
                    createdAt: currentCreatedAt
                ))
                currentKeyID = nil
                currentCreatedAt = nil
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

    private func parseDate(from line: String) -> Date? {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for part in parts {
            if part.count == 10, part.contains("-") {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: part)
            }
        }
        return nil
    }

    private func extractUserID(from raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "^\\[.+?\\]\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped
    }
}
