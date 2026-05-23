//
//  SigningConfigView.swift
//  Mimo
//

import SwiftUI

struct SigningConfigView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var gpgKeys: [GPGKeyInfo] = []
    @State private var sshKeys: [SSHKeyInfo] = []
    @State private var isGPGAvailable = false

    var body: some View {
        let anyProfileUsesGPG = appModel.availableProfiles.contains { $0.signingType == .gpg }

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MimoMascot(
                    mood: (!anyProfileUsesGPG || isGPGAvailable) ? .idle : .worried,
                    palette: MimoEmotion.anger.palette,
                    size: 38,
                    animateAmbient: false
                )
                .frame(width: 50, height: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Constants.Strings.signing)
                        .font(MimoFont.headline(15))
                        .foregroundStyle(MimoPalette.ink)
                    Text("Sign your commits so people know it was really you.")
                        .font(MimoFont.caption(11))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }
                Spacer()
            }

            if !isGPGAvailable && anyProfileUsesGPG {
                gpgUnavailable
            }

            if anyProfileUsesGPG {
                if !gpgKeys.isEmpty { gpgKeysSection }
                if !sshKeys.isEmpty { sshKeysSection }
            } else {
                if !sshKeys.isEmpty { sshKeysSection }
                if !gpgKeys.isEmpty { gpgKeysSection }
            }

            VStack(spacing: 10) {
                ForEach(appModel.availableProfiles) { profile in
                    profileSigningRow(profile: profile)
                }
            }
        }
        .padding(24)
        .onAppear { loadSigningOptions() }
    }

    @ViewBuilder
    private var gpgUnavailable: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(MimoEmotion.fear.wash)
                    .frame(width: 28, height: 28)
                Image(systemName: Constants.SystemImage.warning)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MimoEmotion.fear.body)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("GPG not installed")
                    .font(MimoFont.body(12, weight: .semibold))
                    .foregroundStyle(MimoPalette.ink)
                Text("Install GPG Suite or gnupg to enable GPG signing.")
                    .font(MimoFont.caption(11))
                    .foregroundStyle(MimoPalette.inkSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MimoEmotion.fear.wash)
        )
    }

    @ViewBuilder
    private func profileSigningRow(profile: GitProfile) -> some View {
        let palette = profile.colorID.palette
        let signs = profile.signingType != .none

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.body)
                    .frame(width: 32, height: 32)
                Image(systemName: signs ? Constants.SystemImage.shieldCheck : Constants.SystemImage.signing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(MimoFont.body(13, weight: .semibold))
                        .foregroundStyle(MimoPalette.ink)

                    MimoBadge(
                        text: profile.signingType.displayName.lowercased(),
                        palette: signs ? palette : MimoEmotion.fear.palette
                    )
                }

                if let key = profile.signingKey {
                    Text(key)
                        .font(MimoFont.mono(10))
                        .foregroundStyle(MimoPalette.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            MimoPillButton(title: "Edit", icon: "pencil", palette: palette) {
                appModel.selectedManagementTab = .profile
                appModel.selectedProfileID = profile.id
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 8, y: 2)
        )
    }

    @ViewBuilder
    private var gpgKeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GPG KEYS")
                .font(MimoFont.caption(10, weight: .bold))
                .foregroundStyle(MimoPalette.inkSecondary)
                .textCase(.uppercase)

            ForEach(gpgKeys) { key in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(MimoEmotion.fear.palette.body)
                            .frame(width: 28, height: 28)
                        Image(systemName: Constants.SystemImage.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.userID)
                            .font(MimoFont.body(12, weight: .semibold))
                            .foregroundStyle(MimoPalette.ink)
                            .lineLimit(1)
                        Text(key.keyID.suffix(16))
                            .font(MimoFont.mono(10))
                            .foregroundStyle(MimoPalette.inkTertiary)
                    }

                    Spacer()

                    if let date = key.createdAt {
                        Text(date, style: .date)
                            .font(MimoFont.caption(10))
                            .foregroundStyle(MimoPalette.inkTertiary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MimoPalette.surfaceElevated)
                )
            }
        }
        .padding(14)
        .mimoCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var sshKeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SSH KEYS")
                .font(MimoFont.caption(10, weight: .bold))
                .foregroundStyle(MimoPalette.inkSecondary)
                .textCase(.uppercase)

            ForEach(sshKeys) { key in
                let palette: MimoPaintPalette = {
                    switch key.keyType {
                    case .ed25519: return MimoEmotion.joy.palette
                    case .rsa:     return MimoEmotion.fear.palette
                    case .ecdsa:   return MimoEmotion.serenity.palette
                    case .dsa:     return MimoEmotion.anger.palette
                    }
                }()

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(palette.body)
                            .frame(width: 28, height: 28)
                        Image(systemName: Constants.SystemImage.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(key.filename)
                                .font(MimoFont.body(12, weight: .semibold))
                                .foregroundStyle(MimoPalette.ink)
                                .lineLimit(1)
                            MimoBadge(text: key.keyType.displayName, palette: palette)
                        }
                        if let comment = key.comment {
                            Text(comment)
                                .font(MimoFont.caption(10))
                                .foregroundStyle(MimoPalette.inkTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let date = key.createdAt {
                        Text(date, style: .date)
                            .font(MimoFont.caption(10))
                            .foregroundStyle(MimoPalette.inkTertiary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MimoPalette.surfaceElevated)
                )
            }
        }
        .padding(14)
        .mimoCard(cornerRadius: 16)
    }

    private func loadSigningOptions() {
        let gpgService = GPGKeyService()
        Task {
            isGPGAvailable = await gpgService.isGPGInstalled()
            if let keys = try? await gpgService.scanKeys() {
                gpgKeys = keys
            }
            sshKeys = (try? await SSHKeyService().scanKeys()) ?? []
        }
    }
}
