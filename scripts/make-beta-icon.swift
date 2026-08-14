#!/usr/bin/env swift
//
// Generates a β-badged "beta" variant of the app icon into
// Sources/Marginal/App/Assets.xcassets/AppIconBeta.appiconset, mirroring every
// size/scale of the real AppIcon set. The side-by-side build selects this set via
// ASSETCATALOG_COMPILER_APPICON_NAME=AppIconBeta; the released build is untouched.
//
// Run:  swift scripts/make-beta-icon.swift
//
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Sources/Marginal/App/Assets.xcassets")
let srcSet = catalog.appendingPathComponent("AppIcon.appiconset")
let dstSet = catalog.appendingPathComponent("AppIconBeta.appiconset")

// Badge colour (warm orange reads as "beta").
let badgeColor = NSColor(calibratedRed: 0.98, green: 0.49, blue: 0.09, alpha: 1.0)

struct Entry: Codable {
    var filename: String?
    var idiom: String
    var scale: String
    var size: String
}
struct Info: Codable { var author: String; var version: Int }
struct Contents: Codable { var images: [Entry]; var info: Info }

let decoder = JSONDecoder()
let srcJSON = try Data(contentsOf: srcSet.appendingPathComponent("Contents.json"))
let src = try decoder.decode(Contents.self, from: srcJSON)

try? FileManager.default.removeItem(at: dstSet)
try FileManager.default.createDirectory(at: dstSet, withIntermediateDirectories: true)

/// Draws the source image and composites a β badge in the lower-right corner.
func badged(_ image: NSImage, pixels: Int) -> Data? {
    let w = pixels, h = pixels
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: w, height: h)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let full = NSRect(x: 0, y: 0, width: w, height: h)
    image.draw(in: full, from: .zero, operation: .copy, fraction: 1.0)

    // Badge geometry: a circle hugging the lower-right corner.
    let d = CGFloat(w) * 0.52                     // diameter
    let inset = CGFloat(w) * 0.03
    let circle = NSRect(x: CGFloat(w) - d - inset, y: inset, width: d, height: d)

    // Soft shadow for separation from the icon art.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = d * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -d * 0.02)
    shadow.set()

    badgeColor.setFill()
    NSBezierPath(ovalIn: circle).fill()

    // White ring.
    NSShadow().set() // clear shadow for the ring/glyph
    NSColor.white.withAlphaComponent(0.95).setStroke()
    let ring = NSBezierPath(ovalIn: circle.insetBy(dx: d * 0.045, dy: d * 0.045))
    ring.lineWidth = max(1, d * 0.035)
    ring.stroke()

    // β glyph, centred in the circle. Legible only on larger sizes; on tiny sizes it
    // reads as a coloured dot, which is still a clear "this is the other build" cue.
    let glyph = "β"
    let font = NSFont.systemFont(ofSize: d * 0.62, weight: .bold)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor.white, .paragraphStyle: para,
    ]
    let s = NSAttributedString(string: glyph, attributes: attrs)
    let textSize = s.size()
    let textRect = NSRect(x: circle.midX - textSize.width / 2,
                          y: circle.midY - textSize.height / 2,
                          width: textSize.width, height: textSize.height)
    s.draw(in: textRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func pixelDimension(size: String, scale: String) -> Int {
    let base = Int(size.split(separator: "x").first.map(String.init) ?? "0") ?? 0
    let mult = Int(scale.replacingOccurrences(of: "x", with: "")) ?? 1
    return base * mult
}

var out: [Entry] = []
for entry in src.images {
    guard let filename = entry.filename else { out.append(entry); continue }
    let px = pixelDimension(size: entry.size, scale: entry.scale)
    guard let img = NSImage(contentsOf: srcSet.appendingPathComponent(filename)) else {
        FileHandle.standardError.write(Data("skip: cannot read \(filename)\n".utf8)); continue
    }
    guard let data = badged(img, pixels: px) else {
        FileHandle.standardError.write(Data("skip: cannot render \(filename)\n".utf8)); continue
    }
    let newName = "beta-\(entry.size)-\(entry.scale).png"
    try data.write(to: dstSet.appendingPathComponent(newName))
    var e = entry; e.filename = newName; out.append(e)
    print("wrote \(newName) (\(px)px)")
}

let contents = Contents(images: out, info: Info(author: "marginal-make-beta-icon", version: 1))
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(contents).write(to: dstSet.appendingPathComponent("Contents.json"))
print("Done -> \(dstSet.path)")
