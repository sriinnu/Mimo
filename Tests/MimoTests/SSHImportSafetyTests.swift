//
//  SSHImportSafetyTests.swift
//  MimoTests
//
//  Tests for SSH key filename sanitization — the guard that stops import/
//  generation from clobbering reserved SSH files (config, known_hosts, …) or
//  escaping ~/.ssh. Exercises the pure `SSHKeyService.sanitizeKeyFilename`
//  directly so results are deterministic and don't depend on ~/.ssh existing.
//

import XCTest
@testable import Mimo

final class SSHImportSafetyTests: XCTestCase {

    // MARK: - Reserved filename rejection

    func testRejectsConfig() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("config"))
    }

    func testRejectsKnownHosts() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("known_hosts"))
    }

    func testRejectsAuthorizedKeys() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("authorized_keys"))
    }

    func testRejectsEnvironment() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("environment"))
    }

    // MARK: - Dotfile rejection

    func testRejectsDotfile() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename(".hidden_key"))
    }

    // MARK: - Path traversal rejection

    func testRejectsParentTraversal() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("../evil"))
    }

    func testRejectsAbsolutePath() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("/etc/passwd"))
    }

    func testRejectsBackslashTraversal() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("..\\evil"))
    }

    // MARK: - Whitespace / empty rejection

    func testRejectsEmpty() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename(""))
    }

    func testRejectsWhitespaceOnly() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("   "))
    }

    func testRejectsEmbeddedNewline() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("id\nHost evil"))
    }

    // MARK: - Reserved name with .pub suffix also rejected

    func testRejectsConfigPub() {
        XCTAssertThrowsError(try SSHKeyService.sanitizeKeyFilename("config.pub"))
    }

    // MARK: - Valid filenames accepted

    func testAcceptsEd25519Key() throws {
        let name = try SSHKeyService.sanitizeKeyFilename("id_ed25519")
        XCTAssertEqual(name, "id_ed25519")
    }

    func testAcceptsCustomNamedKey() throws {
        let name = try SSHKeyService.sanitizeKeyFilename("github_work_key")
        XCTAssertEqual(name, "github_work_key")
    }

    func testAcceptsPubFileStripsSuffixForCheck() throws {
        // A *.pub source is allowed; the check runs against the base name.
        let name = try SSHKeyService.sanitizeKeyFilename("id_ed25519.pub")
        XCTAssertEqual(name, "id_ed25519.pub")
    }

    func testTrimsSurroundingWhitespace() throws {
        let name = try SSHKeyService.sanitizeKeyFilename("  id_ed25519  ")
        XCTAssertEqual(name, "id_ed25519")
    }
}
