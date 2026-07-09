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

    private let firstRunSeenKey = "com.sriinnu.mimo.firstRunSeen"

    // MARK: - Storage root
    //
    // Overridable so tests can point persistence at a temp dir instead of
    // clobbering the developer's real ~/.config/mimo/profiles.json. Defaults
    // to the real location for production.
    private let secureConfigDirURL: URL

    /// - parameter configDir: where profile/directory JSON is stored. Tests
    ///   pass a throwaway directory; production leaves it nil for the default.
    init(configDir: URL? = nil) {
        self.secureConfigDirURL = configDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mimo")
    }

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
        writeSecureJSON(availableProfiles, to: "profiles.json")
    }

    /// Reloads profiles from disk. Internal so tests can verify file-backed
    /// round-trips across fresh AppModel instances.
    func loadSavedProfiles() {
        if let profiles = readSecureJSON(
            [GitProfile].self,
            from: "profiles.json",
            legacyKey: Constants.Persistence.profilesKey
        ) {
            availableProfiles = profiles
        }
    }

    private func saveDirectoryProfiles() {
        writeSecureJSON(directoryProfiles, to: "directories.json")
    }

    private func loadSavedDirectoryProfiles() {
        if let dirs = readSecureJSON(
            [DirectoryProfile].self,
            from: "directories.json",
            legacyKey: Constants.Persistence.directoriesKey
        ) {
            directoryProfiles = dirs
        }
    }

    // MARK: - Secure persistence helpers
    //
    // Profiles carry emails, GPG key ids, SSH key paths, and provider URLs —
    // identity metadata. That belongs in a mode-0600 file under ~/.config/mimo
    // (where the audit log already lives), not the world-readable UserDefaults
    // plist. On first read after this change, legacy UserDefaults data is
    // migrated to the file; the file wins on every subsequent load.

    private var secureConfigDir: URL {
        secureConfigDirURL
    }

    private func writeSecureJSON<T: Encodable>(_ value: T, to filename: String) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: secureConfigDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let url = secureConfigDir.appendingPathComponent(filename)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            print("[AppModel] failed to persist \(filename): \(error.localizedDescription)")
        }
    }

    private func readSecureJSON<T: Codable>(
        _ type: T.Type,
        from filename: String,
        legacyKey: String
    ) -> T? {
        let url = secureConfigDir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(type, from: data) {
            return decoded
        }
        // Legacy fallback — older builds kept profiles in UserDefaults. Migrate
        // to the 0600 file on first hit. We leave the legacy key in place; the
        // file takes precedence from here on, so a stale plist is harmless and
        // wiping it on a failed write could lose data.
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode(type, from: data) {
            writeSecureJSON(decoded, to: filename)
            return decoded
        }
        return nil
    }
}
