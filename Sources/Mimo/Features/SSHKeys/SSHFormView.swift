//
//  SSHFormView.swift
//  Mimo
//

import SwiftUI

struct SSHFormView: View {
    @EnvironmentObject private var managementViewModel: ManagementViewModel
    @EnvironmentObject private var viewModel: SSHKeysViewModel
    @StateObject private var formViewModel = SSHFormViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if managementViewModel.showNewSSHKeyForm {
                    newKeyForm
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                existingKeysList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { viewModel.loadKeys() }
        .onExitCommand {
            if managementViewModel.showNewSSHKeyForm {
                withAnimation(MimoMotion.snap) {
                    managementViewModel.showNewSSHKeyForm = false
                }
            }
        }
        .animation(MimoMotion.snap, value: managementViewModel.showNewSSHKeyForm)
        .alert(
            "Delete SSH Key?",
            isPresented: $viewModel.showDeleteConfirmation,
            presenting: viewModel.keyToDelete
        ) { _ in
            Button("Delete", role: .destructive) { viewModel.deleteKey() }
            Button("Cancel", role: .cancel) { viewModel.keyToDelete = nil }
        } message: { key in
            Text("Are you sure you want to delete '\(key.filename)'? This will permanently remove the key file from your ~/.ssh directory.")
        }
    }

    // MARK: - Form

    @ViewBuilder
    private var newKeyForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MimoMascot(
                    mood: formViewModel.errorMessage != nil ? .worried : .curious,
                    palette: palette(for: formViewModel.selectedKeyType),
                    size: 38,
                    animateAmbient: false
                )
                .frame(width: 50, height: 54)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Spin up a new key")
                        .font(MimoFont.headline(14))
                        .foregroundStyle(MimoPalette.ink)
                    Text("Mimo will drop it into ~/.ssh for you.")
                        .font(MimoFont.caption(11))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }
                Spacer()

                Button {
                    viewModel.importKey()
                    withAnimation(MimoMotion.snap) {
                        managementViewModel.showNewSSHKeyForm = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Import existing")
                            .font(MimoFont.caption(11, weight: .semibold))
                    }
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MimoPalette.surfaceSunken)
                    )
                }
                .buttonStyle(.plain)
                .mimoPress()
                .help("Import an existing private key from disk")
            }

            sectionLabel(Constants.Strings.type)
            HStack(spacing: 8) {
                ForEach([SSHKeyType.ed25519, SSHKeyType.rsa], id: \.self) { keyType in
                    keyTypePill(keyType)
                }
            }

            mimoField(label: Constants.Strings.email, text: $formViewModel.email, placeholder: Constants.Placeholder.email)
            mimoField(label: Constants.Strings.file, text: $formViewModel.filename, placeholder: Constants.Placeholder.filename)
            mimoSecureField(label: Constants.Strings.passphrase, text: $formViewModel.passphrase, placeholder: Constants.Placeholder.passphrase)

            HStack {
                Spacer()
                MimoPillButton(
                    title: Constants.Strings.generateKey,
                    icon: Constants.SystemImage.generateKey,
                    palette: palette(for: formViewModel.selectedKeyType),
                    prominent: true
                ) {
                    formViewModel.generateKey {
                        viewModel.loadKeys()
                        withAnimation(MimoMotion.snap) {
                            managementViewModel.showNewSSHKeyForm = false
                        }
                    }
                }
                .disabled(formViewModel.email.isEmpty || formViewModel.filename.isEmpty)
                .opacity((formViewModel.email.isEmpty || formViewModel.filename.isEmpty) ? 0.55 : 1.0)
            }

            statusMessages
        }
        .padding(20)
        .mimoCard(cornerRadius: 22)
    }

    @ViewBuilder
    private func keyTypePill(_ keyType: SSHKeyType) -> some View {
        let isSelected = formViewModel.selectedKeyType == keyType
        let pillPalette = palette(for: keyType)

        Button {
            withAnimation(MimoMotion.snap) {
                formViewModel.selectedKeyType = keyType
            }
        } label: {
            Text(keyType.displayName)
                .font(MimoFont.caption(11, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : MimoPalette.inkSecondary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? pillPalette.body : MimoPalette.surfaceSunken)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? .clear : MimoPalette.shadow.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = formViewModel.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: Constants.SystemImage.warning)
                    .font(.system(size: 11, weight: .semibold))
                Text(error)
                    .font(MimoFont.caption(11))
            }
            .foregroundStyle(MimoEmotion.anger.body)
        }

        if let status = formViewModel.statusMessage ?? viewModel.statusMessage {
            HStack(spacing: 6) {
                Image(systemName: Constants.SystemImage.checkmark)
                    .font(.system(size: 11, weight: .semibold))
                Text(status)
                    .font(MimoFont.caption(11))
            }
            .foregroundStyle(MimoEmotion.serenity.body)
        }
    }

    private func palette(for keyType: SSHKeyType) -> MimoPaintPalette {
        let emotion: MimoEmotion
        switch keyType {
        case .ed25519: emotion = .joy
        case .rsa:     emotion = .fear
        case .ecdsa:   emotion = .serenity
        case .dsa:     emotion = .anger
        }
        return emotion.palette
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(MimoFont.caption(10, weight: .bold))
            .foregroundStyle(MimoPalette.inkSecondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func mimoField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MimoFont.caption(10))
                .foregroundStyle(MimoPalette.inkTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(MimoFont.body(12))
        }
    }

    /// Masked variant for secrets — passphrase. Same shape as `mimoField` but
    /// renders a SecureField so the value isn't shown in cleartext or exposed
    /// to screen capture while typing.
    @ViewBuilder
    private func mimoSecureField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MimoFont.caption(10))
                .foregroundStyle(MimoPalette.inkTertiary)
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(MimoFont.body(12))
        }
    }

    // MARK: - List

    @ViewBuilder
    private var existingKeysList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.keys) { key in
                SSHKeyRowView(key: key, viewModel: viewModel, expandedKeyIDs: $formViewModel.expandedKeyIDs)
            }
        }
    }
}
