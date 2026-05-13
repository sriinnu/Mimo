//
//  CloneView.swift
//  Mimo
//

import SwiftUI

struct CloneView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var themeStore = MimoThemeStore.shared
    @State private var repoURL: String = ""
    @State private var cloneDirectory: String = ""
    @State private var selectedProfileID: UUID?
    @State private var isCloning: Bool = false
    @State private var result: CloneResult?
    @State private var hoveredDismiss = false
    @Environment(\.dismiss) private var dismiss

    private let cloneService = CloneService()

    private var detectedProvider: GitProvider {
        guard !repoURL.isEmpty else { return .custom }
        if repoURL.contains("github.com") { return .github }
        if repoURL.contains("dev.azure.com") || repoURL.contains("ssh.dev.azure.com") { return .azureDevOps }
        if repoURL.contains("gitlab.com") { return .gitlab }
        if repoURL.contains("bitbucket.org") { return .bitbucket }
        return .custom
    }

    private var matchedProfile: GitProfile? {
        appModel.availableProfiles.first { $0.provider == detectedProvider }
    }

    private var providerPalette: MimoPaintPalette {
        let emotion: MimoEmotion
        switch detectedProvider {
        case .github:        emotion = .fear
        case .azureDevOps:   emotion = .sadness
        case .gitlab:        emotion = .anger
        case .bitbucket:     emotion = .disgust
        case .custom:        emotion = .joy
        }
        return emotion.palette
    }

    private var mascotMood: MimoMascot.Mood {
        if isCloning { return .curious }
        if let r = result { return r.success ? .happy : .worried }
        return .idle
    }

    var body: some View {
        ZStack {
            MimoPalette.surface
            MimoStarfield(density: 26).opacity(0.4).blendMode(.plusLighter)

            VStack(spacing: 0) {
                headerBar
                MimoDivider().padding(.horizontal, 20)

                VStack(spacing: 14) {
                    heroCard
                    directoryCard
                    profileCard
                    Spacer(minLength: 0)
                    actionBar
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 560)
        .overlay(alignment: .bottom) {
            if let result {
                resultToast(result)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MimoMotion.settle, value: result != nil)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 12) {
            MimoMascot(mood: mascotMood, palette: providerPalette, size: 36, animateAmbient: false)
                .frame(width: 48, height: 52)

            VStack(alignment: .leading, spacing: 1) {
                Text("Clone a repo")
                    .font(MimoFont.headline(15))
                    .foregroundStyle(MimoPalette.ink)
                Text(repoURL.isEmpty ? "Mimo will pick the right identity." : detectedProvider.displayName)
                    .font(MimoFont.caption(11))
                    .foregroundStyle(MimoPalette.inkSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hoveredDismiss ? MimoPalette.ink : MimoPalette.inkTertiary)
            }
            .buttonStyle(.plain)
            .onHover { hoveredDismiss = $0 }
            .mimoPress()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Hero (URL)

    @ViewBuilder
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REPOSITORY")
                .font(MimoFont.caption(9, weight: .bold))
                .foregroundStyle(MimoPalette.inkTertiary)

            TextField("https://github.com/org/repo.git", text: $repoURL)
                .textFieldStyle(.plain)
                .font(MimoFont.mono(13))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MimoPalette.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(repoURL.isEmpty ? .clear : providerPalette.body.opacity(0.6), lineWidth: 1.5)
                )

            if !repoURL.isEmpty && detectedProvider != .custom {
                detectedProviderBadge
            }
        }
        .padding(16)
        .mimoCard(cornerRadius: 18)
    }

    @ViewBuilder
    private var detectedProviderBadge: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(providerPalette.wash)
                    .frame(width: 24, height: 24)
                Image(systemName: detectedProvider.iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(providerPalette.body)
            }
            Text(detectedProvider.displayName)
                .font(MimoFont.caption(11, weight: .semibold))
                .foregroundStyle(MimoPalette.ink)

            Spacer()

            if let profile = matchedProfile {
                let profilePalette = profile.colorID.palette
                HStack(spacing: 4) {
                    Circle()
                        .fill(profilePalette.body)
                        .frame(width: 6, height: 6)
                    Text(profile.name)
                        .font(MimoFont.caption(10, weight: .bold))
                        .foregroundStyle(profilePalette.body)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous).fill(profilePalette.wash)
                )
            }
        }
    }

    // MARK: - Directory

    @ViewBuilder
    private var directoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESTINATION")
                .font(MimoFont.caption(9, weight: .bold))
                .foregroundStyle(MimoPalette.inkTertiary)

            HStack(spacing: 8) {
                TextField("~/Projects/repo", text: $cloneDirectory)
                    .textFieldStyle(.plain)
                    .font(MimoFont.body(13))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MimoPalette.surfaceSunken)
                    )

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        cloneDirectory = url.path
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MimoPalette.marigold.opacity(0.16))
                            .frame(width: 36, height: 36)
                        Image(systemName: Constants.SystemImage.folder)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MimoPalette.marigold)
                    }
                }
                .buttonStyle(.plain)
                .mimoPress()
            }
        }
        .padding(16)
        .mimoCard(cornerRadius: 18)
    }

    // MARK: - Profile picker

    @ViewBuilder
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IDENTITY")
                .font(MimoFont.caption(9, weight: .bold))
                .foregroundStyle(MimoPalette.inkTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    autoDetectChip
                    ForEach(appModel.availableProfiles) { profile in
                        profileChip(profile)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .mimoCard(cornerRadius: 18)
    }

    @ViewBuilder
    private var autoDetectChip: some View {
        let isSelected = selectedProfileID == nil
        Button {
            withAnimation(MimoMotion.snap) { selectedProfileID = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10, weight: .semibold))
                Text("Auto")
                    .font(MimoFont.caption(11, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : MimoPalette.inkSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? MimoPalette.marigold : MimoPalette.surfaceSunken)
            )
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    @ViewBuilder
    private func profileChip(_ profile: GitProfile) -> some View {
        let isSelected = selectedProfileID == profile.id
        let chipPalette = profile.colorID.palette

        Button {
            withAnimation(MimoMotion.snap) { selectedProfileID = profile.id }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? Color.white : chipPalette.body)
                    .frame(width: 7, height: 7)
                Text(profile.name)
                    .font(MimoFont.caption(11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : MimoPalette.inkSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? chipPalette.body : MimoPalette.surfaceSunken)
            )
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    // MARK: - Action bar

    @ViewBuilder
    private var actionBar: some View {
        HStack {
            if let result {
                HStack(spacing: 5) {
                    Image(systemName: result.success ? Constants.SystemImage.checkmark : Constants.SystemImage.warning)
                        .font(.system(size: 11, weight: .semibold))
                    Text(result.success ? "Done" : "Failed")
                        .font(MimoFont.caption(11, weight: .bold))
                }
                .foregroundStyle(result.success ? MimoEmotion.disgust.body : MimoEmotion.anger.body)
            }
            Spacer()

            Button {
                performClone()
            } label: {
                HStack(spacing: 8) {
                    if isCloning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: Constants.SystemImage.clone)
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(isCloning ? Constants.Strings.cloning : Constants.Strings.cloneRepo)
                        .font(MimoFont.body(13, weight: .bold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(
                    Capsule(style: .continuous)
                        .fill(MimoPalette.marigold)
                )
            }
            .buttonStyle(.plain)
            .mimoPress()
            .disabled(repoURL.isEmpty || cloneDirectory.isEmpty || isCloning)
            .opacity((repoURL.isEmpty || cloneDirectory.isEmpty || isCloning) ? 0.55 : 1.0)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private func resultToast(_ result: CloneResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(result.success ? MimoEmotion.disgust.wash : MimoEmotion.anger.wash)
                    .frame(width: 28, height: 28)
                Image(systemName: result.success ? Constants.SystemImage.checkmark : Constants.SystemImage.warning)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(result.success ? MimoEmotion.disgust.body : MimoEmotion.anger.body)
            }
            Text(result.output)
                .font(MimoFont.mono(11))
                .foregroundStyle(MimoPalette.inkSecondary)
                .lineLimit(4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 14, y: 4)
        )
        .padding(20)
    }

    private func performClone() {
        isCloning = true
        result = nil
        let profileID = selectedProfileID ?? matchedProfile?.id
        let profile = appModel.availableProfiles.first { $0.id == profileID }
        let url = repoURL
        let dir = cloneDirectory

        Task {
            let r = try? await cloneService.clone(url: url, into: dir, profile: profile)
            await MainActor.run {
                result = r
                isCloning = false
            }
        }
    }
}
