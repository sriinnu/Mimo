#!/usr/bin/env swift
//
//  render-app-icon.swift
//  Mimo
//
//  Renders the Mimo macOS app icon at every size declared in
//  Resources/Assets.xcassets/AppIcon.appiconset/Contents.json.
//
//  The icon shows the Mimo mascot (idle mood, .sunshine palette) centered on
//  a warm cream-to-peach radial gradient. A subtle "golden hour" glow sits
//  behind the body. Small sizes (<= 64) drop the tuft + glow + body shadow
//  and render the body slightly larger so silhouette + eyes survive Spotlight
//  / Dock minimum sizes.
//
//  Implementation note: this used to be a SwiftUI/ImageRenderer script, but
//  Swift's top-level type inference choked on the nested ZStack/RadialGradient
//  expressions (compile would hang for minutes). Switched to direct
//  Core Graphics drawing — it's a couple hundred lines of explicit geometry,
//  compiles in seconds, and gives pixel-exact control at every size.
//
//  Keep these colors in sync with:
//    - Sources/Mimo/Design/MimoProfileColor.swift  (.sunshine, light theme)
//    - Sources/Mimo/Design/MimoPalette.swift       (surface, shadow)
//
//  Run with: swift scripts/render-app-icon.swift
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Colors (mirrored from Mimo design system, daydream-light variant)

private struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    init(_ hex: UInt32, alpha: CGFloat = 1.0) {
        r = CGFloat((hex >> 16) & 0xFF) / 255.0
        g = CGFloat((hex >> 8) & 0xFF) / 255.0
        b = CGFloat(hex & 0xFF) / 255.0
        a = alpha
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var cgColor: CGColor {
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    func withAlpha(_ alpha: CGFloat) -> RGB {
        return RGB(r: r, g: g, b: b, a: alpha)
    }
}

private enum Palette {
    // Sunshine profile (light variant) — mascot body / highlight.
    static let sunshineBody      = RGB(0xE8A12B)
    static let sunshineHighlight = RGB(0xF5C570)

    // Cream surfaces (light variant).
    static let creamSurface  = RGB(0xFBF5EA)
    static let creamElevated = RGB(0xFFFCF5)

    // Hand-tuned warm peach for outer-ring of the background gradient.
    static let peach = RGB(0xF8DCB4)

    // Mascot eye + ground shadow.
    static let pupil  = RGB(r: 0.14, g: 0.11, b: 0.09)
    static let shadow = RGB(r: 0,    g: 0,    b: 0, a: 0.12)
}

// MARK: - Drawing helpers

private func makeContext(size: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Could not create CGContext at size \(size)")
    }
    // No CTM flip — native CG coordinates (origin at bottom-left, Y up).
    // The geometry below interprets `topY` and `bottomY` explicitly so the
    // intent is clear. PNG encoding doesn't care which way Y points.
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

private func radialGradient(
    in ctx: CGContext,
    colors: [RGB],
    locations: [CGFloat]? = nil,
    startCenter: CGPoint,
    startRadius: CGFloat,
    endCenter: CGPoint,
    endRadius: CGFloat,
    clipRect: CGRect? = nil
) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = colors.map { $0.cgColor } as CFArray
    let locs: [CGFloat] = locations ?? {
        // Even spacing across the gradient.
        if colors.count == 1 { return [0.0] }
        return (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
    }()
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locs) else {
        return
    }
    ctx.saveGState()
    if let clip = clipRect {
        ctx.clip(to: clip)
    }
    ctx.drawRadialGradient(
        gradient,
        startCenter: startCenter,
        startRadius: startRadius,
        endCenter: endCenter,
        endRadius: endRadius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

private func filledEllipse(_ ctx: CGContext, rect: CGRect, color: RGB) {
    ctx.saveGState()
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: rect)
    ctx.restoreGState()
}

/// Draw an approximate Gaussian-blurred ellipse: stack multiple semi-
/// transparent ellipses at increasing inset. Cheap, no Core Image dependency,
/// good enough for a soft drop shadow under the mascot.
private func softShadowEllipse(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, color: RGB, blur: CGFloat) {
    let layers = 6
    for i in 0..<layers {
        let t = CGFloat(i) / CGFloat(layers - 1) // 0...1
        let grow = blur * (1 - t) * 2
        let w = width + grow
        let h = height + grow
        let alpha = color.a * (1 - t) * 0.45
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        filledEllipse(ctx, rect: rect, color: color.withAlpha(alpha))
    }
}

// MARK: - Icon drawing

private struct IconParams {
    /// Total canvas pixel dimension (square).
    let canvas: CGFloat
    /// Whether to draw secondary detail (tuft, glow, body shadow, rim).
    let detail: Bool
    /// Fraction of canvas the mascot's body width takes up.
    let mascotFraction: CGFloat
    /// Optical vertical offset for the mascot (negative = up).
    let mascotYOffset: CGFloat
}

private func drawIcon(size: Int) -> CGImage {
    let ctx = makeContext(size: size)
    let canvas = CGFloat(size)

    // Tier the rendering based on icon pixel size. Below 128 we drop fine
    // detail so the silhouette + eyes survive crushing down.
    let detail = size >= 128
    let mascotFraction: CGFloat = detail ? 0.62 : 0.78
    // Positive yOffset = nudge mascot UPWARD in screen space.
    // CG default coords: larger Y = higher on screen.
    let yOffset: CGFloat = detail ? canvas * 0.03 : 0

    let params = IconParams(
        canvas: canvas,
        detail: detail,
        mascotFraction: mascotFraction,
        mascotYOffset: yOffset
    )

    drawBackground(ctx, params: params)
    if detail {
        drawGoldenHourGlow(ctx, params: params)
    }
    drawMascot(ctx, params: params)

    guard let image = ctx.makeImage() else {
        fatalError("Could not produce CGImage at size \(size)")
    }
    return image
}

private func drawBackground(_ ctx: CGContext, params: IconParams) {
    // Warm cream-to-peach radial gradient. Bright center pulled slightly
    // above the geometric middle so the top of the icon reads a touch
    // brighter (implied light source above).
    //
    // CG coords: y=0 is bottom, y=canvas is top. Center at y = 0.58*canvas
    // is slightly above the middle.
    let canvas = params.canvas
    let rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)

    // Fill base color first to guarantee no transparent corners.
    ctx.saveGState()
    ctx.setFillColor(Palette.creamSurface.cgColor)
    ctx.fill(rect)
    ctx.restoreGState()

    let center = CGPoint(x: canvas * 0.5, y: canvas * 0.58)
    radialGradient(
        in: ctx,
        colors: [
            Palette.creamElevated,
            Palette.creamSurface,
            Palette.peach,
        ],
        locations: [0.0, 0.55, 1.0],
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: canvas * 0.72,
        clipRect: rect
    )
}

