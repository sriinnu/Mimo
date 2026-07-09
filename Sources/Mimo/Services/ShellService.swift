//
//  ShellService.swift
//  Mimo
//
//  Created by Srinivas Pendela on 26/03/2026
//

import Foundation

enum ShellError: LocalizedError {
    case executionFailed(String)
    case commandNotFound(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Shell execution failed: \(message)"
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        }
    }
}

actor ShellService {

    /// Execute a shell command and return trimmed stdout.
    func run(_ command: String, arguments: [String] = []) async throws -> String {
        let (output, errorOutput, status) = try await Self.capture(
            executable: "/usr/bin/env",
            arguments: [command] + arguments,
            environment: nil
        )
        guard status == 0 else {
            throw ShellError.executionFailed(errorOutput.isEmpty ? "Exit code \(status)" : errorOutput)
        }
        return output
    }

    /// Shared, deadlock-free process runner.
    ///
    /// Pipes are drained concurrently with `waitUntilExit` — otherwise a
    /// command that emits more than the pipe buffer (~64KB) blocks forever
    /// on write while we wait for it to exit. `git clone` and
    /// `git status --porcelain` on big repos both hit this.
    nonisolated static func capture(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) async throws -> (output: String, errorOutput: String, status: Int32) {

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if let environment { process.environment = environment }

        // Start draining each pipe on a background thread BEFORE waiting.
        // `readDataToEndOfFile` blocks until the write end closes (process
        // exit), so it must run off-thread and in parallel with
        // `waitUntilExit` — a full pipe otherwise deadlocks the process.
        let outReader = PipeReader(outputPipe)
        let errReader = PipeReader(errorPipe)
        outReader.start()
        errReader.start()

        try process.run()

        process.waitUntilExit()
        let outData = outReader.wait()
        let errData = errReader.wait()

        let output = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, errorOutput, process.terminationStatus)
    }
}

/// Reads a pipe to EOF on a background thread and hands the bytes back via a
/// semaphore. Foundation's `Thread` has no join, so we wait on the semaphore.
final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let semaphore = DispatchSemaphore(value: 0)
    private var data = Data()
    private let lock = NSLock()

    init(_ pipe: Pipe) { self.pipe = pipe }

    func start() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            let d = self.pipe.fileHandleForReading.readDataToEndOfFile()
            self.lock.lock(); self.data = d; self.lock.unlock()
            self.semaphore.signal()
        }
        thread.qualityOfService = .utility
        thread.start()
    }

    func wait() -> Data {
        semaphore.wait()
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
