//
//  MismatchResolveTests.swift
//  MimoTests
//
//  Tests for AppModel.resolveExpectedProfile() and the auto-switch setting.
//  Sets profile + foreground state in-memory (no persistence I/O) so it
//  doesn't touch real ~/.config/mimo or UserDefaults profile data.
//
//  Note: these compile against main today; they run once the MimoTests target
//  (added in the security/correctness PR) lands.
//

import XCTest
@testable import Mimo

@MainActor
final class MismatchResolveTests: XCTestCase {

    // MARK: - resolveExpectedProfile

    func testResolveReturnsExpectedProfile() {
        let appModel = AppModel()
        let work = GitProfile(name: "Work", userName: "W", userEmail: "w@work.com")
        appModel.availableProfiles = [work]
        appModel.foregroundRepoState = ForegroundRepoState(
            cwd: nil, repoRoot: nil, branch: nil, isDirty: false,
            expectedProfileID: work.id, activeProfileID: nil
        )

        XCTAssertEqual(appModel.resolveExpectedProfile()?.id, work.id)
    }

    func testResolveReturnsNilWhenNoExpected() {
        let appModel = AppModel()
        XCTAssertNil(appModel.resolveExpectedProfile())
    }

    func testResolveReturnsNilWhenExpectedIDNotInProfiles() {
        let appModel = AppModel()
        appModel.foregroundRepoState = ForegroundRepoState(
            cwd: nil, repoRoot: nil, branch: nil, isDirty: false,
            expectedProfileID: UUID(), activeProfileID: nil
        )

        XCTAssertNil(appModel.resolveExpectedProfile())
    }

    // MARK: - autoSwitchOnMismatch persistence

    func testAutoSwitchDefaultsOffAndPersists() {
        let key = Constants.Persistence.autoSwitchKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertFalse(AppModel().autoSwitchOnMismatch)

        let model = AppModel()
        model.autoSwitchOnMismatch = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }
}
