//
//  CloneServiceTests.swift
//  MimoTests
//
//  Tests for provider detection using URL host matching
//  and profile matching logic.
//

import XCTest
@testable import Mimo

final class CloneServiceTests: XCTestCase {

    private let service = CloneService()

    // MARK: - Correct detections

    func testGitHubHTTPS() async {
        let result = await service.detectProvider(from: "https://github.com/org/repo.git")
        XCTAssertEqual(result, .github)
    }

    func testGitHubSSH() async {
        let result = await service.detectProvider(from: "git@github.com:org/repo.git")
        XCTAssertEqual(result, .github)
    }

    func testAzureDevOpsHTTPS() async {
        let result = await service.detectProvider(from: "https://dev.azure.com/org/proj/_git/repo")
        XCTAssertEqual(result, .azureDevOps)
    }

    func testAzureDevOpsSSH() async {
        let result = await service.detectProvider(from: "git@ssh.dev.azure.com:v3/org/proj/repo")
        XCTAssertEqual(result, .azureDevOps)
    }

    func testGitLabHTTPS() async {
        let result = await service.detectProvider(from: "https://gitlab.com/org/repo.git")
        XCTAssertEqual(result, .gitlab)
    }

    func testBitbucketHTTPS() async {
        let result = await service.detectProvider(from: "https://bitbucket.org/org/repo.git")
        XCTAssertEqual(result, .bitbucket)
    }

    // MARK: - Custom / unknown

    func testCustomURL() async {
        let result = await service.detectProvider(from: "https://git.mycompany.com/org/repo.git")
        XCTAssertEqual(result, .custom)
    }

    func testEmptyURL() async {
        let result = await service.detectProvider(from: "")
        XCTAssertEqual(result, .custom)
    }

    // MARK: - Spoof resistance

    func testSpoofedGitHubSubdomainIsCustom() async {
        let result = await service.detectProvider(from: "https://evil.github.com.attacker.com/repo.git")
        XCTAssertEqual(result, .custom)
    }

    func testGitHubInPathIsCustom() async {
        let result = await service.detectProvider(from: "https://notgithub.com/github.com/repo.git")
        XCTAssertEqual(result, .custom)
    }

    // MARK: - Profile matching

    func testFindProfileForProvider() async {
        let profile = GitProfile(name: "Work", userName: "W", userEmail: "w@w.com", provider: .github)
        let profiles = [
            GitProfile(name: "Personal", userName: "P", userEmail: "p@p.com", provider: .custom),
            profile
        ]
        let found = await service.findProfile(for: .github, profiles: profiles)
        XCTAssertEqual(found?.id, profile.id)
    }

    func testFindProfileReturnsNilWhenNoMatch() async {
        let profiles = [
            GitProfile(name: "Personal", userName: "P", userEmail: "p@p.com", provider: .custom)
        ]
        let found = await service.findProfile(for: .github, profiles: profiles)
        XCTAssertNil(found)
    }
}
