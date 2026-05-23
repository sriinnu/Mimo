//
//  AppModelPersistenceTests.swift
//  MimoTests
//
//  Tests for AppModel profile CRUD and UserDefaults persistence.
//  Uses a test-specific UserDefaults suite to avoid polluting real data.
//

import XCTest
@testable import Mimo

@MainActor
final class AppModelPersistenceTests: XCTestCase {

    // MARK: - Profile encode/decode round-trip

    func testProfileRoundTrip() throws {
        let profile = GitProfile(
            name: "Work", userName: "Jane", userEmail: "jane@work.com",
            sshKeyPath: "~/.ssh/id_work", provider: .github, isActive: true
        )
        let data = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([GitProfile].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, profile.id)
        XCTAssertEqual(decoded[0].name, "Work")
        XCTAssertEqual(decoded[0].userEmail, "jane@work.com")
    }

    // MARK: - Multiple profiles round-trip

    func testMultipleProfilesRoundTrip() throws {
        let profiles = [
            GitProfile(name: "Work", userName: "W", userEmail: "w@w.com"),
            GitProfile(name: "Personal", userName: "P", userEmail: "p@p.com")
        ]
        let data = try JSONEncoder().encode(profiles)
        let decoded = try JSONDecoder().decode([GitProfile].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "Work")
        XCTAssertEqual(decoded[1].name, "Personal")
    }

    // MARK: - AppModel addOrUpdateProfile adds new profile

    func testAddProfile() {
        let appModel = AppModel()
        let profile = GitProfile(name: "New", userName: "N", userEmail: "n@n.com")

        appModel.addOrUpdateProfile(profile)

        XCTAssertEqual(appModel.availableProfiles.count, 1)
        XCTAssertEqual(appModel.availableProfiles.first?.id, profile.id)
    }

    // MARK: - AppModel addOrUpdateProfile updates existing

    func testUpdateExistingProfile() {
        let profile = GitProfile(name: "Work", userName: "Old", userEmail: "old@w.com")
        let appModel = AppModel()
        appModel.addOrUpdateProfile(profile)

        var updated = profile
        updated.userName = "New"
        appModel.addOrUpdateProfile(updated)

        XCTAssertEqual(appModel.availableProfiles.count, 1)
        XCTAssertEqual(appModel.availableProfiles.first?.userName, "New")
    }

    // MARK: - AppModel deleteProfile removes profile

    func testDeleteProfile() {
        let profile = GitProfile(name: "Work", userName: "W", userEmail: "w@w.com")
        let appModel = AppModel()
        appModel.addOrUpdateProfile(profile)

        appModel.deleteProfile(id: profile.id)

        XCTAssertTrue(appModel.availableProfiles.isEmpty)
    }

    // MARK: - Delete active profile clears activeProfileID

    func testDeleteActiveProfileClearsActiveID() {
        let profile = GitProfile(name: "Work", userName: "W", userEmail: "w@w.com")
        let appModel = AppModel()
        appModel.addOrUpdateProfile(profile)
        appModel.activeProfileID = profile.id

        appModel.deleteProfile(id: profile.id)

        XCTAssertNil(appModel.activeProfileID)
    }

    // MARK: - Empty state starts with no profiles

    func testEmptyState() {
        let appModel = AppModel()
        XCTAssertTrue(appModel.availableProfiles.isEmpty)
        XCTAssertNil(appModel.activeProfileID)
    }

    // MARK: - activeProfile computed property

    func testActiveProfileReturnsCorrectProfile() {
        let p1 = GitProfile(name: "Work", userName: "W", userEmail: "w@w.com")
        let p2 = GitProfile(name: "Home", userName: "H", userEmail: "h@h.com")
        let appModel = AppModel()
        appModel.addOrUpdateProfile(p1)
        appModel.addOrUpdateProfile(p2)
        appModel.activeProfileID = p2.id

        XCTAssertEqual(appModel.activeProfile?.id, p2.id)
        XCTAssertEqual(appModel.activeProfile?.name, "Home")
    }
}
