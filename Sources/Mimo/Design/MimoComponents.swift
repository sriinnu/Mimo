//
//  MimoComponents.swift
//  Mimo
//
//  Card, pill button, badge, divider — the reusable surface vocabulary.
//

import SwiftUI

// MARK: - Card surface

struct MimoCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 20
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(elevated ? MimoPalette.surfaceElevated : MimoPalette.surface)
            )
            .shadow(
                color: elevated ? MimoPalette.shadow : .clear,
                radius: elevated ? 14 : 0,
                x: 0,
                y: elevated ? 4 : 0
            )
    }
}

extension View {
    func mimoCard(cornerRadius: CGFloat = 20, elevated: Bool = true) -> some View {
        modifier(MimoCardStyle(cornerRadius: cornerRadius, elevated: elevated))
    }
}

// MARK: - Pill button

struct MimoPillButton: View {
    var title: String
    var icon: String?
    var emotion: MimoEmotion? = nil
    var prominent: Bool = false
    var action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(MimoFont.body(13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(hovered ? 1.04 : 1.0)
            .animation(MimoMotion.hover, value: hovered)
        }
        .buttonStyle(.plain)
        .mimoPress()
        .onHover { hovered = $0 }
    }

    private var background: Color {
        if prominent {
            return emotion?.body ?? MimoPalette.marigold
        }
        if let emotion {
            return emotion.wash
        }
        return MimoPalette.surfaceSunken
    }

    private var foreground: Color {
        if prominent { return .white }
        return MimoPalette.ink
    }

    private var borderColor: Color {
        if prominent { return .clear }
        return MimoPalette.shadow.opacity(0.4)
    }
}

// MARK: - Badge

struct MimoBadge: View {
    var text: String
    var emotion: MimoEmotion = .joy
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(MimoFont.caption(10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(emotion.body)
        .background(
            Capsule(style: .continuous)
                .fill(emotion.wash)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(emotion.body.opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Soft divider

struct MimoDivider: View {
    var body: some View {
        Rectangle()
            .fill(MimoPalette.inkTertiary.opacity(0.18))
            .frame(height: 1)
    }
}

// MARK: - Starfield (subtle dark-mode background sparkle)

struct MimoStarfield: View {
    var density: Int = 18
    @State private var seed = Double.random(in: 0...1)

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRng(seed: 42)
            for _ in 0..<density {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let r = 0.4 + CGFloat(rng.next()) * 1.0
                let alpha = 0.15 + rng.next() * 0.35
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededRng {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z & 0xFFFFFFFF) / Double(UInt32.max)
    }
}

