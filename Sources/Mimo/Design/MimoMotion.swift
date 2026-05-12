//
//  MimoMotion.swift
//  Mimo
//
//  Pixar-principled motion curves: snappy springs with personality.
//  Linear easing is banned — everything has weight.
//

import SwiftUI

enum MimoMotion {
    /// The default — quick, slightly bouncy. For most state changes.
    static let snap = Animation.spring(response: 0.32, dampingFraction: 0.72)

    /// Bouncier — for celebratory moments (profile activated, clone succeeded).
    static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.58)

    /// Settled — for subtle settling motions (status badge appear, divider reveal).
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.85)

    /// Fast — for hover/press feedback. Below 200ms so it feels immediate.
    static let hover = Animation.spring(response: 0.18, dampingFraction: 0.85)

    /// Heartbeat — for ambient mascot life (blink interval, idle sway).
    static let heartbeat = Animation.easeInOut(duration: 0.18)
}

/// Squash-on-press modifier — applies a tiny scale dip while the gesture is active.
struct MimoPress: ViewModifier {
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.94 : 1.0)
            .animation(MimoMotion.hover, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}

extension View {
    func mimoPress() -> some View { modifier(MimoPress()) }
}
