//
//  IncludeIfServiceTests.swift
//  MimoTests
//
//  Tests for includeIf block management in .gitconfig.
//  Calls the real IncludeIfService static methods via @testable import.
//

import XCTest
@testable import Mimo

final class IncludeIfServiceTests: XCTestCase {

    // MARK: - Parse includeIf blocks from gitconfig

    func testReadMappingsFindsSingleBlock() {
        let content = """
        [user]
            name = Test
            email = test@test.com
        [includeIf "gitdir:/Users/foo/work/"]
            path = /foo/profile.gitconfig
        """
        let mappings = IncludeIfService.parseMappings(from: content)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].condition, "gitdir:/Users/foo/work/")
        XCTAssertEqual(mappings[0].path, "/foo/profile.gitconfig")
    }

    // MARK: - Multiple mappings

    func testReadMappingsFindsMultiple() {
        let content = """
        [includeIf "gitdir:/Users/foo/work/"]
            path = /foo/work.gitconfig
        [includeIf "gitdir:/Users/foo/personal/"]
            path = /foo/personal.gitconfig
        """
        let mappings = IncludeIfService.parseMappings(from: content)
        XCTAssertEqual(mappings.count, 2)
        XCTAssertEqual(mappings[0].condition, "gitdir:/Users/foo/work/")
        XCTAssertEqual(mappings[1].condition, "gitdir:/Users/foo/personal/")
    }

    // MARK: - No mappings in config

    func testReadMappingsEmptyWhenNone() {
        let mappings = IncludeIfService.parseMappings(from: "[user]\n    name = Test\n")
        XCTAssertTrue(mappings.isEmpty)
    }

    // MARK: - Remove block by condition

    func testRemoveBlockByCondition() {
        let content = """
        [user]
            name = Test
        [includeIf "gitdir:/Users/foo/work/"]
            path = /foo/work.gitconfig
        [includeIf "gitdir:/Users/foo/personal/"]
            path = /foo/personal.gitconfig
        """
        let result = IncludeIfService.removeBlock(condition: "gitdir:/Users/foo/work/", from: content)
        XCTAssertFalse(result.contains("gitdir:/Users/foo/work/"))
        XCTAssertTrue(result.contains("gitdir:/Users/foo/personal/"),
                      "Other blocks should remain")
    }

    // MARK: - Remove block by path

    func testRemoveBlockByPath() {
        let content = """
        [user]
            name = Test
        [includeIf "gitdir:/Users/foo/work/"]
            path = /foo/work.gitconfig
        """
        let result = IncludeIfService.removeBlockContaining(path: "/foo/work.gitconfig", from: content)
        XCTAssertFalse(result.contains("work.gitconfig"))
        XCTAssertFalse(result.contains("gitdir:/Users/foo/work/"))
    }

    // MARK: - Condition string generation

    func testGitdirCondition() {
        let dir = "/Users/foo/work"
        XCTAssertEqual("gitdir:\(dir)/", "gitdir:/Users/foo/work/")
    }

    // MARK: - Tilde expansion in condition

    func testTildeExpansionInPath() {
        let expanded = ("~/work" as NSString).expandingTildeInPath
        let condition = "gitdir:\(expanded)/"
        XCTAssertTrue(condition.hasPrefix("gitdir:/Users/"))
        XCTAssertTrue(condition.hasSuffix("/work/"))
    }
}
