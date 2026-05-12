//
//  MimoTypography.swift
//  Mimo
//
//  SF Pro Rounded for display + personality.
//  SF Mono for paths, emails, fingerprints — the "technical credibility" layer.
//

import SwiftUI

enum MimoFont {
    /// Display sizes — used for app name, page titles, mascot speech.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Headline — section titles, prominent labels.
    static func headline(_ size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Body — readable text.
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Caption — secondary metadata.
    static func caption(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Mono — for emails, paths, SSH keys, branch names. Slightly tighter than default.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
