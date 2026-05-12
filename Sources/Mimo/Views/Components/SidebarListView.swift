//
//  SidebarListView.swift
//  Mimo
//

import SwiftUI

struct SidebarListView<Item: Identifiable, Row: View>: View {
    let title: String
    let subtitle: String
    let items: [Item]
    @ViewBuilder let rowContent: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MimoFont.caption(11, weight: .bold))
                    .foregroundStyle(MimoPalette.inkSecondary)
                    .textCase(.uppercase)

                Text(subtitle)
                    .font(MimoFont.caption(10))
                    .foregroundStyle(MimoPalette.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        rowContent(item)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}