private func drawGoldenHourGlow(_ ctx: CGContext, params: IconParams) {
    // Glow centered roughly on the mascot's body, slightly above middle.
    let canvas = params.canvas
    let center = CGPoint(x: canvas * 0.5, y: canvas * 0.5 + params.mascotYOffset)
    radialGradient(
        in: ctx,
        colors: [
            Palette.sunshineBody.withAlpha(0.32),
            Palette.sunshineBody.withAlpha(0.0),
        ],
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: canvas * 0.42
    )
}

private func drawMascot(_ ctx: CGContext, params: IconParams) {
    // CG coords: y=0 bottom, y=canvas top. Larger Y = higher on screen.
    // "Above" = +Y, "Below" = -Y.
    let canvas = params.canvas

    // Mascot's reference "size" — body width = size * 0.86, height = size * 1.02.
    // Pick mascot size so body width = canvas * mascotFraction.
    let mascotSize = (canvas * params.mascotFraction) / 0.86
    let bodyWidth  = mascotSize * 0.86
    let bodyHeight = mascotSize * 1.02

    let centerX = canvas * 0.5
    let centerY = canvas * 0.5 + params.mascotYOffset
    let bodyCenter = CGPoint(x: centerX, y: centerY)

    let bodyRect = CGRect(
        x: bodyCenter.x - bodyWidth / 2,
        y: bodyCenter.y - bodyHeight / 2,
        width: bodyWidth,
        height: bodyHeight
    )
    // In natural CG coords:
    //   bodyRect.minY = bottom of body
    //   bodyRect.maxY = top of body

    // 1. Soft ground shadow UNDER the body (lower Y in natural CG).
    if params.detail {
        softShadowEllipse(
            ctx,
            center: CGPoint(x: centerX, y: bodyRect.minY - mascotSize * 0.02),
            width: bodyWidth * 0.85,
            height: mascotSize * 0.10,
            color: Palette.shadow,
            blur: mascotSize * 0.06
        )
    }

    // 2. Body — base flat fill in sunshineBody, then a soft radial
    //    highlight blended on top from the upper-left (low X, high Y).
    //    Done as two passes (flat + overlay) rather than one gradient so
    //    we don't have to fight CG's `drawsBeforeStartLocation` semantics
    //    for an off-center radial start.
    ctx.saveGState()
    ctx.beginPath()
    ctx.addEllipse(in: bodyRect)
    ctx.clip()

    // 2a. Flat body fill.
    ctx.setFillColor(Palette.sunshineBody.cgColor)
    ctx.fill(bodyRect)

    // 2b. Radial highlight — light at center (highlight color), fading to
    //     transparent at endRadius. Composited over the flat fill.
    let highlightCenter = CGPoint(
        x: bodyRect.minX + bodyWidth * 0.34,
        y: bodyRect.maxY - bodyHeight * 0.28
    )
    radialGradient(
        in: ctx,
        colors: [Palette.sunshineHighlight.withAlpha(1.0), Palette.sunshineHighlight.withAlpha(0.0)],
        startCenter: highlightCenter,
        startRadius: 0,
        endCenter: highlightCenter,
        endRadius: mascotSize * 0.58
    )

    ctx.restoreGState()

    // 3. Soft inner rim shading at the bottom (full detail only) — weight.
    if params.detail {
        drawInnerRimShadow(ctx, rect: bodyRect, blur: mascotSize * 0.012, lineWidth: mascotSize * 0.05)
    }

    // 4. Tuft on top (full detail only). Sits just touching the body crown
    // — slight overlap so it reads as one character, not body + floating dot.
    if params.detail {
        let tuftDiameter = mascotSize * 0.13
        let tuftCenter = CGPoint(
            x: centerX,
            // Tuft is ABOVE the body top = higher Y in natural CG.
            y: bodyRect.maxY + mascotSize * 0.005 + tuftDiameter / 2
        )
        let tuftRect = CGRect(
            x: tuftCenter.x - tuftDiameter / 2,
            y: tuftCenter.y - tuftDiameter / 2,
            width: tuftDiameter,
            height: tuftDiameter
        )
        filledEllipse(ctx, rect: tuftRect, color: Palette.sunshineBody)
        // Highlight glint — upper-left of the tuft = (-X, +Y).
        let glintD = mascotSize * 0.04
        let glintRect = CGRect(
            x: tuftCenter.x - glintD / 2 - mascotSize * 0.015,
            y: tuftCenter.y - glintD / 2 + mascotSize * 0.015,
            width: glintD,
            height: glintD
        )
        filledEllipse(ctx, rect: glintRect, color: Palette.sunshineHighlight)
    }

    // 5. Eyes
    drawEyes(ctx, params: params, mascotSize: mascotSize, bodyCenter: bodyCenter)
}

