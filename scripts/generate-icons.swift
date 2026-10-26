import AppKit
import Foundation

// Original vector artwork: a cream cat silhouette carrying the Wubi character.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent("Soumao.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ size: Int, menu: Bool = false) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    if menu {
        NSColor.black.setFill()
        let outline = NSBezierPath(roundedRect: NSRect(x: 150, y: 120, width: 724, height: 680), xRadius: 170, yRadius: 170)
        outline.move(to: NSPoint(x: 170, y: 640)); outline.line(to: NSPoint(x: 400, y: 780)); outline.line(to: NSPoint(x: 170, y: 950)); outline.close()
        outline.move(to: NSPoint(x: 854, y: 640)); outline.line(to: NSPoint(x: 854, y: 950)); outline.line(to: NSPoint(x: 624, y: 780)); outline.close()
        outline.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 610, weight: .heavy), .foregroundColor: NSColor.white]
        let word = "五" as NSString
        let textSize = word.size(withAttributes: attrs)
        word.draw(at: NSPoint(x: (1024 - textSize.width) / 2, y: 130), withAttributes: attrs)
    } else {
        let background = NSBezierPath(roundedRect: NSRect(x: 36, y: 36, width: 952, height: 952), xRadius: 218, yRadius: 218)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.06, green: 0.40, blue: 0.43, alpha: 1), ending: NSColor(calibratedRed: 0.03, green: 0.23, blue: 0.30, alpha: 1))!
        gradient.draw(in: background, angle: 270)
        let cream = NSColor(calibratedRed: 1, green: 0.94, blue: 0.81, alpha: 1)
        cream.setFill()
        let cat = NSBezierPath(roundedRect: NSRect(x: 190, y: 190, width: 644, height: 568), xRadius: 208, yRadius: 208)
        cat.move(to: NSPoint(x: 210, y: 600)); cat.line(to: NSPoint(x: 441, y: 729)); cat.line(to: NSPoint(x: 194, y: 868)); cat.close()
        cat.move(to: NSPoint(x: 814, y: 600)); cat.line(to: NSPoint(x: 830, y: 868)); cat.line(to: NSPoint(x: 583, y: 729)); cat.close()
        cat.fill()
        NSColor(calibratedRed: 0.91, green: 0.52, blue: 0.29, alpha: 1).setFill()
        for x in [265.0, 694.0] {
            let ear = NSBezierPath()
            ear.move(to: NSPoint(x: x, y: 708)); ear.line(to: NSPoint(x: x - 8, y: 780)); ear.line(to: NSPoint(x: x + 82, y: 731)); ear.close(); ear.fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 442, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.035, green: 0.29, blue: 0.34, alpha: 1)]
        let word = "五" as NSString
        let textSize = word.size(withAttributes: attrs)
        word.draw(at: NSPoint(x: (1024 - textSize.width) / 2, y: 220), withAttributes: attrs)
        cream.setStroke()
        for y in [380.0, 454.0] {
            let whisker = NSBezierPath(); whisker.lineWidth = 20; whisker.lineCapStyle = .round
            whisker.move(to: NSPoint(x: 111, y: y)); whisker.line(to: NSPoint(x: 220, y: y + 20))
            whisker.move(to: NSPoint(x: 804, y: y + 20)); whisker.line(to: NSPoint(x: 913, y: y)); whisker.stroke()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(size * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let menu = NSImage(size: NSSize(width: 18, height: 18))
for pixels in [18, 36] {
    let rep = render(pixels, menu: true)
    rep.size = NSSize(width: 18, height: 18)
    menu.addRepresentation(rep)
}
try menu.tiffRepresentation!.write(to: root.appendingPathComponent("SoumaoMenu.tiff"))

// ICNS supports PNG payloads directly; write it deterministically without iconutil's
// host graphics-service dependency, so this build also works in a restricted shell.
func bigEndian32(_ value: Int) -> Data {
    var word = UInt32(value).bigEndian
    return withUnsafeBytes(of: &word) { Data($0) }
}
let entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
               ("ic08", 256), ("ic09", 512), ("ic10", 1024),
               ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
var chunks = Data()
for (kind, pixels) in entries {
    let png = render(pixels).representation(using: .png, properties: [:])!
    chunks.append(kind.data(using: .ascii)!)
    chunks.append(bigEndian32(png.count + 8))
    chunks.append(png)
}
var icns = "icns".data(using: .ascii)!
icns.append(bigEndian32(chunks.count + 8))
icns.append(chunks)
try icns.write(to: root.appendingPathComponent("Soumao.icns"))
