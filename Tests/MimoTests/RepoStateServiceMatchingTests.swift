//
//  RepoStateServiceMatchingTests.swift
//  MimoTests
//
//  Tests for the longest-prefix matching logic that maps directory paths
//  to profile IDs. The method is static on RepoStateService.
//

import XCTest
@testable import Mimo

@MainActor
final class RepoStateServiceMatchingTests: XCTestCase {

    private func mapping(directoryPath: String, profileID: UUID) -> DirectoryProfile {
        DirectoryProfile(directoryPath: directoryPath, profileID: profileID)
    }

    // MARK: - Exact match

    func testExactPathMatch() {
        let id = UUID()
        let result = RepoStateService.expectedProfile(
            for: "/Users/foo/work",
            in: [mapping(directoryPath: "/Users/foo/work", profileID: id)]
        )
        XCTAssertEqual(result, id)
    }

    // MARK: - Prefix match

    func testPrefixMatch() {
        let id = UUID()
        let result = RepoStateService.expectedProfile(
            for: "/Users/foo/work/project-x",
            in: [mapping(directoryPath: "/Users/foo/work", profileID: id)]
        )
        XCTAssertEqual(result, id)
    }

    // MARK: - Non-match (no trailing-slash bleed)

    func testWorkdayDoesNotMatchWork() {
        let id = UUID()
        XCTAssertNil(RepoStateService.expectedProfile(
            for: "/Users/foo/workday/project",
            in: [mapping(directoryPath: "/Users/foo/work", profileID: id)]
        ))
    }

    // MARK: - Deepest match wins

    func testDeepestMatchWins() {
        let shallowID = UUID()
        let deepID = UUID()
        let result = RepoStateService.expectedProfile(
            for: "/Users/foo/work/client-a/repo",
            in: [
                mapping(directoryPath: "/Users/foo/work", profileID: shallowID),
                mapping(directoryPath: "/Users/foo/work/client-a", profileID: deepID)
            ]
        )
        XCTAssertEqual(result, deepID)
    }

    // MARK: - Empty mappings

    func testEmptyMappingsReturnsNil() {
        XCTAssertNil(RepoStateService.expectedProfile(for: "/Users/foo/work", in: []))
    }

    // MARK: - Tilde expansion

    func testTildeExpansion() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let id = UUID()
        let result = RepoStateService.expectedProfile(
            for: home + "/work/repo",
            in: [mapping(directoryPath: "~/work", profileID: id)]
        )
        XCTAssertEqual(result, id)
    }

    // MARK: - Trailing slash normalization

    func testTrailingSlashOnMapping() {
        let id = UUID()
        let result = RepoStateService.expectedProfile(
            for: "/Users/foo/work/repo",
            in: [mapping(directoryPath: "/Users/foo/work/", profileID: id)]
        )
        XCTAssertEqual(result, id)
    }

    // MARK: - No match falls through

    func testNoMatchReturnsNil() {
        let id = UUID()
        XCTAssertNil(RepoStateService.expectedProfile(
            for: "/Users/foo/personal/repo",
            in: [mapping(directoryPath: "/Users/foo/work", profileID: id)]
        ))
    }
}
