//
//  MimoMascot.swift
//  Mimo
//
//  The Mimo character — a rounded blob with two big eyes that lives in
//  your menu bar. Body color shifts to match the active git profile's
//  emotion. Blinks ambiently. Bounces on celebration.
//

import SwiftUI

struct MimoMascot: View {
    enum Mood: Equatable {
        case idle       // resting, ambient blinks
        case happy      // squinted-arc eyes, brief bounce
        case curious    // head tilted, wide eyes
        case worried    // drooped eyes, slumped body
        case wincing    // eyes squeezed shut, quick head shake — wrong identity reaction
        case sleeping   // closed eyes (horizontal line)
        case phantom    // temporary identity — domino mask over eyes
    }

    var mood: Mood = .idle
    var palette: MimoPaintPalette = MimoEmotion.joy.palette
    var size: CGFloat = 100
    var animateAmbient: Bool = true

    /// Phases of the costume-change transition that plays when `palette` flips.
    /// Multi-beat squash → bounce-back → settle, so the mascot reads as
    /// *changing costumes*, not just recoloring.
    private enum MorphPhase {
        case rest       // 1.0, 1.0
        case squash     // 0.85, 1.10 — compressed sideways, pulled up
        case stretch    // 1.10, 0.92 — rebound wider, slightly squat

        var scaleX: CGFloat {
            switch self {
            case .rest: return 1.0
            case .squash: return 0.85
            case .stretch: return 1.10
            }
        }

        var scaleY: CGFloat {
            switch self {
            case .rest: return 1.0
            case .squash: return 1.10
            case .stretch: return 0.92
            }
        }
    }

    @State private var blinking = false
    @State private var bouncing = false
    @State private var morphPhase: MorphPhase = .rest
    @State private var winceShake: CGFloat = 0   // -1, 0, +1 — drives the head shake
    @State private var winceSquash = false       // flinch squash on scaleY

    private var bodyWidth: CGFloat { size * 0.86 }
    private var bodyHeight: CGFloat { size * 1.02 }
    private let pupil = Color(red: 0.14, green: 0.11, blue: 0.09)

    /// Composite rotation: curious head-tilt + wince shake.
    private var compositeRotation: Double {
        var deg: Double = 0
        if mood == .curious { deg -= 8 }
        deg += Double(winceShake) * 5
        return deg
    }

    var body: some View {
        ZStack {
            tuft
                .offset(y: -(bodyHeight / 2) - size * 0.06)
            bodyShape
            eyesLayer
                .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size * 1.3)
        .scaleEffect(x: (bouncing ? 1.08 : 1.0) * morphPhase.scaleX,
                     y: (bouncing ? 0.94 : 1.0) * (winceSquash ? 0.94 : 1.0) * morphPhase.scaleY,
                     anchor: .bottom)
        .rotationEffect(.degrees(compositeRotation), anchor: .bottom)
        .offset(y: mood == .worried ? size * 0.03 : 0)
        .animation(MimoMotion.snap, value: mood)
        .animation(MimoMotion.bounce, value: bouncing)
        .animation(MimoMotion.bounce, value: palette)
        .animation(MimoMotion.snap, value: morphPhase)
        .animation(MimoMotion.snap, value: winceShake)
        .animation(MimoMotion.snap, value: winceSquash)
        .task(id: mood) {
            if mood == .happy {
                bouncing = true
                try? await Task.sleep(nanoseconds: 220_000_000)
                bouncing = false
            }
            if mood == .wincing {
                // Wince beat: squash + ±5° head shake over ~250ms,
                // then settle. It's a flinch, not a posture.
                winceSquash = true
                winceShake = -1
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                winceShake = 1
                try? await Task.sleep(nanoseconds: 130_000_000)
                guard !Task.isCancelled else { return }
                winceShake = 0
                winceSquash = false
            } else {
                // Reset any in-flight wince state when mood flips away.
                winceShake = 0
                winceSquash = false
            }
        }
        .task(id: palette) {
            // Costume change: squash → stretch → settle. ~0.6s total.
            // Color tween runs in parallel via the existing .animation(_, value: palette).
            morphPhase = .squash
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            morphPhase = .stretch
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            morphPhase = .rest
        }
        .task {
            guard animateAmbient else { return }
            while !Task.isCancelled {
                let pauseSec = Double.random(in: 4.5...7.5)
                try? await Task.sleep(nanoseconds: UInt64(pauseSec * 1_000_000_000))
                guard !Task.isCancelled, mood != .sleeping else { continue }
                blinking = true
                try? await Task.sleep(nanoseconds: 130_000_000)
                blinking = false
            }
        }
    }

    @ViewBuilder
    private var tuft: some View {
        Circle()
            .fill(palette.body)
            .frame(width: size * 0.11, height: size * 0.11)
            .overlay(
                Circle()
                    .fill(palette.highlight)
                    .frame(width: size * 0.04, height: size * 0.04)
                    .offset(x: -size * 0.015, y: -size * 0.015)
            )
            .offset(y: bouncing ? -size * 0.04 : 0)
    }

