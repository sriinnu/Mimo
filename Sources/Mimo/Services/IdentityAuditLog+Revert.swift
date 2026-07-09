//
//  IdentityAuditLog+Revert.swift
//  Mimo
//
//  Revert engine — undoes a single audit entry by replaying the `before`
//  value back to disk. Conflict-aware: if the live value no longer matches
//  what Mimo wrote (`entry.after`), something changed it since, and we
//  refuse rather than clobber the user's current state. Every revert is
//  itself audited so the undo shows in the time machine (reverts of reverts
//  aren't re-undoable from the UI — `isReverted` gates the button).
//

import Foundation

extension IdentityAuditLog {

    /// Undo a single audit entry.
    ///
    /// Throws `RevertError.conflict` when the live value has drifted from
    /// `entry.after` — restoring `before` then would silently overwrite an
    /// unrelated later change, which is worse than asking the user to look.
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
            try await revertMimoProfiles(entry)

        case .firstRunImport:
            throw RevertError.notSupported(
                "The first-run import moment is traceable but not revertable. "
                + "Delete the imported profile if you want it gone."
            )
        }

        // Flag the original entry reverted — through the writer actor so it
        // can't race an in-flight append.
        await AuditLogWriter.shared.flag(id: entry.id, cap: maxEntries)

        // In-memory mirror — update so the UI reflects the change immediately.
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry.flaggedReverted()
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

        // Conflict guard: only undo if the live value is still what this
        // entry left it. If it drifted (manual edit, another switch, another
        // tool), refuse rather than clobber.
        let current = try? await shell.run("git", arguments: ["config", "--global", entry.configKey])
        if current != entry.after {
            throw RevertError.conflict(
                "\(entry.configKey) has changed since this write. "
                + "Live value is \(current ?? "<unset>"); this entry set it to \(entry.after ?? "<unset>"). "
                + "Update it manually if you still want to revert."
            )
        }

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

        // Same conflict guard, repo-local.
        let current = try? await shell.run(
            "git", arguments: ["config", "-f", path, entry.configKey]
        )
        if current != entry.after {
            throw RevertError.conflict(
                "\(entry.configKey) in \(path) has changed since this write."
            )
        }

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
        // `before` content back verbatim — but ONLY if the live file still
        // matches `after`. If the user (or Mimo) edited ~/.ssh/config since,
        // a verbatim restore would nuke those edits, so we refuse.
        guard let before = entry.before else {
            throw RevertError.missingSnapshot
        }

        let sshConfigURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")

        let fm = FileManager.default
        let live = fm.fileExists(atPath: sshConfigURL.path)
            ? (try? String(contentsOfFile: sshConfigURL.path, encoding: .utf8))
            : nil

        if live != entry.after {
            throw RevertError.conflict(
                "~/.ssh/config has changed since this entry was written. "
                + "Restoring the snapshot would overwrite those edits — edit the file manually instead."
            )
        }

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

    // MARK: - Mimo profile-file revert

    /// `.mimoProfiles` entries snapshot a whole file — either a per-profile
    /// gitconfig (`~/.config/mimo/profiles/<uuid>.gitconfig`) or `~/.gitconfig`
    /// itself (for includeIf edits). Both are plain files, so the revert is
    /// the same shape: if the live file still matches `after`, restore `before`
    /// (or delete it if `before` is nil = the file didn't exist yet). If it
    /// drifted, refuse rather than clobber — same guard as SSH config.
    private func revertMimoProfiles(_ entry: AuditEntry) async throws {
        guard let path = entry.path, !path.isEmpty else {
            throw RevertError.missingSnapshot
        }
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        let live = fm.fileExists(atPath: path)
            ? (try? String(contentsOfFile: path, encoding: .utf8))
            : nil

        if live != entry.after {
            throw RevertError.conflict(
                "\(url.lastPathComponent) has changed since this entry was written. "
                + "Restoring the snapshot would overwrite those edits."
            )
        }

        if let before = entry.before {
            // File existed before this write — restore the prior contents.
            try fm.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try before.write(to: url, atomically: true, encoding: .utf8)
        } else {
            // `before` was nil → this entry *created* the file; revert = remove it.
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
            }
        }
    }
}

// MARK: - Errors

enum RevertError: LocalizedError {
    case notSupported(String)
    case missingSnapshot
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .notSupported(let msg): return msg
        case .missingSnapshot:
            return "The before-state snapshot is missing — can't restore SSH config."
        case .conflict(let msg):
            return "Can't revert safely: \(msg)"
        }
    }
}
