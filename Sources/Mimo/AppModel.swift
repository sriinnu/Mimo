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

    // MARK: - First-Run Onboarding

    /// Non-nil when the user has no profiles yet AND we found an existing
    /// `~/.gitconfig` identity. The management window observes this and
    /// presents the onboarding sheet so the user can opt-in (or skip)
    /// instead of Mimo silently overwriting their config later.
    @Published var pendingFirstRunSnapshot: GitIdentitySnapshot?

    /// When on, Mimo switches to the expected profile the moment it detects a
    /// foreground repo whose mapped identity differs from the active one — no
    /// tap required. Default off: the mismatch card's "Switch to …" button is
    /// the safe default; auto-switch is opt-in for people who want the guard.
    @Published var autoSwitchOnMismatch: Bool = UserDefaults.standard.bool(
        forKey: Constants.Persistence.autoSwitchKey
    ) {
        didSet {
            guard oldValue != autoSwitchOnMismatch else { return }
            UserDefaults.standard.set(autoSwitchOnMismatch, forKey: Constants.Persistence.autoSwitchKey)
            // Clear the dedup guard on disable so re-enabling fires again.
            if !autoSwitchOnMismatch { lastAutoSwitchedExpected = nil }
        }
    }

    private let firstRunSeenKey = "com.sriinnu.mimo.firstRunSeen"

    // MARK: - Services

    private let gitConfig = GitConfigService()
    private let sshService = SSHKeyService()
    private let includeIf = IncludeIfService()
    private let sshConfigService = SSHConfigService()

    // MARK: - Task Management

    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Dedup guard for auto-switch — the expected-profile id we last
    /// auto-switched to. Stops us re-triggering while a mismatch persists and
    /// lets a later, different mismatch fire again.
    private var lastAutoSwitchedExpected: UUID?

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Initialization

    func loadOnLaunch() {
        // Subscribe to mismatch state once so auto-switch can fire whenever a
        // fresh mismatch appears and the setting is on.
        setupMismatchAutoSwitch()

        loadTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            loadSavedProfiles()
            loadSavedDirectoryProfiles()
            await IdentityAuditLog.shared.reload()
            await prepareFirstRunIfNeeded()
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
        let profile = availableProfiles.first { $0.id == id }
        availableProfiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = nil
        }
        saveProfiles()

        Task {
            // 1. Remove per-profile gitconfig file
            let profileConfigPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mimo/profiles/\(id.uuidString).gitconfig")
            try? FileManager.default.removeItem(at: profileConfigPath)

            // 2. Remove includeIf block from ~/.gitconfig
            try? await IncludeIfService().removeMapping(for: id)

            // 3. Remove SSH config host block (needs a GitProfile for the marker)
            if let profile {
                var tempProfile = profile
                tempProfile.sshKeyPath = profile.sshKeyPath ?? ""
                try? await SSHConfigService().removeHostBlock(for: tempProfile)
            }
        }
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

    // MARK: - Mismatch resolution

    /// The profile the foreground repo expects, or nil if none mapped.
    func resolveExpectedProfile() -> GitProfile? {
        guard let id = foregroundRepoState.expectedProfileID else { return nil }
        return availableProfiles.first { $0.id == id }
    }

    /// Switch to whatever the foreground repo expects. No-op if nothing's
    /// mapped. Used by the opt-in auto-switch path.
    func switchToExpectedProfile() async {
        guard let expected = resolveExpectedProfile() else { return }
        await switchProfile(to: expected)
    }

    /// Watches foreground repo state. When a fresh mismatch appears and
    /// auto-switch is on, flips to the expected profile exactly once per
    /// expected id — no thrashing on every poll.
    private func setupMismatchAutoSwitch() {
        $foregroundRepoState
            .filter { $0.hasMismatch }
            .compactMap { $0.expectedProfileID }
            .removeDuplicates()
            .sink { [weak self] expectedID in
                guard let self else { return }
                guard self.autoSwitchOnMismatch, expectedID != self.lastAutoSwitchedExpected else { return }
                self.lastAutoSwitchedExpected = expectedID
                Task { await self.switchToExpectedProfile() }
            }
            .store(in: &cancellables)
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

    // MARK: - First-Run Import

    /// First-launch flow. If the user has no profiles yet and we haven't
    /// already shown the onboarding once, snapshot the existing
    /// `~/.gitconfig` identity. The view layer presents a sheet so the
    /// user decides whether to import — Mimo never writes anything
    /// silently here. Before this existed, Mimo would auto-create a
    /// profile from `user.name` + `user.email`, then the first profile
    /// switch would unset `commit.gpgSign` and `user.signingkey`.
    private func prepareFirstRunIfNeeded() async {
        guard availableProfiles.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: firstRunSeenKey) else { return }

        let snapshot = await gitConfig.currentIdentitySnapshot()
        guard snapshot.hasMinimumForProfile else {
            // Nothing useful to import — mark seen and move on so we
            // don't keep asking on every launch of a fresh-config machine.
            UserDefaults.standard.set(true, forKey: firstRunSeenKey)
            return
        }

        pendingFirstRunSnapshot = snapshot
    }

    /// Called by the onboarding sheet when the user accepts the import.
    /// Builds a profile from the snapshot, persists it, audits the moment,
    /// and clears the pending state.
    func acceptFirstRunImport() {
        guard let snapshot = pendingFirstRunSnapshot,
              let name = snapshot.userName,
              let email = snapshot.userEmail
        else { return }

        let profile = GitProfile(
            name: name,
            userName: name,
            userEmail: email,
            signingKey: snapshot.signingKey,
            sshKeyPath: snapshot.sshKeyPath,
            signingType: snapshot.signingType,
            isActive: true
        )
        availableProfiles.append(profile)
        activeProfileID = profile.id
        saveProfiles()

        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: profile.id,
                profileName: profile.name,
                scope: .firstRunImport,
                summary: "imported existing identity: \(name) <\(email)>",
                before: nil,
                after: "\(name) <\(email)>"
            )
        )

        UserDefaults.standard.set(true, forKey: firstRunSeenKey)
        pendingFirstRunSnapshot = nil
    }

    /// Called by the onboarding sheet when the user picks "start blank".
    /// Records the moment in audit so the user can see they declined.
    func skipFirstRunImport() {
        IdentityAuditLog.shared.record(
            AuditEntry(
                profileID: nil,
                profileName: "Mimo",
                scope: .firstRunImport,
                summary: "user chose to start with no profiles",
                before: nil,
                after: nil
            )
        )
        UserDefaults.standard.set(true, forKey: firstRunSeenKey)
        pendingFirstRunSnapshot = nil
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
