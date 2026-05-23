//
//  GitProfileCodingTests.swift
//  MimoTests
//
//  Tests for GitProfile Codable round-trip and migration resilience.
//  If profiles can't decode from UserDefaults, the user loses all identities.
//

import XCTest
@testable import Mimo

final class GitProfileCodingTests: XCTestCase {

    // MARK: - Full round-trip

    func testFullRoundTrip() throws {
        let id = UUID()
        let profile = GitProfile(
            id: id, name: "Work", userName: "Jane", userEmail: "jane@work.com",
            signingKey: "ABC123", sshKeyPath: "~/.ssh/id_ed25519_work",
            provider: .github, providerURL: "https://github.com/work",
            signingType: .ssh, credentialHelper: .cache,
            isActive: true, colorID: .coral
        )
        let decoded = try roundTrip(profile)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertEqual(decoded.userName, "Jane")
        XCTAssertEqual(decoded.userEmail, "jane@work.com")
        XCTAssertEqual(decoded.signingKey, "ABC123")
        XCTAssertEqual(decoded.sshKeyPath, "~/.ssh/id_ed25519_work")
        XCTAssertEqual(decoded.provider, .github)
        XCTAssertEqual(decoded.providerURL, "https://github.com/work")
        XCTAssertEqual(decoded.signingType, .ssh)
        XCTAssertEqual(decoded.credentialHelper, .cache)
        XCTAssertTrue(decoded.isActive)
        XCTAssertEqual(decoded.colorID, .coral)
    }

    // MARK: - Migration: missing signingType defaults to .none

    func testMissingSigningTypeDefaultsToNone() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Test","userName":"Test","userEmail":"t@t.com","isActive":true}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded.signingType, .none)
    }

    // MARK: - Migration: missing credentialHelper defaults to .osxkeychain

    func testMissingCredentialHelperDefaultsToOsxkeychain() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Test","userName":"Test","userEmail":"t@t.com","isActive":true}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded.credentialHelper, .osxkeychain)
    }

    // MARK: - Migration: missing colorID falls back to deterministic

    func testMissingColorIDFallsBackToDeterministic() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Test","userName":"Test","userEmail":"t@t.com","isActive":true}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded.colorID, MimoProfileColor.defaultFor(profileID: id))
    }

    // MARK: - Migration: missing provider defaults to .custom

    func testMissingProviderDefaultsToCustom() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Test","userName":"Test","userEmail":"t@t.com","isActive":true}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded.provider, .custom)
    }

    // MARK: - Minimal profile round-trip

    func testMinimalProfileRoundTrip() throws {
        let profile = GitProfile(name: "Personal", userName: "Me", userEmail: "me@me.com")
        let decoded = try roundTrip(profile)
        XCTAssertEqual(decoded.name, "Personal")
        XCTAssertNil(decoded.signingKey)
        XCTAssertNil(decoded.sshKeyPath)
        XCTAssertEqual(decoded.provider, .custom)
        XCTAssertEqual(decoded.signingType, .none)
    }

    // MARK: - Helper

    private func roundTrip(_ profile: GitProfile) throws -> GitProfile {
        let data = try JSONEncoder().encode(profile)
        return try JSONDecoder().decode(GitProfile.self, from: data)
    }
}
