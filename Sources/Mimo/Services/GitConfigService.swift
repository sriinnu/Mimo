//
//  GitConfigService.swift
//  Mimo
//

import Foundation

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

    // MARK: - Switch Profile

    @discardableResult
    func applyProfile(_ profile: GitProfile) async throws -> Bool {
        _ = try await shell.run("git", arguments: ["config", "--global", "user.name", profile.userName])
        _ = try await shell.run("git", arguments: ["config", "--global", "user.email", profile.userEmail])

        // SSH command
        if let sshKeyPath = profile.sshKeyPath, !sshKeyPath.isEmpty {
            let expandedPath = (sshKeyPath as NSString).expandingTildeInPath
            let sshCommand = "ssh -i \(expandedPath)"
            _ = try await shell.run("git", arguments: ["config", "--global", "core.sshCommand", sshCommand])
        } else {
            _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", "core.sshCommand"])
        }

        // Signing
        switch profile.signingType {
        case .gpg:
            _ = try await shell.run("git", arguments: ["config", "--global", "commit.gpgSign", "true"])
            _ = try await shell.run("git", arguments: ["config", "--global", "gpg.format", "openpgp"])
            if let key = profile.signingKey, !key.isEmpty {
                _ = try await shell.run("git", arguments: ["config", "--global", "user.signingkey", key])
            }
        case .ssh:
            _ = try await shell.run("git", arguments: ["config", "--global", "commit.gpgSign", "true"])
            _ = try await shell.run("git", arguments: ["config", "--global", "gpg.format", "ssh"])
            if let key = profile.signingKey ?? profile.sshKeyPath, !key.isEmpty {
                _ = try await shell.run("git", arguments: ["config", "--global", "user.signingkey", key])
            }
        case .none:
            _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", "commit.gpgSign"])
            _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", "gpg.format"])
            _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", "user.signingkey"])
        }

        // Credential helper
        if profile.credentialHelper == .none {
            _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", "credential.helper"])
        } else {
            _ = try await shell.run("git", arguments: ["config", "--global", "credential.helper", profile.credentialHelper.rawValue])
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
}
