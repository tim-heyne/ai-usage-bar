import Cocoa

// Rendert das Gauge-Ring-App-Icon in alle benötigten Größen (.iconset)
// Aufruf: swift make_icon.swift <ziel-iconset-ordner>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AIUsageBar.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderPNG(size: Int) -> Data {
    let S = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    let ctx = nsctx.cgContext

    // --- Squircle-Hintergrund (zentriert, mit Rand wie macOS-Icons) ---
    let inset = S * 0.085
    let side  = S - 2 * inset
    let rect  = CGRect(x: inset, y: inset, width: side, height: side)
    let corner = side * 0.2237
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).cgPath

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs,
        colors: [CGColor(red: 0.910, green: 0.537, blue: 0.408, alpha: 1),   // #E88968
                 CGColor(red: 0.784, green: 0.384, blue: 0.247, alpha: 1)] as CFArray, // #C8623F
        locations: [0, 1])!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: 0, y: rect.maxY),
        end:   CGPoint(x: 0, y: rect.minY),
        options: [])
    ctx.restoreGState()

    // --- Gauge-Ring ---
    let center = CGPoint(x: S / 2, y: S / 2)
    let radius = side * 0.30
    let lw = side * 0.105

    // Hintergrund-Ring (weiß, transparent)
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Vordergrund-Arc (weiß, ~75% gefüllt, oben beginnend, im Uhrzeigersinn)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addArc(center: center, radius: radius,
               startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * 0.75, clockwise: true)
    ctx.strokePath()

    // --- "%" in der Mitte ---
    let pct = "%"
    let font = NSFont.systemFont(ofSize: side * 0.22, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let tSize = pct.size(withAttributes: attrs)
    pct.draw(at: CGPoint(x: center.x - tSize.width / 2, y: center.y - tSize.height / 2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iconset-Dateinamen -> Pixelgröße
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in targets {
    let data = renderPNG(size: size)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("Iconset erstellt in \(outDir)")
