#!/usr/bin/env swift
//
// make-icon.swift — render the Mika+ Panes app icon into an .iconset directory.
//
// Pure AppKit/CoreGraphics, no dependencies. The companion make-icon.sh runs this
// and then `iconutil` to produce AppIcon.icns.
//
// Mika+ family style: dark squircle with a teal radial glow, a mint line-art
// glyph with a soft glow, and a green "M+" pill badge. The Panes glyph is a
// window split into three vertical panes (sidebar | list | preview).

import AppKit

// MARK: - Palette

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let bgTop = rgb(18, 24, 32)        // dark navy
let bgBottom = rgb(9, 21, 19)      // dark green-black
let mint = rgb(134, 217, 192)      // seafoam stroke
let pillGreen = rgb(53, 197, 154)  // brighter green badge

// MARK: - Drawing

func drawIcon(_ S: CGFloat) {
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle background.
    let inset = S * 0.004
    let rect = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = S * 0.2237
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    bg.addClip()

    // Vertical base gradient.
    NSGradient(colors: [bgTop, bgBottom])?.draw(in: rect, angle: -90)

    // Teal radial glow behind the glyph, centred slightly above middle.
    let center = NSPoint(x: S * 0.5, y: S * 0.58)
    NSGradient(colors: [mint.withAlphaComponent(0.20), mint.withAlphaComponent(0.0)])?
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: S * 0.5, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Subtle inner top highlight for depth.
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.05), NSColor.white.withAlphaComponent(0.0)])?
        .draw(fromCenter: NSPoint(x: S * 0.5, y: S * 0.96), radius: 0,
              toCenter: NSPoint(x: S * 0.5, y: S * 0.96), radius: S * 0.5, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // MARK: Glyph — a window split into three vertical panes.
    NSGraphicsContext.saveGraphicsState()
    ctx.setShadow(offset: .zero, blur: S * 0.022,
                  color: mint.withAlphaComponent(0.55).cgColor)

    let gw = S * 0.50
    let gh = gw * 0.78
    let gx = (S - gw) / 2
    let gy = (S - gh) / 2 + S * 0.045
    let win = NSRect(x: gx, y: gy, width: gw, height: gh)

    let stroke = S * 0.022
    mint.setStroke()

    let frame = NSBezierPath(roundedRect: win, xRadius: gw * 0.10, yRadius: gw * 0.10)
    frame.lineWidth = stroke
    frame.lineJoinStyle = .round
    frame.stroke()

    // Two vertical dividers → sidebar | list | preview.
    let divInset = win.height * 0.10
    for fraction in [0.30, 0.64] {
        let x = win.minX + win.width * fraction
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: win.minY + divInset))
        line.line(to: NSPoint(x: x, y: win.maxY - divInset))
        line.lineWidth = stroke * 0.85
        line.lineCapStyle = .round
        line.stroke()
    }

    // Center dot — the Mika+ family motif (reads as a selected item).
    let dotR = S * 0.018
    let dotX = win.minX + win.width * 0.82
    let dot = NSBezierPath(ovalIn: NSRect(x: dotX - dotR, y: win.midY - dotR,
                                          width: dotR * 2, height: dotR * 2))
    mint.setFill()
    dot.fill()
    NSGraphicsContext.restoreGraphicsState()

    // MARK: "M+" pill badge, bottom-centre.
    let pw = S * 0.235
    let ph = S * 0.105
    let pill = NSRect(x: (S - pw) / 2, y: S * 0.072, width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.004), blur: S * 0.018,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    pillGreen.setFill()
    NSBezierPath(roundedRect: pill, xRadius: ph / 2, yRadius: ph / 2).fill()
    NSGraphicsContext.restoreGraphicsState()

    let text = "M+" as NSString
    let font = NSFont.systemFont(ofSize: ph * 0.56, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2),
              withAttributes: attrs)
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Emit iconset

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for v in variants {
    let data = renderPNG(pixels: v.px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(v.name).png")
    try! data.write(to: url)
}
print("wrote \(variants.count) pngs to \(outDir)")
