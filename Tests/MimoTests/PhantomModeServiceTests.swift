//
//  PhantomModeServiceTests.swift
//  MimoTests
//
//  Tests for phantom mode state transitions. PhantomModeService is
//  @MainActor with a private init (singleton), so we use .shared
//  and clean up state in tearDown.
//

import XCTest
@testable import Mimo

@MainActor
final class PhantomModeServiceTests: XCTestCase {

    private var service: PhantomModeService { .shared }

    override func tearDown() {
        let appModel = AppModel()
        service.clearOnLaunch(appModel: appModel)
    }

    // MARK: - clearOnLaunch resets all state

    func testClearOnLaunchResetsState() {
        service.phantomReturnToID = UUID()
        service.phantomStartedAt = Date()

        let appModel = AppModel()
        service.clearOnLaunch(appModel: appModel)

        XCTAssertNil(service.phantomReturnToID)
        XCTAssertNil(service.phantomStartedAt)
    }

    // MARK: - clearOnLaunch cancels poll task

    func testClearOnLaunchCancelsPollTask() {
        let appModel = AppModel()
        service.clearOnLaunch(appModel: appModel)
        XCTAssertFalse(service.isActive)
    }

    // MARK: - cancel clears return-to state

    func testCancelClearsPhantomState() {
        service.phantomReturnToID = UUID()
        service.phantomStartedAt = Date()

        let appModel = AppModel()
        service.cancel(appModel: appModel)

        XCTAssertNil(service.phantomReturnToID)
        XCTAssertNil(service.phantomStartedAt)
    }

    // MARK: - cancel with matching profile triggers revert

    func testCancelWithReturnProfileTriggersSwitch() async {
        let returnID = UUID()
        let returnProfile = GitProfile(id: returnID, name: "Original",
                                        userName: "O", userEmail: "o@o.com")
        service.phantomReturnToID = returnID
        service.phantomStartedAt = Date()

        let appModel = AppModel()
        appModel.addOrUpdateProfile(returnProfile)
        service.cancel(appModel: appModel)

        // Give the dispatched Task a moment to run
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(service.phantomReturnToID)
    }

    // MARK: - cancel with no matching profile is safe

    func testCancelWithMissingProfileIsSafe() {
        service.phantomReturnToID = UUID() // non-existent
        service.phantomStartedAt = Date()

        let appModel = AppModel()
        service.cancel(appModel: appModel)

        XCTAssertNil(service.phantomReturnToID)
    }

    // MARK: - isActive false after clear

    func testIsActiveFalseAfterClear() {
        let appModel = AppModel()
        service.clearOnLaunch(appModel: appModel)
        XCTAssertFalse(service.isActive)
    }

    // MARK: - phantomStartedAt is nil after cancel

    func testPhantomStartedAtCleared() {
        service.phantomStartedAt = Date()
        let appModel = AppModel()
        service.cancel(appModel: appModel)
        XCTAssertNil(service.phantomStartedAt)
    }
}
