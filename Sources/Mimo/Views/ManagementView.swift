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
    @StateObject private var viewModel = ManagementViewModel()
    @StateObject private var sshKeysViewModel = SSHKeysViewModel()

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
        }
        .animation(MimoMotion.settle, value: sshKeysViewModel.statusMessage)
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
            MimoEyes(palette: MimoEmotion.disgust.palette, size: 14)
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
                    case .directories, .signing:
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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
            }
        }
        .animation(MimoMotion.snap, value: appModel.selectedManagementTab)
    }
}
