//
//  SSHKeyRowView.swift
//  Mimo
//

import SwiftUI

struct SSHKeyRowView: View {
    let key: SSHKeyInfo
    @ObservedObject var viewModel: SSHKeysViewModel
    @Binding var expandedKeyIDs: Set<UUID>

    private var palette: MimoPaintPalette {
        switch key.keyType {
        case .ed25519: return MimoEmotion.joy.palette
        case .rsa:     return MimoEmotion.fear.palette
        case .ecdsa:   return MimoEmotion.serenity.palette
        case .dsa:     return MimoEmotion.anger.palette
        }
    }

    var body: some View {
        let isExpanded = expandedKeyIDs.contains(key.id)

        VStack(spacing: 0) {
            header(isExpanded: isExpanded)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }

            if isExpanded {
                MimoDivider()
                    .padding(.horizontal, 16)
                expandedSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MimoPalette.surfaceElevated)
                .shadow(color: MimoPalette.shadow, radius: 10, y: 3)
        )
    }

    @ViewBuilder
    private func header(isExpanded: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.body)
                    .frame(width: 36, height: 36)
                Image(systemName: Constants.SystemImage.key)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(key.filename)
                        .font(MimoFont.body(13, weight: .semibold))
                        .foregroundStyle(MimoPalette.ink)
                    MimoBadge(text: key.keyType.displayName, palette: palette)
                }
                if let comment = key.comment {
                    Text(comment)
                        .font(MimoFont.caption(11))
                        .foregroundStyle(MimoPalette.inkSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MimoPalette.inkSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .padding(8)
        }
        .padding(16)
    }

    @ViewBuilder
    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let fingerprint = key.fingerprint {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FINGERPRINT")
                        .font(MimoFont.caption(9, weight: .bold))
                        .foregroundStyle(MimoPalette.inkTertiary)

                    HStack(spacing: 8) {
                        Text(fingerprint)
                            .font(MimoFont.mono(11))
                            .foregroundStyle(MimoPalette.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Button {
                            copyToClipboard(fingerprint, label: "Fingerprint")
                        } label: {
                            Image(systemName: Constants.SystemImage.copy)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MimoPalette.marigold)
                                .padding(8)
                                .background(
                                    Circle().fill(MimoPalette.marigold.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .mimoPress()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MimoPalette.surfaceSunken)
                    )
                }
            }

            HStack(alignment: .top, spacing: 20) {
                dateInfo(label: "CREATED", date: key.createdAt)
                dateInfo(label: "EXPIRES", date: key.expiresAt)
                Spacer()
            }

            HStack {
                MimoPillButton(title: "Copy public key", icon: Constants.SystemImage.copy, palette: palette) {
                    viewModel.copyPublicKey(key) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            $0.trimmingCharacters(in: .whitespacesAndNewlines),
                            forType: .string
                        )
                    }
                }

                Spacer()

                Button {
                    viewModel.confirmDelete(key: key)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MimoEmotion.anger.body)
                        .padding(10)
                        .background(
                            Circle().fill(MimoEmotion.anger.wash)
                        )
                }
                .buttonStyle(.plain)
                .mimoPress()
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func dateInfo(label: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(MimoFont.caption(9, weight: .bold))
                .foregroundStyle(MimoPalette.inkTertiary)
            if let date = date {
                Text(date, style: .date)
                    .font(MimoFont.caption(11))
                    .foregroundStyle(MimoPalette.inkSecondary)
            } else {
                Text("—")
                    .font(MimoFont.caption(11))
                    .foregroundStyle(MimoPalette.inkTertiary)
            }
        }
    }

    private func toggle() {
        withAnimation(MimoMotion.snap) {
            if expandedKeyIDs.contains(key.id) {
                expandedKeyIDs.remove(key.id)
            } else {
                expandedKeyIDs.insert(key.id)
            }
        }
    }

    private func copyToClipboard(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        viewModel.showStatus("\(label) copied!")
    }
}
