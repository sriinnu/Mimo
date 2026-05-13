//
//  DirectoryProfileListView.swift
//  Mimo
//

import SwiftUI

struct DirectoryProfileListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showForm = false

    // Pre-commit guardrail state. Service is @MainActor; we hold a single
    // instance for the view's lifetime and re-check install status when
    // the directory list changes or after an install/uninstall action.
    @State private var hookService = PrecommitHookService()
    @State private var installedRepos: Set<String> = []
    @State private var hookErrorTitle: String = ""
    @State private var hookErrorMessage: String = ""
    @State private var showHookError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                MimoMascot(mood: .idle, palette: MimoEmotion.disgust.palette, size: 36, animateAmbient: false)
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
        .onAppear(perform: refreshHookStatus)
        .onChange(of: appModel.directoryProfiles) { _ in refreshHookStatus() }
        .alert(hookErrorTitle, isPresented: $showHookError) {
            Button(Constants.Strings.precommitOK, role: .cancel) { }
        } message: {
            Text(hookErrorMessage)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            MimoMascot(mood: .curious, palette: MimoEmotion.disgust.palette, size: 80)
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
        let palette: MimoPaintPalette = profile?.colorID.palette ?? MimoEmotion.disgust.palette
        let expandedPath = (mapping.directoryPath as NSString).expandingTildeInPath
        let isInstalled = installedRepos.contains(expandedPath)

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.body)
                    .frame(width: 32, height: 32)
                Image(systemName: Constants.SystemImage.folder)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(mapping.directoryPath)
                    .font(MimoFont.mono(11, weight: .semibold))
                    .foregroundStyle(MimoPalette.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("→")
                        .font(MimoFont.caption(10))
                        .foregroundStyle(MimoPalette.inkTertiary)
                    Text(profile?.name ?? "Unknown profile")
                        .font(MimoFont.caption(11, weight: .medium))
                        .foregroundStyle(MimoPalette.inkSecondary)

                    hookPill(
                        for: mapping,
                        repoPath: expandedPath,
                        isInstalled: isInstalled
                    )
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

    // MARK: - Hook pill

    /// Small pill on each directory row indicating whether the pre-commit
    /// guardrail is installed in that repo. Tapping toggles install/uninstall.
    @ViewBuilder
    private func hookPill(
        for mapping: DirectoryProfile,
        repoPath: String,
        isInstalled: Bool
    ) -> some View {
        let palette: MimoPaintPalette = isInstalled
            ? MimoEmotion.disgust.palette
            : MimoEmotion.fear.palette
        let title = isInstalled
            ? Constants.Strings.precommitInstalled
            : Constants.Strings.precommitMissing
        let icon = isInstalled
            ? Constants.SystemImage.hookOn
            : Constants.SystemImage.hookOff

        Button {
            toggleHook(for: mapping, repoPath: repoPath, isInstalled: isInstalled)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(title).font(MimoFont.caption(10, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(palette.body)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.wash)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(palette.body.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .mimoPress()
        .help(isInstalled
              ? "Pre-commit guardrail installed. Click to remove."
              : "Install Mimo's pre-commit guardrail in this repo.")
    }

    // MARK: - Hook actions

    private func toggleHook(
        for mapping: DirectoryProfile,
        repoPath: String,
        isInstalled: Bool
    ) {
        guard let profile = appModel.availableProfiles.first(where: { $0.id == mapping.profileID }) else {
            hookErrorTitle = Constants.Strings.precommitInstallFailedTitle
            hookErrorMessage = "The profile for this directory is missing. Re-add the mapping and try again."
            showHookError = true
            return
        }

        do {
            if isInstalled {
                try hookService.uninstall(at: repoPath)
                installedRepos.remove(repoPath)
            } else {
                try hookService.install(
                    at: repoPath,
                    profileID: profile.id,
                    profileName: profile.name
                )
                installedRepos.insert(repoPath)
            }
        } catch {
            hookErrorTitle = isInstalled
                ? Constants.Strings.precommitUninstallFailedTitle
                : Constants.Strings.precommitInstallFailedTitle
            hookErrorMessage = error.localizedDescription
            showHookError = true
            // Re-derive from disk in case the on-disk state diverged.
            refreshHookStatus()
        }
    }

    private func refreshHookStatus() {
        var found: Set<String> = []
        for mapping in appModel.directoryProfiles {
            let expanded = (mapping.directoryPath as NSString).expandingTildeInPath
            if hookService.isInstalled(at: expanded) {
                found.insert(expanded)
            }
        }
        installedRepos = found
    }
}
