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
        if url.contains("github.com") { return .github }
        if url.contains("dev.azure.com") || url.contains("ssh.dev.azure.com") { return .azureDevOps }
        if url.contains("gitlab.com") { return .gitlab }
        if url.contains("bitbucket.org") { return .bitbucket }
        return .custom
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

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", url, directory]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return CloneResult(success: true, output: output + errorOutput)
        } else {
            return CloneResult(success: false, output: errorOutput.isEmpty ? output : errorOutput)
        }
    }
}
