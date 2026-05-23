//
//  SSHConfigServiceTests.swift
//  MimoTests
//
//  Tests for SSH config marker-based host block parsing and manipulation.
//  Calls the real SSHConfigService static methods via @testable import.
//

import XCTest
@testable import Mimo

final class SSHConfigServiceTests: XCTestCase {

    // MARK: - Extract block by marker

    func testExtractBlockFindsMarkerAndHost() {
        let id = UUID()
        let content = """
        Host existing.com
            HostName existing.com

        # Mimo:\(id.uuidString)
        Host github.com
            HostName github.com
            IdentityFile ~/.ssh/id_work
            User git
        """
        let block = SSHConfigService.extractBlock(for: id, from: content)
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Host github.com"))
        XCTAssertTrue(block!.contains("# Mimo:\(id.uuidString)"))
    }

    // MARK: - Extract block returns nil for missing marker

    func testExtractBlockReturnsNilForMissingMarker() {
        let content = "Host github.com\n    HostName github.com\n"
        XCTAssertNil(SSHConfigService.extractBlock(for: UUID(), from: content))
    }

    // MARK: - Block replacement is idempotent

    func testReplaceBlockDoesNotDuplicate() {
        let id = UUID()
        let tag = "# Mimo:\(id.uuidString)"
        let block = "\(tag)\nHost github.com\n    HostName github.com\n    User git\n"
        var content = "\n\n\(block)"

        let newBlock = "\(tag)\nHost github.com\n    HostName github.com\n    IdentityFile newkey\n    User git\n"
        if let existing = SSHConfigService.extractBlock(for: id, from: content) {
            content = content.replacingOccurrences(of: existing, with: newBlock)
        }
        XCTAssertEqual(content.components(separatedBy: tag).count - 1, 1)
    }

    // MARK: - Block removal leaves config clean

    func testRemoveBlockCleansUp() {
        let id = UUID()
        let tag = "# Mimo:\(id.uuidString)"
        let content = "Host other.com\n    HostName other.com\n\n\(tag)\nHost github.com\n    HostName github.com\n    User git\n"

        let cleaned = SSHConfigService.removeBlock(for: id, from: content)
        XCTAssertFalse(cleaned.contains(tag))
        XCTAssertTrue(cleaned.contains("Host other.com"), "Other blocks should remain")
    }

    // MARK: - Empty config handles block insert

    func testEmptyConfigHandlesInsert() {
        let id = UUID()
        let tag = "# Mimo:\(id.uuidString)"
        let block = "\(tag)\nHost github.com\n    HostName github.com\n    User git\n"
        let result = "\n\n" + block
        XCTAssertTrue(result.contains(tag))
        XCTAssertTrue(result.contains("Host github.com"))
    }

    // MARK: - Parse readConfig entries

    func testParseEntries() {
        let content = """
        Host github.com
            HostName github.com
            IdentityFile ~/.ssh/id_ed25519
            User git

        Host gitlab.com
            HostName gitlab.com
            IdentityFile ~/.ssh/id_gl
            User git
        """
        let entries = SSHConfigService.parseConfig(content)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].host, "github.com")
        XCTAssertEqual(entries[0].hostName, "github.com")
        XCTAssertEqual(entries[1].host, "gitlab.com")
    }
}
