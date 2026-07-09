//
//  ProviderConfigService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 12/05/2026
//

import Foundation

actor ProviderConfigService {

    private let shell = ShellService()

    private func currentValue(_ key: String) async -> String? {
        guard let v = try? await shell.run("git", arguments: ["config", "--global", key]),
              !v.isEmpty else { return nil }
        return v
    }

    func applyProviderConfig(_ profile: GitProfile, provider: GitProvider) async throws {
        guard provider != .custom else { return }

        // Rewrite HTTPS provider URLs to SSH so the per-profile SSH key is
        // used. `core.sshCommand` is owned by GitConfigService.applyProfile —
        // writing it here too was a redundant double-write.
        let httpsPrefix = provider.httpsURLPrefix
        let sshPrefix = provider.sshURLPrefix

        if !httpsPrefix.isEmpty {
            let key = "url.\(sshPrefix).insteadOf"
            try await auditedSet(key: key, value: httpsPrefix, profile: profile)
        }
    }

    func removeProviderConfig(_ profile: GitProfile, provider: GitProvider) async throws {
        guard provider != .custom else { return }

        let sshPrefix = provider.sshURLPrefix
        if !sshPrefix.isEmpty {
            let key = "url.\(sshPrefix).insteadOf"
            try await auditedUnset(key: key, profile: profile)
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

    // MARK: - Audited primitives

    private func auditedSet(key: String, value: String, profile: GitProfile) async throws {
        let before = await currentValue(key)
        _ = try await shell.run("git", arguments: ["config", "--global", key, value])
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

    private func auditedUnset(key: String, profile: GitProfile) async throws {
        let before = await currentValue(key)
        _ = try? await shell.run("git", arguments: ["config", "--global", "--unset", key])
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
