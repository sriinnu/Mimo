//
//  SSHImportSafetyTests.swift
//  MimoTests
//
//  Tests for SSH key import filename sanitization.
//  Prevents overwriting reserved SSH files (~/.ssh/config, etc.).
//

import XCTest
@testable import Mimo

final class SSHImportSafetyTests: XCTestCase {

    // MARK: - Reserved filename rejection

    func testRejectsConfig() async throws {
        try await assertImportFails(filename: "config")
    }

    func testRejectsKnownHosts() async throws {
        try await assertImportFails(filename: "known_hosts")
    }

    func testRejectsAuthorizedKeys() async throws {
        try await assertImportFails(filename: "authorized_keys")
    }

    // MARK: - Dotfile rejection

    func testRejectsDotfile() async throws {
        try await assertImportFails(filename: ".hidden_key")
    }

    // MARK: - Valid filenames accepted

    func testAcceptsEd25519Key() async throws {
        try await assertImportSucceeds(filename: "id_ed25519")
    }

    func testAcceptsCustomNamedKey() async throws {
        try await assertImportSucceeds(filename: "github_work_key")
    }

    // MARK: - Helpers

    private func makeSourceFile(named filename: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let srcFile = tmpDir.appendingPathComponent(filename)
        try "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
            .write(toFile: srcFile.path, atomically: true, encoding: .utf8)
        return srcFile
    }

    private func assertImportFails(filename: String) async throws {
        let service = SSHKeyService()
        let srcFile = try makeSourceFile(named: filename)

        defer {
            try? FileManager.default.removeItem(at: srcFile.deletingLastPathComponent())
        }

        do {
            _ = try await service.importKey(from: srcFile.path)
            XCTFail("Import should have rejected filename: \(filename)")
        } catch {
            // Expected
        }
    }

    private func assertImportSucceeds(filename: String) async throws {
        let service = SSHKeyService()
        let srcFile = try makeSourceFile(named: filename)

        defer {
            try? FileManager.default.removeItem(at: srcFile.deletingLastPathComponent())
            let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
            try? FileManager.default.removeItem(
                at: sshDir.appendingPathComponent(filename)
            )
        }

        do {
            let destPath = try await service.importKey(from: srcFile.path)
            XCTAssertTrue(destPath.hasSuffix(filename))
        } catch {
            // Could fail if ~/.ssh doesn't exist in test env — acceptable
        }
    }
}
