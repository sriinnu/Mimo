//
//  RevertMimoProfilesTests.swift
//  MimoTests
//
//  Tests for reverting .mimoProfiles audit snapshots (per-profile gitconfig
//  writes + includeIf edits). Revert targets are isolated temp files so the
//  real ~/.config/mimo is untouched.
//
//  Note: revert() records the undo in the real audit.jsonl (the log isn't
//  injectable yet); that append is harmless and the file targets below are
//  fully isolated.
//

import XCTest
@testable import Mimo

@MainActor
final class RevertMimoProfilesTests: XCTestCase {

    private func tmpFile(_ contents: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-revert-\(UUID().uuidString).txt")
        if let contents { try contents.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    // Restore: file currently == after, revert writes `before` back.
    func testRestoresBeforeContents() async throws {
        let url = try tmpFile("AFTER")
        defer { try? FileManager.default.removeItem(at: url) }

        let entry = AuditEntry(
            profileID: nil, profileName: "T",
            scope: .mimoProfiles, path: url.path,
            summary: "wrote profile config",
            before: "BEFORE", after: "AFTER"
        )

        try await IdentityAuditLog.shared.revert(entry)

        let restored = try String(contentsOfFile: url.path, encoding: .utf8)
        XCTAssertEqual(restored, "BEFORE")
    }

    // Create-revert: before=nil means this entry created the file; revert deletes it.
    func testDeletesFileWhenBeforeWasNil() async throws {
        let url = try tmpFile("CREATED")
        defer { try? FileManager.default.removeItem(at: url) }

        let entry = AuditEntry(
            profileID: nil, profileName: "T",
            scope: .mimoProfiles, path: url.path,
            summary: "created profile config",
            before: nil, after: "CREATED"
        )

        try await IdentityAuditLog.shared.revert(entry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // Conflict: live file drifted from `after` → refuse, leave the file untouched.
    func testRefusesWhenFileChangedSince() async throws {
        let url = try tmpFile("DRIFTED")
        defer { try? FileManager.default.removeItem(at: url) }

        let entry = AuditEntry(
            profileID: nil, profileName: "T",
            scope: .mimoProfiles, path: url.path,
            summary: "wrote profile config",
            before: "BEFORE", after: "AFTER"   // live is "DRIFTED", not "AFTER"
        )

        do {
            try await IdentityAuditLog.shared.revert(entry)
            XCTFail("Revert should have refused on conflict")
        } catch {
            // expected — live file drifted from `after`
        }

        let untouched = try String(contentsOfFile: url.path, encoding: .utf8)
        XCTAssertEqual(untouched, "DRIFTED")
    }
}
