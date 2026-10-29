// Renders the app icon into an .icns file.
// Usage: swift Scripts/make-icon.swift <output.icns>
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Draw in a 1024 coordinate space.
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // Background: standard macOS icon grid (824pt body, 100pt margin).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    bodyPath.fill()
    ctx.restoreGState()
    bodyPath.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.18, green: 0.20, blue: 0.62, alpha: 1)])!
        .draw(in: body, angle: -90)

    // Keycap
    let cap = CGRect(x: 262, y: 250, width: 500, height: 500)
    let capPath = NSBezierPath(roundedRect: cap, xRadius: 96, yRadius: 96)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(white: 0.86, alpha: 1).setFill()
    capPath.fill()
    ctx.restoreGState()
    let top = NSBezierPath(roundedRect: cap.insetBy(dx: 26, dy: 26).offsetBy(dx: 0, dy: 14), xRadius: 74, yRadius: 74)
    NSGradient(colors: [NSColor.white, NSColor(white: 0.93, alpha: 1)])!.draw(in: top, angle: -90)

    // Glyphs: a large 中 with a small A, the two sides of an input source.
    let ink = NSColor(srgbRed: 0.20, green: 0.22, blue: 0.62, alpha: 1)
    func draw(_ text: String, font: NSFont, center: CGPoint, color: NSColor) {
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let b = str.size()
        str.draw(at: CGPoint(x: center.x - b.width / 2, y: center.y - b.height / 2))
    }
    draw("中", font: .systemFont(ofSize: 250, weight: .semibold), center: CGPoint(x: 545, y: 470), color: ink)
    draw("A", font: .systemFont(ofSize: 120, weight: .bold), center: CGPoint(x: 370, y: 625), color: ink.withAlphaComponent(0.55))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
