//
//  AuditEntryCodingTests.swift
//  MimoTests
//
//  Tests for AuditEntry and AuditScope Codable round-trip.
//  If this breaks, Mimo's entire undo history is unreadable.
//

import XCTest
@testable import Mimo

final class AuditEntryCodingTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - AuditScope round-trip

    func testGitConfigGlobalScope() throws {
        let scope = AuditScope.gitConfigGlobal
        let entry = AuditEntry(profileID: nil, profileName: "Test",
                               scope: scope, summary: "test", before: nil, after: nil)
        XCTAssertEqual(try roundTrip(entry).scope, .gitConfigGlobal)
    }

    func testGitConfigRepoScope() throws {
        let path = "/Users/foo/repo/.git/config"
        let scope = AuditScope.gitConfigRepo(path: path)
        let entry = AuditEntry(profileID: nil, profileName: "Test",
                               scope: scope, summary: "test", before: nil, after: nil)
        XCTAssertEqual(try roundTrip(entry).scope, .gitConfigRepo(path: path))
    }

    func testSSHConfigScope() throws {
        let scope = AuditScope.sshConfig
        let entry = AuditEntry(profileID: nil, profileName: "Test",
                               scope: scope, summary: "test", before: nil, after: nil)
        XCTAssertEqual(try roundTrip(entry).scope, .sshConfig)
    }

    func testMimoProfilesScope() throws {
        let scope = AuditScope.mimoProfiles
        let entry = AuditEntry(profileID: nil, profileName: "Test",
                               scope: scope, summary: "test", before: nil, after: nil)
        XCTAssertEqual(try roundTrip(entry).scope, .mimoProfiles)
    }

    // MARK: - Factory method (all before/after combos)

    func testGitConfigGlobalSetFromNil() throws {
        let entry = AuditEntry.gitConfigGlobal(
            profileID: UUID(), profileName: "Work",
            key: "user.email", before: nil, after: "work@co.com"
        )
        let decoded = try roundTrip(entry)
        XCTAssertNil(decoded.before)
        XCTAssertEqual(decoded.after, "work@co.com")
        XCTAssertEqual(decoded.configKey, "user.email")
    }

    func testGitConfigGlobalUnset() throws {
        let entry = AuditEntry.gitConfigGlobal(
            profileID: UUID(), profileName: "Work",
            key: "user.signingkey", before: "ABC123", after: nil
        )
        let decoded = try roundTrip(entry)
        XCTAssertEqual(decoded.before, "ABC123")
        XCTAssertNil(decoded.after)
    }

    func testGitConfigGlobalChange() throws {
        let entry = AuditEntry.gitConfigGlobal(
            profileID: UUID(), profileName: "Work",
            key: "user.name", before: "Old", after: "New"
        )
        let decoded = try roundTrip(entry)
        XCTAssertEqual(decoded.before, "Old")
        XCTAssertEqual(decoded.after, "New")
    }

    func testGitConfigGlobalNoOp() throws {
        let entry = AuditEntry.gitConfigGlobal(
            profileID: UUID(), profileName: "Work",
            key: "user.name", before: "Same", after: "Same"
        )
        XCTAssertTrue(try roundTrip(entry).summary.contains("no change"))
    }

    // MARK: - isReverted flag

    func testIsRevertedPreserved() throws {
        var entry = AuditEntry(profileID: nil, profileName: "Test",
                               scope: .gitConfigGlobal, summary: "test",
                               before: nil, after: nil, isReverted: true)
        XCTAssertTrue(try roundTrip(entry).isReverted)
    }

    // MARK: - Helper

    private func roundTrip(_ entry: AuditEntry) throws -> AuditEntry {
        try decoder.decode(AuditEntry.self, from: encoder.encode(entry))
    }
}