    @ViewBuilder
    private var bodyShape: some View {
        ZStack {
            // soft drop shadow under the body
            Ellipse()
                .fill(MimoPalette.shadow)
                .frame(width: bodyWidth * 0.85, height: size * 0.10)
                .blur(radius: size * 0.04)
                .offset(y: bodyHeight * 0.48)

            // main body with radial gradient highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [palette.highlight, palette.body],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: bodyWidth, height: bodyHeight)

            // inner rim shadow at bottom — gives weight
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [.clear, .clear, MimoPalette.shadow],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: size * 0.05
                )
                .frame(width: bodyWidth, height: bodyHeight)
                .blur(radius: size * 0.012)
                .clipShape(Ellipse().size(width: bodyWidth, height: bodyHeight))
        }
    }

    @ViewBuilder
    private var eyesLayer: some View {
        ZStack {
            HStack(spacing: size * 0.13) {
                eye
                eye
            }
            .scaleEffect(y: blinking ? 0.08 : 1.0, anchor: .center)
            .animation(MimoMotion.heartbeat, value: blinking)

            if mood == .phantom {
                dominoMask
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(MimoMotion.bounce, value: mood)
    }

    /// Horizontal black band across both eyes — superhero / cat-burglar mask.
    /// Sized as a fraction of mascot `size` so it scales with the body.
    @ViewBuilder
    private var dominoMask: some View {
        // Mask roughly spans both eyes (eye width ~0.18, gap 0.13 → 0.49)
        // with a touch of slack on each side and rounded ends.
        Capsule(style: .continuous)
            .fill(pupil)
            .frame(width: size * 0.56, height: size * 0.085)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: MimoPalette.shadow.opacity(0.5),
                    radius: size * 0.01,
                    y: size * 0.006)
    }

    @ViewBuilder
    private var eye: some View {
        switch mood {
        case .happy:
            HappyArc()
                .stroke(pupil, style: StrokeStyle(lineWidth: size * 0.038, lineCap: .round))
                .frame(width: size * 0.17, height: size * 0.10)
        case .sleeping:
            Capsule()
                .fill(pupil)
                .frame(width: size * 0.16, height: size * 0.022)
        case .wincing:
            // Eyes squeezed shut — a short upward-arc line (like a
            // grimacing closed eye), thicker than the sleeping line.
            WinceArc()
                .stroke(pupil, style: StrokeStyle(lineWidth: size * 0.036, lineCap: .round))
                .frame(width: size * 0.17, height: size * 0.08)
        case .worried:
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.16, height: size * 0.16)
                Circle()
                    .fill(pupil)
                    .frame(width: size * 0.10, height: size * 0.10)
                    .offset(y: -size * 0.012)
            }
            .frame(width: size * 0.16, height: size * 0.16, alignment: .bottom)
        case .idle, .curious, .phantom:
            // Phantom uses the standard idle eye; the domino mask overlay
            // is drawn on top of the eyes layer (see `eyesLayer`).
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.18, height: size * 0.18)
                Circle()
                    .fill(pupil)
                    .frame(width: size * 0.115, height: size * 0.115)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.038, height: size * 0.038)
                    .offset(x: size * 0.028, y: -size * 0.028)
            }
        }
    }
}

private struct HappyArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.4)
        )
        return path
    }
}

/// A short, upward-arching line — eyes squeezed shut in a flinch. Opens at the
/// top, bowing slightly downward in the middle, like a grimace seen head-on.
private struct WinceArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.2)
        )
        return path
    }
}

// MARK: - Status bar variant (eyes only)

struct MimoEyes: View {
    var palette: MimoPaintPalette = MimoEmotion.joy.palette
    var size: CGFloat = 18
    /// Status-bar variant rendering. `.normal` paints the open-eye dots,
    /// `.wincing` paints squeezed-shut horizontal lines for the mismatch beat.
    var mood: Mood = .normal

    enum Mood: Equatable {
        case normal
        case wincing
    }

    var body: some View {
        HStack(spacing: size * 0.18) {
            eye
            eye
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var eye: some View {
        switch mood {
        case .normal:
            ZStack {
                Circle()
                    .fill(palette.body)
                    .frame(width: size * 0.42, height: size * 0.42)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.11, height: size * 0.11)
                    .offset(x: size * 0.06, y: -size * 0.06)
            }
        case .wincing:
            // Squeezed-shut line, drawn in the profile body color so it stays
            // recognizable as Mimo's eyes (just closed) at status-bar size.
            Capsule()
                .fill(palette.body)
                .frame(width: size * 0.42, height: size * 0.10)
        }
    }
}

/// Renders the Mimo eyes to an NSImage for use as the status bar icon.
/// `mood` selects between the resting eye-dots and the squeezed-shut wince line.
@MainActor
func mimoStatusBarImage(
    palette: MimoPaintPalette,
    size: CGFloat = 18,
    mood: MimoEyes.Mood = .normal
) -> NSImage? {
    let renderer = ImageRenderer(content: MimoEyes(palette: palette, size: size, mood: mood))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    return renderer.nsImage
}
