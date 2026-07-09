//
//  AboutView.swift
//  Mimo
//
//  Mimo's bio page — meet the character. Theme picker lives here.
//

import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var themeStore = MimoThemeStore.shared
    @State private var mascotMood: MimoMascot.Mood = .idle
    @State private var emotionIndex: Int = 0

    private var palette: MimoPaintPalette {
        MimoEmotion.allCases[emotionIndex % MimoEmotion.allCases.count].palette
    }

    var body: some View {
        ZStack {
            MimoPalette.surface
            MimoStarfield(density: 30).opacity(themeStore.theme == .night ? 0.55 : 0.4).blendMode(.plusLighter)

            VStack(spacing: 0) {
                Button {
                    emotionIndex += 1
                    mascotMood = .happy
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        mascotMood = .idle
                    }
                } label: {
                    MimoMascot(mood: mascotMood, palette: palette, size: 130)
                        .frame(width: 170, height: 185)
                }
                .buttonStyle(.plain)
                .mimoPress()
                .padding(.top, 18)

                Text(Constants.Strings.appName)
                    .font(MimoFont.display(32))
                    .foregroundStyle(MimoPalette.ink)
                    .padding(.top, 2)

                Text("who do you want to be today?")
                    .font(MimoFont.body(12))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .padding(.top, 2)

                versionPill
                    .padding(.top, 10)

                themePicker
                    .padding(.top, 14)

                autoSwitchToggle
                    .padding(.top, 12)

                MimoDivider()
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)

                VStack(spacing: 8) {
                    Text("A tiny shape-shifter that swaps your git identity\ndepending on the repo you walk into.")
                        .multilineTextAlignment(.center)
                        .font(MimoFont.body(11))
                        .foregroundStyle(MimoPalette.inkSecondary)

                    Link(destination: URL(string: "https://github.com/sriinnu/Mimo")!) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                            Text("github.com/sriinnu/Mimo")
                                .font(MimoFont.mono(10, weight: .semibold))
                        }
                        .foregroundStyle(MimoPalette.marigold)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                Text(copyrightText)
                    .font(MimoFont.caption(10))
                    .foregroundStyle(MimoPalette.inkTertiary)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: Constants.Layout.aboutWidth, height: 560)
    }

    // MARK: - Version

    @ViewBuilder
    private var versionPill: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        HStack(spacing: 6) {
            Text("v\(version)")
                .font(MimoFont.mono(11, weight: .bold))
            Text("· build \(build)")
                .font(MimoFont.mono(10))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(MimoPalette.inkSecondary)
        .background(
            Capsule(style: .continuous)
                .fill(MimoPalette.surfaceSunken)
        )
    }

    // MARK: - Theme picker

    @ViewBuilder
    private var themePicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(MimoTheme.allCases) { theme in
                    themeChip(theme)
                }
            }
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(MimoPalette.surfaceSunken)
            )

            Text(themeStore.theme.tagline)
                .font(MimoFont.caption(10, weight: .medium))
                .foregroundStyle(MimoPalette.inkTertiary)
                .animation(MimoMotion.snap, value: themeStore.theme)
        }
    }

    @ViewBuilder
    private func themeChip(_ theme: MimoTheme) -> some View {        let isSelected = themeStore.theme == theme

        Button {
            themeStore.setTheme(theme)
        } label: {
            Text(theme.displayName)
                .font(MimoFont.body(11, weight: .bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? .white : MimoPalette.inkSecondary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? MimoPalette.marigold : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .mimoPress()
    }

    private var copyrightText: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Created by Srinivas Pendela · © 2026"
    }

    // MARK: - Auto-switch toggle

    /// Opt-in: flip to the expected identity the moment you enter a repo whose
    /// mapped identity differs from the active one. Off by default — the
    /// mismatch card's "Switch to …" button is the always-safe path.
    @ViewBuilder
    private var autoSwitchToggle: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MimoPalette.surfaceSunken)
                    .frame(width: 28, height: 28)
                Image(systemName: Constants.SystemImage.switchProfile)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MimoPalette.marigold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-switch on mismatch")
                    .font(MimoFont.body(12, weight: .semibold))
                    .foregroundStyle(MimoPalette.ink)
                Text("Switch the moment you enter a repo expecting a different identity.")
                    .font(MimoFont.caption(9))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: $appModel.autoSwitchOnMismatch)
                .labelsHidden()
                .tint(MimoPalette.marigold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MimoPalette.surfaceSunken.opacity(0.5))
        )
        .padding(.horizontal, 20)
    }
}
