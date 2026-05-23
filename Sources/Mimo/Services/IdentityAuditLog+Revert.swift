//
//  IdentityAuditLog+Revert.swift
//  Mimo
//
//  Revert engine — undoes a single audit entry by replaying the `before`
//  value back to disk. Every revert itself is audited so the user can see
//  the undo in the time machine (but reverts of reverts are not undoable
//  from the UI — `isReverted` gates the button).
//

import Foundation

extension IdentityAuditLog {

    /// Undo a single audit entry.
    ///
    /// Throws on disk / git failures so the view can surface the error.
    /// The entry is flagged as reverted only after the write succeeds.
    func revert(_ entry: AuditEntry) async throws {
        guard !entry.isReverted else { return }

        switch entry.scope {
        case .gitConfigGlobal:
            try await revertGitConfigGlobal(entry)

        case .gitConfigRepo(let path):
            try await revertGitConfigRepo(entry, path: path)

        case .sshConfig:
            try await revertSSHConfig(entry)

        case .mimoProfiles:
            throw RevertError.notSupported(
                "Profile-file snapshots can't be reverted entry-by-entry. "
                + "Switch profiles manually to restore a previous state."
            )

        case .firstRunImport:
            throw RevertError.notSupported(
                "The first-run import moment is traceable but not revertable. "
                + "Delete the imported profile if you want it gone."
            )
        }

        // Flag the original entry as reverted on disk.
        Self.flagAsReverted(id: entry.id, cap: maxEntries)

        // In-memory mirror — update so the UI reflects the change immediately.
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = AuditEntry(
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

        // Audit the revert itself.
        record(
            AuditEntry(
                profileID: entry.profileID,
                profileName: entry.profileName,
                scope: entry.scope,
                path: entry.path,
                summary: "reverted: \(entry.summary)",
                before: entry.after,
                after: entry.before,
                configKey: entry.configKey
            )
        )
    }

    // MARK: - Git config revert

    private func revertGitConfigGlobal(_ entry: AuditEntry) async throws {
        let shell = ShellService()
        guard !entry.configKey.isEmpty else { return }

        if let before = entry.before {
            _ = try await shell.run(
                "git", arguments: ["config", "--global", entry.configKey, before]
            )
        } else {
            _ = try? await shell.run(
                "git", arguments: ["config", "--global", "--unset", entry.configKey]
            )
        }
    }

    private func revertGitConfigRepo(_ entry: AuditEntry, path: String) async throws {
        let shell = ShellService()
        guard !entry.configKey.isEmpty else { return }

        if let before = entry.before {
            _ = try await shell.run(
                "git", arguments: ["config", "-f", path, entry.configKey, before]
            )
        } else {
            _ = try? await shell.run(
                "git", arguments: ["config", "-f", path, "--unset", entry.configKey]
            )
        }
    }

    // MARK: - SSH config revert

    private func revertSSHConfig(_ entry: AuditEntry) async throws {
        // SSH entries snapshot the whole file. Restoring means writing the
        // `before` content back verbatim — the same strategy the SSH config
        // service uses for its own block-level ops, just at file granularity.
        guard let before = entry.before else {
            throw RevertError.missingSnapshot
        }

        let sshConfigURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")

        let fm = FileManager.default
        if !fm.fileExists(atPath: sshConfigURL.deletingLastPathComponent().path) {
            try fm.createDirectory(
                at: sshConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try before.write(to: sshConfigURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: sshConfigURL.path
        )
    }
}

// MARK: - Errors

enum RevertError: LocalizedError {
    case notSupported(String)
    case missingSnapshot

    var errorDescription: String? {
        switch self {
        case .notSupported(let msg): return msg
        case .missingSnapshot:
            return "The before-state snapshot is missing — can't restore SSH config."
        }
    }
}