private func drawInnerRimShadow(_ ctx: CGContext, rect: CGRect, blur: CGFloat, lineWidth: CGFloat) {
    // Soft bottom-rim shading inside the body. Radial gradient whose far
    // edge hugs the body's bottom and whose center sits just below the
    // body — shading is heaviest at the bottom arc, fades to nothing
    // toward the top half. No hard edges.
    //
    // Natural CG coords: rect.minY = bottom edge of body.
    _ = lineWidth
    _ = blur

    ctx.saveGState()
    ctx.beginPath()
    ctx.addEllipse(in: rect)
    ctx.clip()

    let centerX = rect.midX
    let centerY = rect.minY - rect.height * 0.05 // just below the body bottom
    let center = CGPoint(x: centerX, y: centerY)

    let inner = rect.height * 0.30
    let outer = rect.height * 0.85

    radialGradient(
        in: ctx,
        colors: [
            Palette.shadow.withAlpha(0.0),
            Palette.shadow.withAlpha(0.18),
            Palette.shadow.withAlpha(0.32),
        ],
        locations: [0.0, 0.6, 1.0],
        startCenter: center,
        startRadius: inner,
        endCenter: center,
        endRadius: outer
    )

    ctx.restoreGState()
}

private func drawEyes(_ ctx: CGContext, params: IconParams, mascotSize: CGFloat, bodyCenter: CGPoint) {
    // Idle eyes from MimoMascot.swift:
    //   white circle (eye)          @ size * 0.18
    //   pupil circle                @ size * 0.115
    //   white glint                 @ size * 0.038, offset (+0.028, -0.028)
    // Eye gap (between eyes)        @ size * 0.13
    // Eye layer Y offset            @ -size * 0.06 from mascot center
    //
    // At simplified detail (small icon sizes), bump eyes ~1.18x so they
    // stay legible after Apple's mask + Dock downscale.

    let eyeScale: CGFloat = params.detail ? 1.0 : 1.18
    let eyeDiameter   = mascotSize * 0.18  * eyeScale
    let pupilDiameter = mascotSize * 0.115 * eyeScale
    let glintDiameter = mascotSize * 0.038 * eyeScale
    let gap           = mascotSize * 0.13

    // Eyes sit slightly above body center (natural CG: larger Y = up).
    let eyeCenterY = bodyCenter.y + mascotSize * 0.06
    let leftEyeX  = bodyCenter.x - (eyeDiameter / 2 + gap / 2)
    let rightEyeX = bodyCenter.x + (eyeDiameter / 2 + gap / 2)

    for eyeX in [leftEyeX, rightEyeX] {
        // White sclera
        let eyeRect = CGRect(
            x: eyeX - eyeDiameter / 2,
            y: eyeCenterY - eyeDiameter / 2,
            width: eyeDiameter,
            height: eyeDiameter
        )
        filledEllipse(ctx, rect: eyeRect, color: RGB(0xFFFFFF))

        // Pupil
        let pupilRect = CGRect(
            x: eyeX - pupilDiameter / 2,
            y: eyeCenterY - pupilDiameter / 2,
            width: pupilDiameter,
            height: pupilDiameter
        )
        filledEllipse(ctx, rect: pupilRect, color: Palette.pupil)

        // Glint — upper-right of pupil = (+X, +Y) in natural CG.
        let glintCenter = CGPoint(
            x: eyeX + eyeDiameter * 0.155,
            y: eyeCenterY + eyeDiameter * 0.155
        )
        let glintRect = CGRect(
            x: glintCenter.x - glintDiameter / 2,
            y: glintCenter.y - glintDiameter / 2,
            width: glintDiameter,
            height: glintDiameter
        )
        filledEllipse(ctx, rect: glintRect, color: RGB(0xFFFFFF))
    }
}

