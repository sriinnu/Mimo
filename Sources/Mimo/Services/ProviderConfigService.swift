//
//  ProviderConfigService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 12/05/2026
//

import Foundation

actor ProviderConfigService {

    private let shell = ShellService()

    func applyProviderConfig(_ profile: GitProfile, provider: GitProvider) async throws {
        guard provider != .custom else { return }

        let httpsPrefix = provider.httpsURLPrefix
        let sshPrefix = provider.sshURLPrefix

        if !httpsPrefix.isEmpty {
            _ = try await shell.run("git", arguments: [
                "config", "--global",
                "url.\(sshPrefix).insteadOf", httpsPrefix
            ])
        }

        if let sshKeyPath = profile.sshKeyPath, !sshKeyPath.isEmpty {
            let expandedPath = (sshKeyPath as NSString).expandingTildeInPath
            let sshCommand = "ssh -i \(expandedPath)"
            _ = try await shell.run("git", arguments: [
                "config", "--global", "core.sshCommand", sshCommand
            ])
        }
    }

    func removeProviderConfig(_ profile: GitProfile, provider: GitProvider) async throws {
        guard provider != .custom else { return }

        let sshPrefix = provider.sshURLPrefix
        if !sshPrefix.isEmpty {
            _ = try? await shell.run("git", arguments: [
                "config", "--global", "--unset", "url.\(sshPrefix).insteadOf"
            ])
        }

        if let sshKeyPath = profile.sshKeyPath, !sshKeyPath.isEmpty {
            _ = try? await shell.run("git", arguments: [
                "config", "--global", "--unset", "core.sshCommand"
            ])
        }
    }

    func generateSSHConfigHost(for profile: GitProfile, provider: GitProvider) -> String? {
        guard provider != .custom,
              let sshKeyPath = profile.sshKeyPath,
              !sshKeyPath.isEmpty,
              !provider.defaultHost.isEmpty
        else { return nil }

        let expandedPath = (sshKeyPath as NSString).expandingTildeInPath
        return """
        Host \(provider.defaultHost)
            HostName \(provider.defaultHost)
            IdentityFile \(expandedPath)
            User git
        """
    }
}
