//
//  GitConfigService.swift
//  Mimo
//

import Foundation

/// What Mimo found in `~/.gitconfig` at first launch. Any field can be
/// nil; the onboarding sheet displays what's present.
struct GitIdentitySnapshot: Identifiable {
    let id = UUID()
    let userName: String?
    let userEmail: String?
    let signingKey: String?
    let signingType: SigningType
    let sshKeyPath: String?

    var hasAnything: Bool {
        userName != nil || userEmail != nil || signingKey != nil || sshKeyPath != nil
    }

    var hasMinimumForProfile: Bool {
        userName != nil && userEmail != nil
    }
}

enum GitConfigError: LocalizedError {
    case gitNotInstalled
    case configNotFound
    case profileNotFound(String)
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitNotInstalled:
            return "Git is not installed on this system."
        case .configNotFound:
            return "Could not locate ~/.gitconfig."
        case .profileNotFound(let name):
            return "Profile '\(name)' not found."
        case .readFailed(let detail):
            return "Failed to read git config: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write git config: \(detail)"
        }
    }
}

actor GitConfigService {

    private let shell = ShellService()
    private let providerConfig = ProviderConfigService()

    private var gitconfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitconfig")
            .path
    }

    // MARK: - Read Current Config

    func currentUserName() async -> String? {
        try? await shell.run("git", arguments: ["config", "--global", "user.name"])
    }

    func currentUserEmail() async -> String? {
        try? await shell.run("git", arguments: ["config", "--global", "user.email"])
    }

    func currentSigningKey() async -> String? {
        try? await shell.run("git", arguments: ["config", "--global", "user.signingkey"])
    }

    func currentSSHCommand() async -> String? {
        try? await shell.run("git", arguments: ["config", "--global", "core.sshCommand"])
    }

    private func currentValue(_ key: String) async -> String? {
        guard let v = try? await shell.run("git", arguments: ["config", "--global", key]),
              !v.isEmpty else { return nil }
        return v
    }

    /// Snapshot of the user's existing global git identity, used by the
    /// first-run onboarding sheet to decide what to offer for import.
    /// Every field is independently optional — a partial identity (name
    /// only, no email) still surfaces so the UI can show it accurately.
    func currentIdentitySnapshot() async -> GitIdentitySnapshot {
        async let name = currentUserName()
        async let email = currentUserEmail()
        async let signingKey = currentSigningKey()
        async let sshCommand = currentSSHCommand()
        async let commitGpgSign = currentValue("commit.gpgSign")
        async let gpgFormat = currentValue("gpg.format")

        let (n, e, k, ssh, sign, format) =
            await (name, email, signingKey, sshCommand, commitGpgSign, gpgFormat)

        let signingType: SigningType
        if sign == "true" {
            signingType = (format == "ssh") ? .ssh : .gpg
        } else {
            signingType = .none
        }

        return GitIdentitySnapshot(
            userName: n,
            userEmail: e,
            signingKey: k,
            signingType: signingType,
            sshKeyPath: Self.parseSSHKeyPath(from: ssh)
        )
    }

    /// `core.sshCommand` typically looks like `ssh -i /path/to/key` — pull
    /// the path out so the imported profile has an sshKeyPath set.
    static func parseSSHKeyPath(from sshCommand: String?) -> String? {
        guard let cmd = sshCommand else { return nil }
        let parts = cmd.split(separator: " ").map(String.init)
        guard let idx = parts.firstIndex(of: "-i"), idx + 1 < parts.count else { return nil }
        return parts[idx + 1]
    }

    // MARK: - Switch Profile

    @discardableResult
    func applyProfile(_ profile: GitProfile) async throws -> Bool {
        try await setGlobal("user.name", to: profile.userName, profile: profile)
        try await setGlobal("user.email", to: profile.userEmail, profile: profile)

        // SSH command
        if let sshKeyPath = profile.sshKeyPath, !sshKeyPath.isEmpty {
            let expandedPath = (sshKeyPath as NSString).expandingTildeInPath
            let sshCommand = "ssh -i \(expandedPath)"
            try await setGlobal("core.sshCommand", to: sshCommand, profile: profile)
        } else {
            try await unsetGlobal("core.sshCommand", profile: profile)
        }

        // Signing
        switch profile.signingType {
        case .gpg:
            try await setGlobal("commit.gpgSign", to: "true", profile: profile)
            try await setGlobal("gpg.format", to: "openpgp", profile: profile)
            if let key = profile.signingKey, !key.isEmpty {
                try await setGlobal("user.signingkey", to: key, profile: profile)
            }
        case .ssh:
            try await setGlobal("commit.gpgSign", to: "true", profile: profile)
            try await setGlobal("gpg.format", to: "ssh", profile: profile)
            if let key = profile.signingKey ?? profile.sshKeyPath, !key.isEmpty {
                try await setGlobal("user.signingkey", to: key, profile: profile)
            }
        case .none:
            try await unsetGlobal("commit.gpgSign", profile: profile)
            try await unsetGlobal("gpg.format", profile: profile)
            try await unsetGlobal("user.signingkey", profile: profile)
        }

        // Credential helper
        if profile.credentialHelper == .none {
            try await unsetGlobal("credential.helper", profile: profile)
        } else {
            try await setGlobal(
                "credential.helper",
                to: profile.credentialHelper.rawValue,
                profile: profile
            )
        }

        // Provider URL rewriting
        try await providerConfig.applyProviderConfig(profile, provider: profile.provider)

        return true
    }

    // MARK: - Detect Active Profile

    func detectActiveProfile(from profiles: [GitProfile]) async -> UUID? {
        let name = await currentUserName()
        let email = await currentUserEmail()
        guard let name, let email else { return nil }
        return profiles.first { profile in
            profile.userName == name && profile.userEmail == email
        }?.id
    }

    // MARK: - Audited writes
    //
    // Every config write goes through these two helpers. They read the
    // pre-state, mutate, then drop a line in the audit log so the user
    // can scroll back later and undo any single change.

    private func setGlobal(_ key: String, to value: String, profile: GitProfile) async throws {
        let before = await currentValue(key)
        _ = try await shell.run("git", arguments: ["config", "--global", key, value])

        // Skip noisy no-op rows — if nothing actually changed, no audit.
        guard before != value else { return }

        IdentityAuditLog.shared.record(
            .gitConfigGlobal(
                profileID: profile.id,
                profileName: profile.name,
                key: key,
                before: before,
                after: value
            )
        )
    }

    private func unsetGlobal(_ key: String, profile: GitProfile) async throws {
        let before = await currentValue(key)
        // Unset is allowed to fail (key may not be set); we don't propagate.
        _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", key])

        // No audit if nothing was there to begin with.
        guard before != nil else { return }

        IdentityAuditLog.shared.record(
            .gitConfigGlobal(
                profileID: profile.id,
                profileName: profile.name,
                key: key,
                before: before,
                after: nil
            )
        )
    }
}
