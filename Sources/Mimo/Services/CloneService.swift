//
//  CloneService.swift
//  Mimo
//

import Foundation

struct CloneResult {
    let success: Bool
    let output: String
}

actor CloneService {

    private let shell = ShellService()

    func detectProvider(from url: String) -> GitProvider {
        // Match on the parsed HOST only — a naive `url.contains("github.com")`
        // is spoofable: `https://evil.github.com.attacker.com/...` and
        // `https://notgithub.com/github.com/...` would both misdetect as
        // GitHub and trigger provider rewrites (url.insteadOf, SSH host block)
        // for the wrong host.
        let host = Self.host(of: url)?.lowercased() ?? ""
        switch host {
        case "github.com": return .github
        case "dev.azure.com", "ssh.dev.azure.com": return .azureDevOps
        case "gitlab.com": return .gitlab
        case "bitbucket.org": return .bitbucket
        default: return .custom
        }
    }

    /// Pull the hostname out of an HTTPS or SCP-style SSH git URL.
    /// `https://host/...` → parsed via URLComponents; `git@host:...` →
    /// strip the user, take everything up to the first `:` or `/`.
    nonisolated static func host(of url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)?.host
        }
        var s = trimmed
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        let stop = s.firstIndex(where: { $0 == ":" || $0 == "/" }) ?? s.endIndex
        let host = String(s[..<stop])
        return host.isEmpty ? nil : host
    }

    func findProfile(for provider: GitProvider, profiles: [GitProfile]) -> GitProfile? {
        profiles.first { $0.provider == provider }
    }

    func clone(url: String, into directory: String, profile: GitProfile?) async throws -> CloneResult {
        var env = ProcessInfo.processInfo.environment

        if let profile, let sshKeyPath = profile.sshKeyPath, !sshKeyPath.isEmpty {
            let expandedPath = (sshKeyPath as NSString).expandingTildeInPath
            env["GIT_SSH_COMMAND"] = "ssh -i \(expandedPath) -o IdentitiesOnly=yes"
        }

        // Drain pipes concurrently via ShellService.capture so a large clone
        // (progress > ~64KB on stderr) can't deadlock us.
        let (output, errorOutput, status) = try await ShellService.capture(
            executable: "/usr/bin/env",
            arguments: ["git", "clone", url, directory],
            environment: env
        )

        if status == 0 {
            // git clone prints progress to stderr; surface both for success.
            return CloneResult(success: true, output: output + errorOutput)
        } else {
            return CloneResult(
                success: false,
                output: errorOutput.isEmpty ? output : errorOutput
            )
        }
    }
}
