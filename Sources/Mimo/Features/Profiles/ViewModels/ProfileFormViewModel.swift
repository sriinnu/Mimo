//
//  ProfileFormViewModel.swift
//  Mimo
//

import SwiftUI

@MainActor
final class ProfileFormViewModel: ObservableObject {
    @Published var profileName: String = ""
    @Published var gitUserName: String = ""
    @Published var gitEmail: String = ""
    @Published var selectedSSHKey: String = ""
    @Published var availableKeys: [String] = []
    @Published var selectedProvider: GitProvider = .custom
    @Published var providerURL: String = ""
    @Published var signingType: SigningType = .none
    @Published var signingKey: String = ""
    @Published var credentialHelper: CredentialHelper = .osxkeychain
    @Published var colorID: MimoProfileColor = .sunshine

    @Published var isCreatingNewProfile: Bool = false
    @Published var showForm: Bool = false

    var isFormValid: Bool {
        !profileName.trimmingCharacters(in: .whitespaces).isEmpty
            && !gitUserName.trimmingCharacters(in: .whitespaces).isEmpty
            && !gitEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func loadProfile(currentProfile: GitProfile?) {
        guard let profile = currentProfile else { return }
        profileName = profile.name
        gitUserName = profile.userName
        gitEmail = profile.userEmail
        selectedSSHKey = profile.sshKeyPath ?? ""
        selectedProvider = profile.provider
        providerURL = profile.providerURL ?? ""
        signingType = profile.signingType
        signingKey = profile.signingKey ?? ""
        credentialHelper = profile.credentialHelper
        colorID = profile.colorID
    }

    func resetForm() {
        profileName = ""
        gitUserName = ""
        gitEmail = ""
        selectedSSHKey = ""
        selectedProvider = .custom
        providerURL = ""
        signingType = .none
        signingKey = ""
        credentialHelper = .osxkeychain
        // Pick a fresh random suggestion so back-to-back new profiles get
        // visually distinct mascot tints out of the gate.
        colorID = MimoProfileColor.allCases.randomElement() ?? .sunshine
    }

    func saveProfile(appModel: AppModel, currentProfile: GitProfile?) {
        if isCreatingNewProfile {
            let newProfile = GitProfile(
                name: profileName,
                userName: gitUserName,
                userEmail: gitEmail,
                sshKeyPath: selectedSSHKey.isEmpty ? nil : selectedSSHKey,
                provider: selectedProvider,
                providerURL: providerURL.isEmpty ? nil : providerURL,
                signingType: signingType,
                credentialHelper: credentialHelper,
                colorID: colorID
            )
            appModel.addOrUpdateProfile(newProfile)
            appModel.selectedProfileID = newProfile.id
            withAnimation {
                isCreatingNewProfile = false
                showForm = false
            }
        } else {
            guard let existing = currentProfile else { return }
            var updated = existing
            updated.name = profileName
            updated.userName = gitUserName
            updated.userEmail = gitEmail
            updated.sshKeyPath = selectedSSHKey.isEmpty ? nil : selectedSSHKey
            updated.provider = selectedProvider
            updated.providerURL = providerURL.isEmpty ? nil : providerURL
            updated.signingType = signingType
            updated.signingKey = signingKey.isEmpty ? nil : signingKey
            updated.credentialHelper = credentialHelper
            updated.colorID = colorID
            appModel.addOrUpdateProfile(updated)
            withAnimation {
                showForm = false
            }
        }
    }

    func scanSSHKeys() {
        let service = SSHKeyService()
        Task { [weak self] in
            if let keys = try? await service.scanKeys() {
                if !Task.isCancelled {
                    self?.availableKeys = keys.map(\.privateKeyPath)
                }
            }
        }
    }

    func toggleFormState(appModel: AppModel) {
        withAnimation(.easeInOut(duration: Constants.Animation.defaultDuration)) {
            if !showForm {
                showForm = true
                isCreatingNewProfile = true
                resetForm()
            } else if isCreatingNewProfile {
                showForm = false
                isCreatingNewProfile = false
            } else {
                isCreatingNewProfile = true
                resetForm()
            }
        }
    }
}
