//
//  MimoProfileColor.swift
//  Mimo
//
//  The curated identity palette. Eight warm, illustrated colors users pick
//  from when creating a profile. Decoupled from MimoEmotion (which is now
//  reserved for mascot/system-state moments, not identity).
//
//  Why these eight: each reads as a "place" or "role" more than a feeling,
//  scales beyond five identities, and survives both light and dark themes
//  without retuning. No two should be confusable at 18pt status-bar size.
//

import SwiftUI

enum MimoProfileColor: String, CaseIterable, Identifiable, Codable, Hashable {
    case sunshine    // warm gold — default, the "happy path" identity
    case coral       // sunset coral — playful, personal
    case sage        // muted forest green — open source, growth
    case plum        // deep plum — work, formal
    case twilight    // dusty blue — focused, quiet
    case terracotta  // earthy red-orange — bold, side-project energy
    case honey       // pale gold — light, drafty experiments
    case lavender    // soft lilac — design, study

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunshine:   return "Sunshine"
        case .coral:      return "Coral"
        case .sage:       return "Sage"
        case .plum:       return "Plum"
        case .twilight:   return "Twilight"
        case .terracotta: return "Terracotta"
        case .honey:      return "Honey"
        case .lavender:   return "Lavender"
        }
    }

    /// Body color — what fills the chip, tints the mascot, lights the badge.
    /// Tuned to read in both light and dark themes; theme-specific overrides
    /// can be added here if any color looks off in `night` or `retro`.
    var body: Color {
        switch MimoThemeStore.shared.theme {
        case .retro:
            // Neon themes push every color toward saturation. These keep the
            // identity-readable distinction without going acid-bright.
            switch self {
            case .sunshine:   return .rgb(0xFFD83A)
            case .coral:      return .rgb(0xFF6E8F)
            case .sage:       return .rgb(0x6FE0A0)
            case .plum:       return .rgb(0xC472FF)
            case .twilight:   return .rgb(0x6EC8FF)
            case .terracotta: return .rgb(0xFF8A5C)
            case .honey:      return .rgb(0xFFE48F)
            case .lavender:   return .rgb(0xD0A0FF)
            }
        case .night:
            switch self {
            case .sunshine:   return .rgb(0xE8B83A)
            case .coral:      return .rgb(0xE87568)
            case .sage:       return .rgb(0x7EB084)
            case .plum:       return .rgb(0x9A6FA0)
            case .twilight:   return .rgb(0x6E9BC8)
            case .terracotta: return .rgb(0xC9684C)
            case .honey:      return .rgb(0xD8B870)
            case .lavender:   return .rgb(0xB098D0)
            }
        case .light:
            switch self {
            case .sunshine:   return .rgb(0xF5B83C)
            case .coral:      return .rgb(0xF47B6E)
            case .sage:       return .rgb(0x8FB593)
            case .plum:       return .rgb(0x8B5A8C)
            case .twilight:   return .rgb(0x6B8FB5)
            case .terracotta: return .rgb(0xC97456)
            case .honey:      return .rgb(0xE5C46B)
            case .lavender:   return .rgb(0xB5A0CC)
            }
        case .daydream:
            // Light/dark adaptive.
            switch self {
            case .sunshine:   return Color(light: .rgb(0xE8A12B), dark: .rgb(0xFFC754))
            case .coral:      return Color(light: .rgb(0xE56B5E), dark: .rgb(0xFB8B7E))
            case .sage:       return Color(light: .rgb(0x6FA376), dark: .rgb(0x9CCAA0))
            case .plum:       return Color(light: .rgb(0x7B4A7E), dark: .rgb(0xB088B0))
            case .twilight:   return Color(light: .rgb(0x547BA8), dark: .rgb(0x88AEDA))
            case .terracotta: return Color(light: .rgb(0xB35F44), dark: .rgb(0xE08868))
            case .honey:      return Color(light: .rgb(0xD4AE52), dark: .rgb(0xF0CE7E))
            case .lavender:   return Color(light: .rgb(0xA088BD), dark: .rgb(0xC8B4E0))
            }
        }
    }

    /// Lighter wash for surfaces, badge backgrounds, hover states.
    var wash: Color { body.opacity(0.18) }

    /// Soft mid-opacity tint — for ring outlines, hover highlights.
    var tint: Color { body.opacity(0.32) }

    /// Bright highlight for the upper-left of the mascot body — gives the 3D pop.
    /// Hand-tuned per color rather than algorithmically lightened, so each one
    /// reads warm in the same way the body does.
    var highlight: Color {
        switch MimoThemeStore.shared.theme {
        case .retro:
            switch self {
            case .sunshine:   return .rgb(0xFFF080)
            case .coral:      return .rgb(0xFFA8C0)
            case .sage:       return .rgb(0xA8F0C0)
            case .plum:       return .rgb(0xE0A8FF)
            case .twilight:   return .rgb(0xA8E8FF)
            case .terracotta: return .rgb(0xFFB890)
            case .honey:      return .rgb(0xFFF0B8)
            case .lavender:   return .rgb(0xE8C8FF)
            }
        case .night:
            switch self {
            case .sunshine:   return .rgb(0xF0D070)
            case .coral:      return .rgb(0xF09588)
            case .sage:       return .rgb(0xA0CCA8)
            case .plum:       return .rgb(0xB890BC)
            case .twilight:   return .rgb(0x90B8D8)
            case .terracotta: return .rgb(0xDC8870)
            case .honey:      return .rgb(0xE8D090)
            case .lavender:   return .rgb(0xCCB8E0)
            }
        case .light:
            switch self {
            case .sunshine:   return .rgb(0xFCD274)
            case .coral:      return .rgb(0xFAA59A)
            case .sage:       return .rgb(0xB5D2B9)
            case .plum:       return .rgb(0xB088B0)
            case .twilight:   return .rgb(0x95B0CD)
            case .terracotta: return .rgb(0xDD9C82)
            case .honey:      return .rgb(0xEFD89A)
            case .lavender:   return .rgb(0xCFC0DF)
            }
        case .daydream:
            switch self {
            case .sunshine:   return Color(light: .rgb(0xF5C570), dark: .rgb(0xFFDC85))
            case .coral:      return Color(light: .rgb(0xF09588), dark: .rgb(0xFEA89B))
            case .sage:       return Color(light: .rgb(0x9BC0A0), dark: .rgb(0xBCDEC0))
            case .plum:       return Color(light: .rgb(0xA078A8), dark: .rgb(0xCAA8CA))
            case .twilight:   return Color(light: .rgb(0x82A2C8), dark: .rgb(0xACC8E0))
            case .terracotta: return Color(light: .rgb(0xD08868), dark: .rgb(0xEDA88A))
            case .honey:      return Color(light: .rgb(0xE8C880), dark: .rgb(0xF6DCA0))
            case .lavender:   return Color(light: .rgb(0xC8B0DC), dark: .rgb(0xDDC8EA))
            }
        }
    }
}

// MARK: - Deterministic fallback assignment

extension MimoProfileColor {
    /// Picks a color from the curated palette deterministically from a UUID.
    /// Used as the default for profiles created before the colorID field existed,
    /// and as a sensible starting suggestion when creating a new profile.
    static func defaultFor(profileID: UUID) -> MimoProfileColor {
        let bytes = withUnsafeBytes(of: profileID.uuid) { Array($0) }
        let sum = bytes.reduce(0) { $0 &+ Int($1) }
        return MimoProfileColor.allCases[sum % MimoProfileColor.allCases.count]
    }
}
