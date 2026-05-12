//
//  MimoTheme.swift
//  Mimo
//
//  Two themes — Daydream (warm Pixar daylight, adapts to OS) and
//  Night (always-dark, cosmic, ember accents). Persisted in UserDefaults.
//

import SwiftUI
import Combine

enum MimoTheme: String, CaseIterable, Identifiable {
    case daydream  // light/dark adaptive, warm cream + midnight
    case light     // always-light, bright paper, pastel emotions
    case night     // always-dark, deep indigo + ember accents
    case retro     // synthwave neon — navy-purple + hot pink + acid emotions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daydream: return "Daydream"
        case .light:    return "Light"
        case .night:    return "Night"
        case .retro:    return "Retro"
        }
    }

    var tagline: String {
        switch self {
        case .daydream: return "warm pixar daylight"
        case .light:    return "bright paper morning"
        case .night:    return "soul cosmic night"
        case .retro:    return "synthwave neon dream"
        }
    }
}

final class MimoThemeStore: ObservableObject, @unchecked Sendable {
    static let shared = MimoThemeStore()

    private let key = "com.sriinnu.mimo.theme"

    @Published var theme: MimoTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? MimoTheme.daydream.rawValue
        self.theme = MimoTheme(rawValue: raw) ?? .daydream
    }

    func setTheme(_ theme: MimoTheme) {
        withAnimation(MimoMotion.snap) {
            self.theme = theme
        }
    }
}
