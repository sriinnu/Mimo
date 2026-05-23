//
//  MenuBarView.swift
//  Mimo
//
//  The menu bar popover — Mimo's home. Warm Pixar surface, mascot in
//  the corner, emotion-colored profile rows, animated celebration on
//  profile switch.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var updater: UpdaterService
    @ObservedObject private var themeStore = MimoThemeStore.shared
    @StateObject private var viewModel = MenuBarViewModel()
    @State private var repoStatus: GitRepoStatus?
    @State private var showCloneSheet = false
    @State private var mascotMood: MimoMascot.Mood = .idle
    /// Whether the mismatch card was visible on the *previous* render. When it
    /// flips from true → false, we play a `.happy` bounce on the header mascot
    /// to celebrate the fix.
    @State private var wasMismatched: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            VStack(spacing: 0) {
                if updater.isUpdateAvailable {
                    updateBanner
                    MimoDivider().padding(.horizontal, 16)
                }

                headerSection

                if appModel.foregroundRepoState.hasMismatch {
                    mismatchCard
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        ))
                }

                MimoDivider().padding(.horizontal, 16)

                profileListSection
                    .padding(.top, 4)

                if let status = repoStatus, status.branch != nil {
                    MimoDivider().padding(.horizontal, 16)
                    repoStatusSection(status: status)
                }

                MimoDivider().padding(.horizontal, 16)
                actionButtonsSection

                MimoDivider().padding(.horizontal, 16)
                quitButton
                    .padding(.bottom, 10)
            }
            .animation(MimoMotion.snap, value: appModel.foregroundRepoState.hasMismatch)
        }
        .frame(width: Constants.Layout.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showCloneSheet) {
            CloneView().environmentObject(appModel)
        }
        .onAppear {
            appModel.loadOnLaunch()
            loadRepoStatus()
            wasMismatched = appModel.foregroundRepoState.hasMismatch
        }
        .task(id: appModel.activeProfileID) {
            guard appModel.activeProfileID != nil else { return }
            mascotMood = .happy
            try? await Task.sleep(nanoseconds: 900_000_000)
            mascotMood = .idle
        }
        .onChange(of: appModel.foregroundRepoState.hasMismatch) { newValue in
            // True → false: user fixed the mismatch. Celebrate.
            if wasMismatched && !newValue {
                Task {
                    mascotMood = .happy
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    mascotMood = .idle
                }
            }
            wasMismatched = newValue
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack {
            MimoPalette.surface
            MimoStarfield(density: 22)
                .opacity(0.45)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    private var activePalette: MimoPaintPalette {
        appModel.activeProfile?.colorID.palette ?? MimoEmotion.joy.palette
    }

    // MARK: - Header

    /// Phantom mode overrides ambient mascot mood — the domino-masked face
    /// is the strongest possible signal that you're operating as someone
    /// else for one commit.
    private var effectiveMascotMood: MimoMascot.Mood {
        appModel.phantomReturnToID != nil ? .phantom : mascotMood
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 12) {
            MimoMascot(mood: effectiveMascotMood, palette: activePalette, size: 44)
                .frame(width: 56, height: 60)

            VStack(alignment: .leading, spacing: 1) {
                Text(Constants.Strings.appName)
                    .font(MimoFont.display(20))
                    .foregroundStyle(MimoPalette.ink)
                Text("who do you want to be today?")
                    .font(MimoFont.caption(10, weight: .medium))
                    .foregroundStyle(MimoPalette.inkSecondary)
            }

            Spacer()

            Button {
                AboutWindowController.shared.showAbout(appModel: appModel)
            } label: {
                Image(systemName: Constants.SystemImage.info)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .mimoPress()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Mismatch warning card

    /// Auto-detect card: appears when the foreground app's cwd is in a repo
    /// that expects a *different* profile than the one currently active. The
    /// fix is one tap — switch to the expected profile.
    @ViewBuilder
    private var mismatchCard: some View {
        let state = appModel.foregroundRepoState
        let activeProfile = appModel.activeProfile
        let expectedProfile = state.expectedProfileID.flatMap { id in
            appModel.availableProfiles.first(where: { $0.id == id })
        }
        let activePalette = activeProfile?.colorID.palette ?? MimoEmotion.joy.palette
        let expectedPalette = expectedProfile?.colorID.palette ?? MimoEmotion.anger.palette

        HStack(alignment: .top, spacing: 12) {
            MimoMascot(
                mood: .wincing,
                palette: activePalette,
                size: 36,
                animateAmbient: false
            )
            .frame(width: 44, height: 50)

            VStack(alignment: .leading, spacing: 6) {
                Text("Wrong identity for this repo")
                    .font(MimoFont.headline(13))
                    .foregroundStyle(MimoPalette.ink)

                if let repoRoot = state.repoRoot {
                    Text(displayPath(for: repoRoot))
                        .font(MimoFont.mono(10))
                        .foregroundStyle(MimoPalette.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                contextLine(
                    activeName: activeProfile?.name ?? "no profile",
                    expectedName: expectedProfile?.name ?? "another profile",
                    repoPath: state.repoRoot.map { displayPath(for: $0) } ?? "this folder"
                )
                .font(MimoFont.body(11))
                .foregroundStyle(MimoPalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if let expectedProfile {
                    MimoPillButton(
                        title: "Switch to \(expectedProfile.name)",
                        icon: Constants.SystemImage.switchProfile,
                        palette: expectedPalette,
                        prominent: true
                    ) {
                        viewModel.switchProfile(appModel: appModel, to: expectedProfile)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .mimoCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(expectedPalette.body.opacity(0.35), lineWidth: 1)
        )
    }

    /// Renders the bold-name context sentence using AttributedString so the
    /// profile names stand out without spinning up an extra HStack.
    private func contextLine(
        activeName: String,
        expectedName: String,
        repoPath: String
    ) -> Text {
        var attributed = AttributedString("You're currently ")
        var active = AttributedString(activeName)
        active.font = MimoFont.body(11, weight: .semibold)
        active.foregroundColor = MimoPalette.ink
        attributed.append(active)
        attributed.append(AttributedString(", but "))
        var path = AttributedString(repoPath)
        path.font = MimoFont.mono(10, weight: .semibold)
        path.foregroundColor = MimoPalette.ink
        attributed.append(path)
        attributed.append(AttributedString(" expects "))
        var expected = AttributedString(expectedName)
        expected.font = MimoFont.body(11, weight: .semibold)
        expected.foregroundColor = MimoPalette.ink
        attributed.append(expected)
        attributed.append(AttributedString("."))
        return Text(attributed)
    }

    /// Replaces `$HOME` with `~` for compact display in the card and tooltip.
    private func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Update banner

    @ViewBuilder
    private var updateBanner: some View {
        Button {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.checkForUpdates(nil)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MimoPalette.marigold.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: Constants.SystemImage.sparkle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MimoPalette.marigold)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(Constants.Strings.updateAvailable)
                        .font(MimoFont.body(12, weight: .semibold))
                        .foregroundStyle(MimoPalette.ink)
                    Text(Constants.Strings.updateNow)
                        .font(MimoFont.caption(10))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MimoPalette.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MimoPalette.marigold.opacity(0.08))
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    // MARK: - Profile list

    @ViewBuilder
    private var profileListSection: some View {
        VStack(spacing: 6) {
            if appModel.availableProfiles.isEmpty {
                emptyProfileState
            } else {
                ForEach(appModel.availableProfiles) { profile in
                    profileRow(profile: profile)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyProfileState: some View {
        VStack(spacing: 12) {
            MimoMascot(mood: .curious, palette: MimoEmotion.joy.palette, size: 90)
                .frame(height: 110)
                .padding(.top, 6)

            VStack(spacing: 4) {
                Text("No profiles yet")
                    .font(MimoFont.headline(14))
                    .foregroundStyle(MimoPalette.ink)
                Text(Constants.Strings.noProfilesHint)
                    .font(MimoFont.body(11))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            MimoPillButton(
                title: Constants.Strings.addProfile,
                icon: Constants.SystemImage.plus,
                palette: MimoEmotion.joy.palette,
                prominent: true
            ) {
                appModel.openManagementWindow(tab: .profile)
            }
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func profileRow(profile: GitProfile) -> some View {
        let isActive = profile.id == appModel.activeProfileID
        let isHovered = viewModel.hoveredProfileID == profile.id
        let palette = profile.colorID.palette

        Button {
            viewModel.switchProfile(appModel: appModel, to: profile)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(palette.body)
                        .frame(width: 28, height: 28)
                    if isActive {
                        MimoEyes(palette: palette, size: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(MimoFont.body(13, weight: .semibold))
                            .foregroundStyle(MimoPalette.ink)
                        if profile.provider != .custom {
                            Image(systemName: profile.provider.iconName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MimoPalette.inkTertiary)
                        }
                    }
                    Text("\(profile.userName) · \(profile.userEmail)")
                        .font(MimoFont.mono(10))
                        .foregroundStyle(MimoPalette.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isActive {
                    MimoBadge(text: "active", palette: palette)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(rowBackground(isActive: isActive, isHovered: isHovered, palette: palette))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isActive ? palette.body.opacity(0.3) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { hovering in viewModel.setHoveredProfile(id: profile.id, isHovering: hovering) }
        }
        .buttonStyle(.plain)
        .mimoPress()
        .animation(MimoMotion.snap, value: isActive)
    }

    private func rowBackground(isActive: Bool, isHovered: Bool, palette: MimoPaintPalette) -> Color {
        if isActive { return palette.wash }
        if isHovered { return MimoPalette.surfaceSunken }
        return .clear
    }

    // MARK: - Repo status

    @ViewBuilder
    private func repoStatusSection(status: GitRepoStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.isDirty ? Constants.SystemImage.dirty : Constants.SystemImage.clean)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(status.isDirty ? MimoEmotion.anger.body : MimoEmotion.serenity.body)

            VStack(alignment: .leading, spacing: 1) {
                if let branch = status.branch {
                    HStack(spacing: 4) {
                        Image(systemName: Constants.SystemImage.branch)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MimoPalette.inkSecondary)
                        Text(branch)
                            .font(MimoFont.mono(11, weight: .semibold))
                            .foregroundStyle(MimoPalette.ink)
                    }
                }
                if let name = status.repoName {
                    Text(name)
                        .font(MimoFont.caption(9))
                        .foregroundStyle(MimoPalette.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let active = appModel.activeProfile {
                MimoBadge(text: active.name, palette: active.colorID.palette)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: 2) {
            actionRow(id: "ssh", icon: Constants.SystemImage.sshManage, title: Constants.Strings.manageSSH) {
                appModel.openManagementWindow(tab: .ssh)
            }
            actionRow(id: "profile", icon: Constants.SystemImage.profileManage, title: Constants.Strings.manageProfile) {
                appModel.openManagementWindow(tab: .profile)
            }
            actionRow(id: "clone", icon: Constants.SystemImage.clone, title: Constants.Strings.cloneRepo) {
                showCloneSheet = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionRow(id: String, icon: String, title: String, action: @escaping () -> Void) -> some View {
        let isHovered = viewModel.hoveredActionID == id

        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(MimoFont.body(13, weight: .medium))
                    .foregroundStyle(MimoPalette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MimoPalette.inkTertiary.opacity(isHovered ? 1 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? MimoPalette.surfaceSunken : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { hovering in viewModel.setHoveredAction(id: id, isHovering: hovering) }
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    // MARK: - Quit

    @ViewBuilder
    private var quitButton: some View {
        let isHovered = viewModel.hoveredActionID == "quit"

        Button {
            viewModel.quit()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: Constants.SystemImage.quit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .frame(width: 20)
                Text(Constants.Strings.quitApp)
                    .font(MimoFont.body(13, weight: .medium))
                    .foregroundStyle(MimoPalette.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? MimoPalette.surfaceSunken : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { hovering in viewModel.setHoveredAction(id: "quit", isHovering: hovering) }
        }
        .buttonStyle(.plain)
        .mimoPress()
        .padding(.horizontal, 8)
    }

    private func loadRepoStatus() {
        let service = GitStatusService()
        let path = appModel.foregroundRepoState.repoRoot?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        Task {
            let status = await service.status(for: path)
            await MainActor.run { repoStatus = status }
        }
    }
}
