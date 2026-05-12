//
//  SigningConfigView.swift
//  Mimo
//

import SwiftUI

struct SigningConfigView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var gpgKeys: [GPGKeyInfo] = []
    @State private var isGPGAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MimoMascot(
                    mood: isGPGAvailable ? .idle : .worried,
                    emotion: .anger,
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

            if !isGPGAvailable {
                gpgUnavailable
            }

            VStack(spacing: 10) {
                ForEach(appModel.availableProfiles) { profile in
                    profileSigningRow(profile: profile)
                }
            }
        }
        .padding(24)
        .onAppear { loadGPGStatus() }
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
        let emotion = MimoPalette.emotion(for: profile.id)
        let signs = profile.signingType != .none

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(emotion.body)
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
                        emotion: signs ? emotion : .fear
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

            MimoPillButton(title: "Edit", icon: "pencil", emotion: emotion) {
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

    private func loadGPGStatus() {
        let service = GPGKeyService()
        Task {
            isGPGAvailable = await service.isGPGInstalled()
            if let keys = try? await service.scanKeys() {
                gpgKeys = keys
            }
        }
    }
}
