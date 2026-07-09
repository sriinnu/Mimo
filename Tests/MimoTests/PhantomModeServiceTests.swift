//
//  PhantomModeServiceTests.swift
//  MimoTests
//
//  Tests for phantom mode state transitions. PhantomModeService is @MainActor
//  with a private init (singleton), so we use .shared. The phantom *state*
//  (phantomReturnToID / phantomStartedAt) lives on AppModel — the service
//  only drives it — so assertions read from appModel.
//

import XCTest
@testable import Mimo

@MainActor
final class PhantomModeServiceTests: XCTestCase {

    private var service: PhantomModeService { .shared }

    private func makeModel() -> AppModel {
        AppModel(configDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-phantom-\(UUID().uuidString)"))
    }

    // MARK: - clearOnLaunch resets all state

    func testClearOnLaunchResetsState() {
        let appModel = makeModel()
        appModel.phantomReturnToID = UUID()
        appModel.phantomStartedAt = Date()

        service.clearOnLaunch(appModel: appModel)

        XCTAssertNil(appModel.phantomReturnToID)
        XCTAssertNil(appModel.phantomStartedAt)
    }

    // MARK: - clearOnLaunch cancels poll task

    func testClearOnLaunchCancelsPollTask() {
        let appModel = makeModel()
        service.clearOnLaunch(appModel: appModel)
        XCTAssertFalse(service.isActive)
    }

    // MARK: - cancel clears return-to state (no matching profile → no switch)

    func testCancelClearsPhantomState() {
        let appModel = makeModel()
        appModel.phantomReturnToID = UUID()
        appModel.phantomStartedAt = Date()

        service.cancel(appModel: appModel)

        XCTAssertNil(appModel.phantomReturnToID)
        XCTAssertNil(appModel.phantomStartedAt)
    }

    // MARK: - cancel with matching profile triggers a real git switch
    //
    // Skipped in unit tests: switchProfile writes to the real ~/.gitconfig.
    // Cover via an integration harness with an injectable GitConfigService.

    func testCancelWithReturnProfileTriggersSwitch() throws {
        throw XCTSkip("requires real git-config writes; cover via integration harness")
    }

    // MARK: - cancel with no matching profile is safe

    func testCancelWithMissingProfileIsSafe() {
        let appModel = makeModel()
        appModel.phantomReturnToID = UUID() // non-existent
        appModel.phantomStartedAt = Date()

        service.cancel(appModel: appModel)

        XCTAssertNil(appModel.phantomReturnToID)
    }

    // MARK: - isActive false after clear

    func testIsActiveFalseAfterClear() {
        let appModel = makeModel()
        service.clearOnLaunch(appModel: appModel)
        XCTAssertFalse(service.isActive)
    }

    // MARK: - phantomStartedAt is nil after cancel

    func testPhantomStartedAtCleared() {
        let appModel = makeModel()
        appModel.phantomStartedAt = Date()
        service.cancel(appModel: appModel)
        XCTAssertNil(appModel.phantomStartedAt)
    }
}