// MARK: - PNG output

private func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("png encode failed for \(url.path)\n".utf8))
        exit(2)
    }
    do {
        try data.write(to: url)
    } catch {
        FileHandle.standardError.write(Data("write failed for \(url.path): \(error)\n".utf8))
        exit(3)
    }
}

// MARK: - Entry

private func resolveAppIconDir() -> String {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let candidates = [
        "\(cwd)/Resources/Assets.xcassets/AppIcon.appiconset",
        "\(cwd)/../Resources/Assets.xcassets/AppIcon.appiconset",
    ]
    for c in candidates {
        if fileManager.fileExists(atPath: c) {
            return c
        }
    }
    FileHandle.standardError.write(Data("Could not find AppIcon.appiconset; tried:\n  \(candidates.joined(separator: "\n  "))\n".utf8))
    exit(1)
}

let appIconDir = resolveAppIconDir()

// Filenames -> pixel sizes. Matches Contents.json.
let outputs: [(filename: String, pixelSize: Int)] = [
    ("16.png",   16),
    ("32.png",   32),
    ("64.png",   64),
    ("128.png",  128),
    ("256.png",  256),
    ("512.png",  512),
    ("1024.png", 1024),
]

for (filename, pixelSize) in outputs {
    let image = drawIcon(size: pixelSize)
    let url = URL(fileURLWithPath: "\(appIconDir)/\(filename)")
    writePNG(image, to: url)
    print("rendered \(filename) (\(pixelSize)x\(pixelSize)) -> \(url.path)")
}
