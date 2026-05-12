//
//  ProfileRowView.swift
//  Mimo
//

import SwiftUI

struct ProfileRowView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var viewModel: ProfileFormViewModel
    let profile: GitProfile
    let isSelected: Bool

    private var emotion: MimoEmotion { MimoPalette.emotion(for: profile.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(emotion.body)
                    .frame(width: 40, height: 40)
                if profile.isActive {
                    MimoEyes(emotion: emotion, size: 24)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(MimoFont.headline(14))
                        .foregroundStyle(MimoPalette.ink)

                    if profile.provider != .custom {
                        Image(systemName: profile.provider.iconName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MimoPalette.inkSecondary)
                    }

                    if profile.isActive {
                        MimoBadge(text: "active", emotion: emotion, icon: "sparkles")
                    }
                }

                Text("\(profile.userName) · \(profile.userEmail)")
                    .font(MimoFont.mono(11))
                    .foregroundStyle(MimoPalette.inkSecondary)

                if let ssh = profile.sshKeyPath {
                    HStack(spacing: 4) {
                        Image(systemName: Constants.SystemImage.key)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MimoPalette.inkTertiary)
                        Text((ssh as NSString).lastPathComponent)
                            .font(MimoFont.mono(10))
                            .foregroundStyle(MimoPalette.inkTertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if !viewModel.showForm || !isSelected {
                    if !profile.isActive {
                        MimoPillButton(title: "Activate", icon: nil, emotion: emotion, prominent: true) {
                            Task { await appModel.switchProfile(to: profile) }
                        }
                    }

                    MimoPillButton(title: "Edit", icon: "pencil", emotion: nil) {
                        appModel.selectedProfileID = profile.id
                        withAnimation(MimoMotion.snap) {
                            viewModel.showForm = true
                            viewModel.isCreatingNewProfile = false
                            viewModel.loadProfile(currentProfile: appModel.selectedProfile)
                        }
                    }
                } else if isSelected && viewModel.showForm && !viewModel.isCreatingNewProfile {
                    MimoPillButton(title: "Done", icon: Constants.SystemImage.checkmark, emotion: emotion, prominent: true) {
                        withAnimation(MimoMotion.snap) {
                            viewModel.showForm = false
                        }
                    }
                }

                Button {
                    appModel.deleteProfile(id: profile.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MimoEmotion.anger.body.opacity(0.7))
                        .padding(8)
                        .background(
                            Circle().fill(MimoEmotion.anger.wash.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .mimoPress()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(profile.isActive ? emotion.wash : MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(profile.isActive ? emotion.body.opacity(0.3) : .clear, lineWidth: 1.5)
        )
    }
}
