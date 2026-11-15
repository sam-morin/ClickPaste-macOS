// Draws the ClickPaste app icon and writes AppIcon.icns next to this script.
//   swift Icon/make-icon.swift
import AppKit

func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    // Coordinates are on a 1024 grid, scaled to the requested size. Origin is bottom-left.
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    let cs = CGColorSpaceCreateDeviceRGB()
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a) }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

    // Background tile, macOS icon grid: 824pt body inset 100pt, with a soft drop shadow.
    let tile = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(tile); ctx.setFillColor(rgb(40, 90, 220)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(84, 150, 255), rgb(46, 84, 214)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Clipboard board.
    let board = CGRect(x: 262, y: 190, width: 440, height: 560)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(10, 30, 90, 0.35))
    ctx.addPath(rounded(board, 56)); ctx.setFillColor(rgb(255, 255, 255)); ctx.fillPath()
    ctx.restoreGState()

    // Clip at the top of the board.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: rgb(10, 30, 90, 0.3))
    ctx.addPath(rounded(CGRect(x: 382, y: 700, width: 200, height: 96), 30)); ctx.setFillColor(rgb(36, 52, 92)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(rounded(CGRect(x: 437, y: 762, width: 90, height: 22), 11)); ctx.setFillColor(rgb(84, 150, 255)); ctx.fillPath()

    // Text lines, the last one partly "typed" with a caret.
    ctx.setFillColor(rgb(196, 210, 236))
    for (y, w) in [(600, 320), (530, 280), (460, 320)] as [(CGFloat, CGFloat)] {
        ctx.addPath(rounded(CGRect(x: 322, y: y, width: w, height: 34), 17)); ctx.fillPath()
    }
    ctx.setFillColor(rgb(46, 84, 214))
    ctx.addPath(rounded(CGRect(x: 322, y: 390, width: 150, height: 34), 17)); ctx.fillPath()
    ctx.addPath(rounded(CGRect(x: 490, y: 372, width: 14, height: 70), 7)); ctx.fillPath()

    // Mouse pointer clicking onto the board.
    let tip = CGPoint(x: 572, y: 356)
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, -150), (36, -116), (62, -176), (90, -164), (64, -105), (112, -105)]
    let arrow = CGMutablePath()
    arrow.move(to: tip)
    for p in pts.dropFirst() { arrow.addLine(to: CGPoint(x: tip.x + p.0, y: tip.y + p.1)) }
    arrow.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 4, height: -10), blur: 16, color: rgb(0, 0, 0, 0.4))
    ctx.addPath(arrow); ctx.setFillColor(rgb(20, 24, 36)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(arrow); ctx.setStrokeColor(rgb(255, 255, 255)); ctx.setLineWidth(14); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.addPath(arrow); ctx.setFillColor(rgb(20, 24, 36)); ctx.fillPath()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    drawIcon(ctx, CGFloat(px))
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! png(pt).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! png(pt * 2).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
try! png(1024).write(to: dir.appendingPathComponent("preview.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Icon/AppIcon.icns" : "iconutil failed")
