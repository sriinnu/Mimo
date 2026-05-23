//
//  ManagementView.swift
//  Mimo
//
//  Mimo's "studio" — the management window. Warm surface, tab outfits,
//  status badges that slide in like character speech bubbles.
//

import SwiftUI

struct ManagementView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var themeStore = MimoThemeStore.shared
    @ObservedObject private var auditLog = IdentityAuditLog.shared
    @StateObject private var viewModel = ManagementViewModel()
    @StateObject private var sshKeysViewModel = SSHKeysViewModel()
    @State private var showResetConfirmation = false
    @State private var showImportAlert = false
    @State private var importAlertMessage = ""
    @State private var exportImportStatus: String?

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                contentHeader
                MimoDivider().padding(.horizontal, 24)
                contentArea
            }
        }
        .frame(
            minWidth: Constants.Layout.managementWidth,
            minHeight: Constants.Layout.managementHeight
        )
        .overlay(alignment: .bottom) {
            if let message = sshKeysViewModel.statusMessage {
                statusToast(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
            if let message = exportImportStatus {
                statusToast(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(MimoMotion.settle, value: sshKeysViewModel.statusMessage)
        .animation(MimoMotion.settle, value: exportImportStatus)
        .onAppear { sshKeysViewModel.loadKeys() }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack {
            MimoPalette.surface
            MimoStarfield(density: 40).opacity(0.35).blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func statusToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            MimoEyes(palette: MimoEmotion.serenity.palette, size: 14)
            Text(message)
                .font(MimoFont.body(12, weight: .semibold))
                .foregroundStyle(MimoPalette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 12, y: 4)
        )
        .padding(.bottom, 24)
    }

    // MARK: - Header

    @ViewBuilder
    private var contentHeader: some View {
        HStack {
            tabToggle
            Spacer()

            HStack(spacing: 8) {
                // Add / toggle — primary action, stays prominent
                Button {
                    withAnimation(MimoMotion.snap) {
                        switch appModel.selectedManagementTab {
                        case .profile:
                            if !viewModel.showProfileForm {
                                viewModel.showProfileForm = true
                                viewModel.isCreatingNewProfile = true
                            } else if viewModel.isCreatingNewProfile {
                                viewModel.showProfileForm = false
                                viewModel.isCreatingNewProfile = false
                            } else {
                                viewModel.isCreatingNewProfile = true
                            }
                        case .ssh:
                            viewModel.showNewSSHKeyForm.toggle()
                        case .directories, .signing, .timeMachine:
                            break
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(MimoPalette.marigold.opacity(0.16))
                            .frame(width: 30, height: 30)
                        Image(systemName: viewModel.isMinusIcon(tab: appModel.selectedManagementTab)
                            ? Constants.SystemImage.minus
                            : Constants.SystemImage.plus)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MimoPalette.marigold)
                    }
                }
                .buttonStyle(.plain)
                .mimoPress()

                // Overflow — Export / Import / Reset (destructive is buried here)
                Menu {
                    Button {
                        exportProfiles()
                    } label: {
                        Label("Export profiles…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importProfiles()
                    } label: {
                        Label("Import profiles…", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset all Mimo data…", systemImage: "trash")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(MimoPalette.surfaceElevated)
                            .frame(width: 30, height: 30)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MimoPalette.inkSecondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30, height: 30)
                .help("More actions")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .alert("Factory reset?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset everything", role: .destructive) {
                factoryReset()
            }
        } message: {
            Text("This removes all profiles, directory mappings, audit history, and per-profile config files. Your git config changes will be reverted too. This cannot be undone.")
        }
        .alert("Import profiles", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importAlertMessage)
        }
    }

    @ViewBuilder
    private var tabToggle: some View {
        HStack(spacing: 6) {
            ForEach(Constants.ManagementTab.allCases) { tab in
                tabPill(for: tab)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 6, y: 2)
        )
    }

    @ViewBuilder
    private func tabPill(for tab: Constants.ManagementTab) -> some View {
        let isActive = appModel.selectedManagementTab == tab
        let (count, icon) = tabInfo(for: tab)

        Button {
            withAnimation(MimoMotion.snap) {
                viewModel.selectTab(appModel: appModel, tab: tab)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.rawValue)
                    .font(MimoFont.body(12, weight: isActive ? .bold : .medium))
                Text("\(count)")
                    .font(MimoFont.caption(10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isActive ? Color.white.opacity(0.25) : MimoPalette.surfaceSunken)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? .white : MimoPalette.inkSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? MimoPalette.marigold : .clear)
            )
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    private func tabInfo(for tab: Constants.ManagementTab) -> (Int, String) {
        switch tab {
        case .profile:
            return (appModel.availableProfiles.count, Constants.SystemImage.profileManage)
        case .ssh:
            return (sshKeysViewModel.keys.count, Constants.SystemImage.sshManage)
        case .directories:
            return (appModel.directoryProfiles.count, Constants.SystemImage.directories)
        case .signing:
            return (appModel.availableProfiles.filter { $0.signingType != .none }.count, Constants.SystemImage.signing)
        case .timeMachine:
            return (auditLog.entries.count, Constants.SystemImage.timeMachine)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            switch appModel.selectedManagementTab {
            case .profile:
                ProfileFormView()
                    .environmentObject(viewModel)
            case .ssh:
                SSHFormView()
                    .environmentObject(viewModel)
                    .environmentObject(sshKeysViewModel)
            case .directories:
                ScrollView {
                    DirectoryProfileListView()
                        .environmentObject(appModel)
                }
            case .signing:
                ScrollView {
                    SigningConfigView()
                        .environmentObject(appModel)
                }
            case .timeMachine:
                AuditLogView()
                    .environmentObject(appModel)
            }
        }
        .animation(MimoMotion.snap, value: appModel.selectedManagementTab)
    }

    // MARK: - Export / Import / Reset

    private func exportProfiles() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mimo-profiles.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try JSONEncoder().encode(appModel.availableProfiles)
            try data.write(to: url)
            showExportImportStatus("Exported \(appModel.availableProfiles.count) profiles")
        } catch {
            showExportImportStatus("Export failed: \(error.localizedDescription)")
        }
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([GitProfile].self, from: data)
            for profile in imported {
                appModel.addOrUpdateProfile(profile)
            }
            importAlertMessage = "Imported \(imported.count) profiles."
            showImportAlert = true
        } catch {
            importAlertMessage = "Import failed: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func factoryReset() {
        // 1. Clear all profiles (this also cleans up orphaned files via deleteProfile)
        let profileIDs = appModel.availableProfiles.map(\.id)
        for id in profileIDs {
            appModel.deleteProfile(id: id)
        }

        // 2. Clear directory profiles
        let dirIDs = appModel.directoryProfiles.map(\.id)
        for id in dirIDs {
            appModel.removeDirectoryProfile(id: id)
        }

        // 3. Clear audit log
        auditLog.clear()

        // 4. Clear SSH config host blocks
        Task {
            try? await SSHConfigService().removeAllHostBlocks()
        }

        // 5. Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: Constants.Persistence.profilesKey)
        UserDefaults.standard.removeObject(forKey: Constants.Persistence.directoriesKey)

        // 6. Remove ~/.config/mimo/ directory
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mimo")
        try? FileManager.default.removeItem(at: configDir)

        showExportImportStatus("All Mimo data has been reset")
    }

    private func showExportImportStatus(_ message: String) {
        exportImportStatus = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                exportImportStatus = nil
            }
        }
    }
}
