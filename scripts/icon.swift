// Make the app icon sizes from Resources/Icone.jpg (square, full-bleed image). The image
// is fitted into the macOS icon template: a continuous-corner square of 824 on a 1024
// grid, with a light shadow.
//   swift scripts/icon.swift <folder.iconset>
import AppKit
import SwiftUI

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let source = NSImage(contentsOfFile: "Resources/Icone.jpg") else { fatalError("Resources/Icone.jpg not found") }
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let unit = CGFloat(pixels) / 1024
    let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = RoundedRectangle(cornerRadius: 185.4 * unit, style: .continuous).path(in: body).cgPath
    let cg = context.cgContext
    // Subtle drop shadow, like system icons.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 22 * unit, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    cg.addPath(shape)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()
    cg.addPath(shape)
    cg.clip()
    source.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try render(points * scale).write(to: output.appendingPathComponent(name))
}
