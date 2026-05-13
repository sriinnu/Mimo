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
        case sleeping   // closed eyes (horizontal line)
    }

    var mood: Mood = .idle
    var palette: MimoPaintPalette = MimoEmotion.joy.palette
    var size: CGFloat = 100
    var animateAmbient: Bool = true

    @State private var blinking = false
    @State private var bouncing = false

    private var bodyWidth: CGFloat { size * 0.86 }
    private var bodyHeight: CGFloat { size * 1.02 }
    private let pupil = Color(red: 0.14, green: 0.11, blue: 0.09)

    var body: some View {
        ZStack {
            tuft
                .offset(y: -(bodyHeight / 2) - size * 0.06)
            bodyShape
            eyesLayer
                .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size * 1.3)
        .scaleEffect(x: bouncing ? 1.08 : 1.0,
                     y: bouncing ? 0.94 : 1.0,
                     anchor: .bottom)
        .rotationEffect(.degrees(mood == .curious ? -8 : 0), anchor: .bottom)
        .offset(y: mood == .worried ? size * 0.03 : 0)
        .animation(MimoMotion.snap, value: mood)
        .animation(MimoMotion.bounce, value: bouncing)
        .animation(MimoMotion.bounce, value: palette)
        .task(id: mood) {
            if mood == .happy {
                bouncing = true
                try? await Task.sleep(nanoseconds: 220_000_000)
                bouncing = false
            }
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
        HStack(spacing: size * 0.13) {
            eye
            eye
        }
        .scaleEffect(y: blinking ? 0.08 : 1.0, anchor: .center)
        .animation(MimoMotion.heartbeat, value: blinking)
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
        case .idle, .curious:
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

// MARK: - Status bar variant (eyes only)

struct MimoEyes: View {
    var palette: MimoPaintPalette = MimoEmotion.joy.palette
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: size * 0.18) {
            eyeDot
            eyeDot
        }
        .frame(width: size, height: size)
    }

    private var eyeDot: some View {
        ZStack {
            Circle()
                .fill(palette.body)
                .frame(width: size * 0.42, height: size * 0.42)
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.11, height: size * 0.11)
                .offset(x: size * 0.06, y: -size * 0.06)
        }
    }
}

/// Renders the Mimo eyes to an NSImage for use as the status bar icon.
@MainActor
func mimoStatusBarImage(palette: MimoPaintPalette, size: CGFloat = 18) -> NSImage? {
    let renderer = ImageRenderer(content: MimoEyes(palette: palette, size: size))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    return renderer.nsImage
}
