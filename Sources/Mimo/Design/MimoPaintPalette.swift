//
//  MimoPaintPalette.swift
//  Mimo
//
//  The colors a view actually paints with. A small value type that any
//  color source (profile identity, mascot mood/emotion, system status)
//  can produce, so visual components don't have to know which kind they got.
//

import SwiftUI

struct MimoPaintPalette: Equatable, Hashable {
    /// Stable identifier — used for animation `value:` triggers so SwiftUI
    /// re-animates when the source changes, even if two palettes resolve
    /// to the same `body` color value.
    let id: String
    let body: Color
    let highlight: Color
    let wash: Color
    let tint: Color

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension MimoEmotion {
    /// Use for system-state-flavored views (status badges, error pills, mascot
    /// reactive moments). Not for identity — identities use `MimoProfileColor`.
    var palette: MimoPaintPalette {
        MimoPaintPalette(
            id: "emotion.\(rawValue)",
            body: body,
            highlight: highlight,
            wash: wash,
            tint: tint
        )
    }
}

extension MimoProfileColor {
    /// The identity palette — what a profile-tied view paints with.
    var palette: MimoPaintPalette {
        MimoPaintPalette(
            id: "profile.\(rawValue)",
            body: body,
            highlight: highlight,
            wash: wash,
            tint: tint
        )
    }
}
