//
//  SSHSidebarView.swift
//  Mimo
//

import SwiftUI

struct SSHSidebarView: View {
    @StateObject private var viewModel = SSHKeysViewModel()

    var body: some View {
        SidebarListView(
            title: Constants.Strings.sshKeys,
            subtitle: "\(viewModel.keys.count) keys",
            items: viewModel.keys
        ) { key in
            sshKeyRow(key: key)
        }
        .onAppear { viewModel.loadKeys() }
    }

    @ViewBuilder
    private func sshKeyRow(key: SSHKeyInfo) -> some View {
        let keyPalette: MimoPaintPalette = {
            switch key.keyType {
            case .ed25519: return MimoEmotion.joy.palette
            case .rsa:     return MimoEmotion.fear.palette
            case .ecdsa:   return MimoEmotion.serenity.palette
            case .dsa:     return MimoEmotion.anger.palette
            }
        }()

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(key.filename)
                    .font(MimoFont.mono(11, weight: .semibold))
                    .foregroundStyle(MimoPalette.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    MimoBadge(text: key.keyType.displayName, palette: keyPalette)

                    if let comment = key.comment {
                        Text(comment)
                            .font(MimoFont.caption(10))
                            .foregroundStyle(MimoPalette.inkTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
