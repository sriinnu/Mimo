//
//  DirectoryProfileListView.swift
//  Mimo
//

import SwiftUI

struct DirectoryProfileListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                MimoMascot(mood: .idle, emotion: .disgust, size: 36, animateAmbient: false)
                    .frame(width: 48, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Constants.Strings.directories)
                        .font(MimoFont.headline(15))
                        .foregroundStyle(MimoPalette.ink)
                    Text(Constants.Strings.directoryHint)
                        .font(MimoFont.caption(11))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }
                Spacer()

                Button {
                    withAnimation(MimoMotion.snap) { showForm.toggle() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(MimoPalette.marigold.opacity(0.16))
                            .frame(width: 28, height: 28)
                        Image(systemName: showForm ? Constants.SystemImage.minus : Constants.SystemImage.plus)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MimoPalette.marigold)
                    }
                }
                .buttonStyle(.plain)
                .mimoPress()
            }

            if showForm {
                DirectoryProfileFormView(isPresented: $showForm)
                    .environmentObject(appModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if appModel.directoryProfiles.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(appModel.directoryProfiles) { mapping in
                        directoryRow(mapping: mapping)
                    }
                }
            }
        }
        .padding(24)
        .animation(MimoMotion.snap, value: showForm)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            MimoMascot(mood: .curious, emotion: .disgust, size: 80)
                .frame(height: 96)
            Text("No directory mappings yet")
                .font(MimoFont.headline(13))
                .foregroundStyle(MimoPalette.ink)
            Text("Map a folder to a profile so Mimo swaps you automatically.")
                .font(MimoFont.body(11))
                .foregroundStyle(MimoPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func directoryRow(mapping: DirectoryProfile) -> some View {
        let profile = appModel.availableProfiles.first { $0.id == mapping.profileID }
        let emotion: MimoEmotion = profile.map { MimoPalette.emotion(for: $0.id) } ?? .disgust

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(emotion.body)
                    .frame(width: 32, height: 32)
                Image(systemName: Constants.SystemImage.folder)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.directoryPath)
                    .font(MimoFont.mono(11, weight: .semibold))
                    .foregroundStyle(MimoPalette.ink)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("→")
                        .font(MimoFont.caption(10))
                        .foregroundStyle(MimoPalette.inkTertiary)
                    Text(profile?.name ?? "Unknown profile")
                        .font(MimoFont.caption(11, weight: .medium))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }
            }

            Spacer()

            Button {
                appModel.removeDirectoryProfile(id: mapping.id)
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 8, y: 2)
        )
    }
}
