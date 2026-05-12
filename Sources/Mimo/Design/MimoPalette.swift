//
//  MimoPalette.swift
//  Mimo
//
//  Theme-aware design tokens. Every property reads MimoThemeStore.shared.theme
//  on access — views that observe the store re-render and pick up the new values.
//

import SwiftUI
import AppKit

enum MimoEmotion: Int, CaseIterable, Hashable {
    case joy        // warm sunshine yellow / honey at night / pastel butter / neon yellow
    case sadness    // soft melancholy blue / twilight / pastel periwinkle / electric cyan
    case anger      // warm fire red / ember / pastel coral / neon magenta
    case fear       // pensive lavender / deep lavender / pastel lilac / electric purple
    case disgust    // bright mint green / deep mint / pastel pistachio / acid lime

    var name: String {
        switch self {
        case .joy: return "Joy"
        case .sadness: return "Sadness"
        case .anger: return "Anger"
        case .fear: return "Fear"
        case .disgust: return "Disgust"
        }
    }

    /// The core body color — varies per theme.
    var body: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream:
            switch self {
            case .joy:     return Color(light: .rgb(0xFFCB3B), dark: .rgb(0xFFD75A))
            case .sadness: return Color(light: .rgb(0x5A8FD8), dark: .rgb(0x7AA9E8))
            case .anger:   return Color(light: .rgb(0xE55A4E), dark: .rgb(0xF37268))
            case .fear:    return Color(light: .rgb(0xA989D9), dark: .rgb(0xBFA0E8))
            case .disgust: return Color(light: .rgb(0x86C66D), dark: .rgb(0x9CD984))
            }
        case .light:
            // Pastel, soft-saturation. Reads as illustrated children's book.
            switch self {
            case .joy:     return .rgb(0xFFD455)
            case .sadness: return .rgb(0x79A8E5)
            case .anger:   return .rgb(0xF07065)
            case .fear:    return .rgb(0xBC9DE0)
            case .disgust: return .rgb(0x9DD588)
            }
        case .night:
            switch self {
            case .joy:     return .rgb(0xE8B83A)
            case .sadness: return .rgb(0x4A7CC0)
            case .anger:   return .rgb(0xD04A40)
            case .fear:    return .rgb(0x9272BF)
            case .disgust: return .rgb(0x6FA85C)
            }
        case .retro:
            // Neon. Saturation cranked, almost glowing.
            switch self {
            case .joy:     return .rgb(0xFFEE00)
            case .sadness: return .rgb(0x00E5FF)
            case .anger:   return .rgb(0xFF1A5C)
            case .fear:    return .rgb(0xB045FF)
            case .disgust: return .rgb(0x7FFF00)
            }
        }
    }

    /// Lighter wash for surfaces, badge backgrounds.
    var wash: Color {
        switch MimoThemeStore.shared.theme {
        case .retro:    return body.opacity(0.20)
        case .night:    return body.opacity(0.22)
        case .light:    return body.opacity(0.18)
        case .daydream: return body.opacity(0.16)
        }
    }

    var tint: Color { body.opacity(0.32) }

    /// The upper-left highlight that gives the mascot its 3D pop.
    var highlight: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream:
            switch self {
            case .joy:     return .rgb(0xFFE680)
            case .sadness: return .rgb(0xA8C8F0)
            case .anger:   return .rgb(0xF59A92)
            case .fear:    return .rgb(0xD4BDF0)
            case .disgust: return .rgb(0xB9E0A8)
            }
        case .light:
            switch self {
            case .joy:     return .rgb(0xFFE89A)
            case .sadness: return .rgb(0xB8D2F0)
            case .anger:   return .rgb(0xF7A89F)
            case .fear:    return .rgb(0xD8C5EE)
            case .disgust: return .rgb(0xC5E5B5)
            }
        case .night:
            switch self {
            case .joy:     return .rgb(0xFFD675)
            case .sadness: return .rgb(0x88B0E0)
            case .anger:   return .rgb(0xE88078)
            case .fear:    return .rgb(0xB8A0D8)
            case .disgust: return .rgb(0x95C485)
            }
        case .retro:
            // Highlight is even more luminescent — pure light core.
            switch self {
            case .joy:     return .rgb(0xFFF876)
            case .sadness: return .rgb(0x88F0FF)
            case .anger:   return .rgb(0xFF6E9A)
            case .fear:    return .rgb(0xD088FF)
            case .disgust: return .rgb(0xC8FF88)
            }
        }
    }
}

enum MimoPalette {
    // MARK: - Surfaces

    static var surface: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0xFBF5EA), dark: .rgb(0x1A1B2F))
        case .light:    return .rgb(0xFFFCF5)
        case .night:    return .rgb(0x14152A)
        case .retro:    return .rgb(0x1A0F3D)
        }
    }

    static var surfaceElevated: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0xFFFFFF), dark: .rgb(0x252748))
        case .light:    return .rgb(0xFFFFFF)
        case .night:    return .rgb(0x1F2042)
        case .retro:    return .rgb(0x2A1F5A)
        }
    }

    static var surfaceSunken: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0xF2EADC), dark: .rgb(0x14152A))
        case .light:    return .rgb(0xF5EFE0)
        case .night:    return .rgb(0x0E0E1F)
        case .retro:    return .rgb(0x0F0828)
        }
    }

    // MARK: - Ink

    static var ink: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0x2D2A26), dark: .rgb(0xF4EFE5))
        case .light:    return .rgb(0x1F1C18)
        case .night:    return .rgb(0xF4EFE5)
        case .retro:    return .rgb(0xE8F4FF)
        }
    }

    static var inkSecondary: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0x6B635A), dark: .rgb(0xA09787))
        case .light:    return .rgb(0x5A5247)
        case .night:    return .rgb(0xB0A89A)
        case .retro:    return .rgb(0xA090C8)
        }
    }

    static var inkTertiary: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0x9A8F82), dark: .rgb(0x756D60))
        case .light:    return .rgb(0x8A8275)
        case .night:    return .rgb(0x6B6258)
        case .retro:    return .rgb(0x605078)
        }
    }

    // MARK: - Accent

    /// The Mimo brand action color — marigold / coral / ember / hot-pink per theme.
    static var marigold: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: .rgb(0xE8853B), dark: .rgb(0xF0975A))
        case .light:    return .rgb(0xFF8C5A)
        case .night:    return .rgb(0xFF7A4D)
        case .retro:    return .rgb(0xFF2D95)
        }
    }

    static var shadow: Color {
        switch MimoThemeStore.shared.theme {
        case .daydream: return Color(light: Color.black.opacity(0.12), dark: Color.black.opacity(0.40))
        case .light:    return Color.black.opacity(0.10)
        case .night:    return Color.black.opacity(0.55)
        case .retro:    return Color.black.opacity(0.60)
        }
    }

    // MARK: - Profile color derivation

    static func emotion(for profileID: UUID) -> MimoEmotion {
        let bytes = withUnsafeBytes(of: profileID.uuid) { Array($0) }
        let sum = bytes.reduce(0) { $0 &+ Int($1) }
        return MimoEmotion.allCases[sum % MimoEmotion.allCases.count]
    }
}

// MARK: - Color helpers

extension Color {
    /// Light/dark adaptive color builder. Used inside Daydream theme.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    /// Hex helper. `0xRRGGBB`.
    static func rgb(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
