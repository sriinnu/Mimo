//
//  OnboardingImportView.swift
//  Mimo
//
//  First-launch sheet. Mimo finds an existing identity in ~/.gitconfig
//  and asks the user whether to import it as the first profile — instead
//  of silently overwriting it the moment the user picks a profile later.
//

import SwiftUI

struct OnboardingImportView: View {
    @EnvironmentObject private var appModel: AppModel
    let snapshot: GitIdentitySnapshot

    var body: some View {
        VStack(spacing: 0) {
            header
            MimoDivider().padding(.horizontal, 24)
            detectedValues
            Spacer(minLength: 16)
            actionRow
        }
        .frame(width: 480)
        .padding(.vertical, 24)
        .background(MimoPalette.surface)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            MimoMascot(
                mood: .curious,
                palette: MimoEmotion.joy.palette,
                size: 56,
                animateAmbient: true
            )
            .frame(width: 72, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                Text("I found someone already here")
                    .font(MimoFont.headline(18))
                    .foregroundStyle(MimoPalette.ink)
                Text("Mimo can import this identity as your first profile so nothing gets overwritten by accident. Or start with a clean slate — your call.")
                    .font(MimoFont.body(12))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var detectedValues: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "Name", value: snapshot.userName, icon: "person")
            row(label: "Email", value: snapshot.userEmail, icon: "envelope")
            if snapshot.signingType != .none {
                row(
                    label: "Signing",
                    value: signingDescription,
                    icon: "checkmark.shield"
                )
            }
            if let key = snapshot.sshKeyPath {
                row(label: "SSH key", value: shortenPath(key), icon: "key")
            }
        }
        .padding(20)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func row(label: String, value: String?, icon: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MimoPalette.surfaceElevated)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MimoPalette.inkSecondary)
            }

            Text(label.uppercased())
                .font(MimoFont.caption(10, weight: .bold))
                .foregroundStyle(MimoPalette.inkTertiary)
                .frame(width: 72, alignment: .leading)

            Text(value ?? "—")
                .font(MimoFont.mono(12))
                .foregroundStyle(value == nil ? MimoPalette.inkTertiary : MimoPalette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                appModel.skipFirstRunImport()
            } label: {
                Text("Skip — start blank")
                    .font(MimoFont.body(12, weight: .semibold))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MimoPalette.surfaceSunken)
                    )
            }
            .buttonStyle(.plain)
            .mimoPress()

            Spacer()

            MimoPillButton(
                title: "Import as my first profile",
                icon: "sparkles",
                palette: MimoEmotion.joy.palette,
                prominent: true
            ) {
                appModel.acceptFirstRunImport()
            }
        }
        .padding(.horizontal, 24)
    }

    private var signingDescription: String {
        switch snapshot.signingType {
        case .gpg: return "GPG (\(snapshot.signingKey ?? "no key set"))"
        case .ssh: return "SSH (\(snapshot.signingKey ?? "no key set"))"
        case .none: return "off"
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
