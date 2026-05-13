//
//  ProfileFormView.swift
//  Mimo
//

import SwiftUI

struct ProfileFormView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var managementViewModel: ManagementViewModel
    @StateObject private var viewModel = ProfileFormViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if managementViewModel.showProfileForm {
                    profileForm
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                existingProfilesList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: appModel.selectedProfileID) { _ in
            if managementViewModel.showProfileForm && !managementViewModel.isCreatingNewProfile {
                viewModel.loadProfile(currentProfile: appModel.selectedProfile)
            }
        }
        .onAppear {
            if appModel.availableProfiles.isEmpty {
                managementViewModel.showProfileForm = true
                managementViewModel.isCreatingNewProfile = true
            }
            viewModel.loadProfile(currentProfile: appModel.selectedProfile)
            viewModel.scanSSHKeys()
        }
        .onExitCommand {
            if managementViewModel.showProfileForm {
                withAnimation(MimoMotion.snap) {
                    managementViewModel.showProfileForm = false
                    managementViewModel.isCreatingNewProfile = false
                }
            }
        }
        .onChange(of: managementViewModel.isCreatingNewProfile) { isCreating in
            viewModel.isCreatingNewProfile = isCreating
            if isCreating { viewModel.resetForm() }
        }
        .onChange(of: managementViewModel.showProfileForm) { show in
            viewModel.showForm = show
        }
        .onChange(of: viewModel.showForm) { show in
            managementViewModel.showProfileForm = show
        }
        .onChange(of: viewModel.isCreatingNewProfile) { isCreating in
            managementViewModel.isCreatingNewProfile = isCreating
        }
        .animation(MimoMotion.snap, value: managementViewModel.showProfileForm)
    }

    // MARK: - Form

    @ViewBuilder
    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MimoMascot(
                    mood: viewModel.isFormValid ? .happy : .curious,
                    palette: previewPalette,
                    size: 40,
                    animateAmbient: false
                )
                .frame(width: 52, height: 56)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.isCreatingNewProfile ? "Meet your new identity" : "Editing identity")
                        .font(MimoFont.headline(14))
                        .foregroundStyle(MimoPalette.ink)
                    Text(viewModel.isCreatingNewProfile ? "Tell Mimo who you'd like to be." : "Update the details below.")
                        .font(MimoFont.caption(11))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }
                Spacer()
            }

            sectionLabel(Constants.Strings.identity)
            VStack(spacing: 10) {
                mimoField(label: Constants.Placeholder.profileName, text: $viewModel.profileName)
                mimoField(label: Constants.Placeholder.gitUserName, text: $viewModel.gitUserName)
                mimoField(label: Constants.Placeholder.gitEmail, text: $viewModel.gitEmail)
            }

            sectionLabel("Color")
            colorPicker

            sectionLabel(Constants.Strings.provider)
            Picker("", selection: $viewModel.selectedProvider) {
                ForEach(GitProvider.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.iconName).tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if viewModel.selectedProvider == .custom {
                mimoField(label: "Custom URL", text: $viewModel.providerURL)
            }

            sectionLabel(Constants.Label.sshKey)
            if viewModel.availableKeys.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: Constants.SystemImage.key)
                        .font(.system(size: 11))
                        .foregroundStyle(MimoPalette.inkTertiary)
                    Text(Constants.Strings.selectYourKey)
                        .font(MimoFont.body(12))
                        .foregroundStyle(MimoPalette.inkTertiary)
                }
            } else {
                Picker("", selection: $viewModel.selectedSSHKey) {
                    Text(Constants.Strings.selectYourKey).tag("")
                    ForEach(viewModel.availableKeys, id: \.self) { key in
                        Text((key as NSString).lastPathComponent).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            sectionLabel(Constants.Strings.signing)
            Picker("", selection: $viewModel.signingType) {
                ForEach(SigningType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if viewModel.signingType != .none {
                mimoField(label: "Signing Key ID", text: $viewModel.signingKey)
            }

            sectionLabel(Constants.Strings.credentialHelper)
            Picker("", selection: $viewModel.credentialHelper) {
                ForEach(CredentialHelper.allCases) { h in
                    Text(h.displayName).tag(h)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            HStack {
                Spacer()
                MimoPillButton(
                    title: viewModel.isCreatingNewProfile ? "Create profile" : Constants.Strings.saveChanges,
                    icon: viewModel.isCreatingNewProfile ? Constants.SystemImage.profileAdd : Constants.SystemImage.checkmark,
                    palette: previewPalette,
                    prominent: true
                ) {
                    viewModel.saveProfile(appModel: appModel, currentProfile: appModel.selectedProfile)
                }
                .disabled(!viewModel.isFormValid)
                .opacity(viewModel.isFormValid ? 1.0 : 0.55)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .mimoCard(cornerRadius: 22)
    }

    private var previewPalette: MimoPaintPalette {
        viewModel.colorID.palette
    }

    @ViewBuilder
    private var colorPicker: some View {
        HStack(spacing: 8) {
            ForEach(MimoProfileColor.allCases) { color in
                colorChip(color)
            }
        }
    }

    @ViewBuilder
    private func colorChip(_ color: MimoProfileColor) -> some View {
        let isSelected = viewModel.colorID == color
        Button {
            withAnimation(MimoMotion.snap) { viewModel.colorID = color }
        } label: {
            ZStack {
                Circle()
                    .fill(color.body)
                    .frame(width: isSelected ? 26 : 22, height: isSelected ? 26 : 22)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(color.body.opacity(isSelected ? 0.6 : 0), lineWidth: 1)
                            .padding(-3)
                    )
                    .shadow(color: color.body.opacity(isSelected ? 0.4 : 0), radius: 5)
            }
            .frame(width: 30, height: 30)
            .accessibilityLabel(color.displayName)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .buttonStyle(.plain)
        .mimoPress()
        .help(color.displayName)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(MimoFont.caption(10, weight: .bold))
            .foregroundStyle(MimoPalette.inkSecondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func mimoField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MimoFont.caption(10))
                .foregroundStyle(MimoPalette.inkTertiary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(MimoFont.body(12))
        }
    }

    // MARK: - List

    @ViewBuilder
    private var existingProfilesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appModel.availableProfiles) { profile in
                if !viewModel.showForm
                    || (viewModel.showForm && !viewModel.isCreatingNewProfile && appModel.selectedProfileID == profile.id) {
                    ProfileRowView(
                        viewModel: viewModel,
                        profile: profile,
                        isSelected: appModel.selectedProfileID == profile.id
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}
