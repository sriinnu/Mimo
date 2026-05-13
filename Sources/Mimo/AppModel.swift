//
//  AppModel.swift
//  
//
// Created by Srinivas Pendela on 27/04/2026.
//

import SwiftUI
import Combine

@MainActor
final class AppModel: ObservableObject {

    // MARK: - Published State

    @Published var availableProfiles: [GitProfile] = []
    @Published var activeProfileID: UUID?
    @Published var directoryProfiles: [DirectoryProfile] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// Snapshot of the foreground app's working-directory + git context.
    /// Updated by `RepoStateService`; consumed (eventually) by views that
    /// surface mismatch warnings, mascot wince, identity-narration tooltips.
    @Published var foregroundRepoState: ForegroundRepoState = .empty

    // MARK: - Phantom Mode

    /// When non-nil, phantom mode is active. The value is the profile id we
    /// will switch back to after the next commit (or timeout). Set by
    /// `PhantomModeService.start`, cleared on revert/cancel.
    @Published var phantomReturnToID: UUID?

    /// Timestamp the phantom session started — used for the in-UI "returning
    /// to …" label and (eventually) telemetry. Cleared with `phantomReturnToID`.
    @Published var phantomStartedAt: Date?

    // MARK: - Services

    private let gitConfig = GitConfigService()
    private let sshService = SSHKeyService()
    private let includeIf = IncludeIfService()
    private let sshConfigService = SSHConfigService()

    // MARK: - Task Management

    private var loadTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Initialization

    func loadOnLaunch() {
        loadTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            loadSavedProfiles()
            loadSavedDirectoryProfiles()
            await importCurrentGitProfileIfNeeded()
            await detectActiveProfile()
            isLoading = false
        }
    }

    // MARK: - Profile Management

    func addOrUpdateProfile(_ profile: GitProfile) {
        if let index = availableProfiles.firstIndex(where: { $0.id == profile.id }) {
            availableProfiles[index] = profile
        } else {
            availableProfiles.append(profile)
        }
        saveProfiles()
    }

    func deleteProfile(id: UUID) {
        availableProfiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = nil
        }
        saveProfiles()
    }

    func switchProfile(to profile: GitProfile) async {
        isLoading = true
        errorMessage = nil

        do {
            try await gitConfig.applyProfile(profile)

            if let sshKeyPath = profile.sshKeyPath, !sshKeyPath.isEmpty {
                do {
                    try await sshService.addToAgent(privateKeyPath: sshKeyPath)
                } catch {
                    print("SSH-ADD failed: \(error.localizedDescription)")
                }
            }

            // Update SSH config host block
            try? await sshConfigService.applyHostBlock(
                for: profile,
                provider: profile.provider,
                allProfiles: availableProfiles
            )

            activeProfileID = profile.id
            syncActiveFlags()
            saveProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func detectActiveProfile() async {
        activeProfileID = await gitConfig.detectActiveProfile(
            from: availableProfiles
        )
        syncActiveFlags()
    }

    // MARK: - Management Window

    @Published var selectedManagementTab: Constants.ManagementTab = .profile
    @Published var selectedProfileID: UUID?

    var selectedProfile: GitProfile? {
        guard let id = selectedProfileID else {
            return availableProfiles.first
        }
        return availableProfiles.first { $0.id == id }
    }

    func openManagementWindow(tab: Constants.ManagementTab) {
        selectedManagementTab = tab
        ManagementWindowController.shared.showWindow(appModel: self)
    }

    // MARK: - Computed

    var activeProfile: GitProfile? {
        availableProfiles.first { $0.id == activeProfileID }
    }

    // MARK: - Import Current Git Config

    private func importCurrentGitProfileIfNeeded() async {
        guard availableProfiles.isEmpty else { return }

        let name = await gitConfig.currentUserName()
        let email = await gitConfig.currentUserEmail()

        guard let name, !name.isEmpty, let email, !email.isEmpty else { return }

        let profile = GitProfile(
            name: name,
            userName: name,
            userEmail: email,
            sshKeyPath: nil,
            isActive: true
        )
        availableProfiles.append(profile)
        activeProfileID = profile.id
        saveProfiles()
    }

    // MARK: - Directory Profiles

    func addDirectoryProfile(directoryPath: String, profileID: UUID) {
        let mapping = DirectoryProfile(directoryPath: directoryPath, profileID: profileID)
        directoryProfiles.append(mapping)
        saveDirectoryProfiles()
        Task {
            if let profile = availableProfiles.first(where: { $0.id == profileID }) {
                try? await includeIf.applyMapping(profile: profile, directoryPath: directoryPath)
            }
        }
    }

    func removeDirectoryProfile(id: UUID) {
        guard let mapping = directoryProfiles.first(where: { $0.id == id }) else { return }
        directoryProfiles.removeAll { $0.id == id }
        saveDirectoryProfiles()
        Task {
            try? await includeIf.removeMapping(directoryPath: mapping.directoryPath)
        }
    }

    // MARK: - Private Helpers

    private func syncActiveFlags() {
        for index in availableProfiles.indices {
            availableProfiles[index].isActive = (
                availableProfiles[index].id == activeProfileID
            )
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(availableProfiles) {
            UserDefaults.standard.set(
                data,
                forKey: Constants.Persistence.profilesKey
            )
        }
    }

    private func loadSavedProfiles() {
        guard
            let data = UserDefaults.standard.data(
                forKey: Constants.Persistence.profilesKey
            ),
            let profiles = try? JSONDecoder().decode(
                [GitProfile].self,
                from: data
            )
        else {
            return
        }
        availableProfiles = profiles
    }

    private func saveDirectoryProfiles() {
        if let data = try? JSONEncoder().encode(directoryProfiles) {
            UserDefaults.standard.set(data, forKey: Constants.Persistence.directoriesKey)
        }
    }

    private func loadSavedDirectoryProfiles() {
        guard
            let data = UserDefaults.standard.data(forKey: Constants.Persistence.directoriesKey),
            let dirs = try? JSONDecoder().decode([DirectoryProfile].self, from: data)
        else { return }
        directoryProfiles = dirs
    }
}
