import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let outDir = root.appendingPathComponent("macos/Resources")
let svgURL = outDir.appendingPathComponent("marmot.svg")
let pngURL = outDir.appendingPathComponent("marmot.png")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func loadPNG(_ url: URL) -> NSBitmapImageRep {
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let src = NSBitmapImageRep(data: tiff) else {
        fatalError("cannot read \(url.path)")
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1024,
        pixelsHigh: 1024,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    src.draw(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func rasterizeSVG() -> NSBitmapImageRep {
    let tmp = FileManager.default.temporaryDirectory
    let ql = Process()
    ql.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    ql.arguments = ["-t", "-s", "1024", "-o", tmp.path, svgURL.path]
    ql.standardOutput = FileHandle.nullDevice
    ql.standardError = FileHandle.nullDevice
    try! ql.run()
    ql.waitUntilExit()
    let pngURL = tmp.appendingPathComponent("marmot.svg.png")
    guard let image = NSImage(contentsOf: pngURL),
          let tiff = image.tiffRepresentation,
          let src = NSBitmapImageRep(data: tiff) else {
        fatalError("qlmanage failed to rasterize SVG")
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1024,
        pixelsHigh: 1024,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    src.draw(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func tightCrop(_ source: NSBitmapImageRep, padding: CGFloat = 0.16) -> NSBitmapImageRep {
    let w = source.pixelsWide
    let h = source.pixelsHigh
    guard let src = source.bitmapData else { fatalError("cannot access bitmap pixels") }
    let srcRow = source.bytesPerRow
    let srcSpp = max(source.samplesPerPixel, 1)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let si = y * srcRow + x * srcSpp
            let r = Int(src[si])
            let g = srcSpp > 1 ? Int(src[si + 1]) : r
            let b = srcSpp > 2 ? Int(src[si + 2]) : r
            let a = srcSpp > 3 ? Int(src[si + 3]) : 255
            if r + g + b > 180, a > 20 {
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX > minX, maxY > minY else { return source }
    let pad = Int(ceil(CGFloat(max(maxX - minX + 1, maxY - minY + 1)) * padding))
    minX = max(0, minX - pad)
    minY = max(0, minY - pad)
    maxX = min(w - 1, maxX + pad)
    maxY = min(h - 1, maxY + pad)
    let cw = maxX - minX + 1
    let ch = maxY - minY + 1
    print("crop \(minX),\(minY) \(cw)x\(ch) from \(w)x\(h)")
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: cw,
        pixelsHigh: ch,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    guard let dst = out.bitmapData else { return source }
    let dstRow = out.bytesPerRow
    for y in 0..<ch {
        for x in 0..<cw {
            let si = (minY + y) * srcRow + (minX + x) * srcSpp
            let di = y * dstRow + x * 4
            dst[di] = src[si]
            dst[di + 1] = srcSpp > 1 ? src[si + 1] : src[si]
            dst[di + 2] = srcSpp > 2 ? src[si + 2] : src[si]
            dst[di + 3] = srcSpp > 3 ? src[si + 3] : 255
        }
    }
    return out
}

func paddedMark(_ source: NSBitmapImageRep, inset: CGFloat) -> NSBitmapImageRep {
    let tw = source.pixelsWide
    let th = source.pixelsHigh
    let pad = Int(ceil(CGFloat(max(tw, th)) * inset))
    let cw = tw + pad * 2
    let ch = th + pad * 2
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: cw,
        pixelsHigh: ch,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    guard let src = source.bitmapData, let dst = out.bitmapData else { return source }
    let srcRow = source.bytesPerRow
    let dstRow = out.bytesPerRow
    let srcSpp = max(source.samplesPerPixel, 1)
    for y in 0..<ch {
        for x in 0..<cw {
            let di = y * dstRow + x * 4
            let sx = x - pad
            let sy = y - pad
            if sx >= 0, sy >= 0, sx < tw, sy < th {
                let si = sy * srcRow + sx * srcSpp
                dst[di] = src[si]
                dst[di + 1] = srcSpp > 1 ? src[si + 1] : src[si]
                dst[di + 2] = srcSpp > 2 ? src[si + 2] : src[si]
                dst[di + 3] = srcSpp > 3 ? src[si + 3] : 255
            } else {
                dst[di] = 0
                dst[di + 1] = 0
                dst[di + 2] = 0
                dst[di + 3] = 0
            }
        }
    }
    print("pad \(tw)x\(th) + \(pad) -> \(cw)x\(ch)")
    return out
}

func scaled(_ source: NSBitmapImageRep, size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func punchTemplate(_ source: NSBitmapImageRep) -> NSBitmapImageRep {
    let w = source.pixelsWide
    let h = source.pixelsHigh
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w,
        pixelsHigh: h,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    guard let src = source.bitmapData, let dst = out.bitmapData else {
        fatalError("cannot access bitmap pixels")
    }
    let srcRow = source.bytesPerRow
    let dstRow = out.bytesPerRow
    let srcSpp = max(source.samplesPerPixel, 1)
    for y in 0..<h {
        for x in 0..<w {
            let si = y * srcRow + x * srcSpp
            let r = Int(src[si])
            let g = srcSpp > 1 ? Int(src[si + 1]) : r
            let b = srcSpp > 2 ? Int(src[si + 2]) : r
            let a = srcSpp > 3 ? Int(src[si + 3]) : 255
            let di = y * dstRow + x * 4
            if r + g + b > 180, a > 20 {
                dst[di] = 255
                dst[di + 1] = 255
                dst[di + 2] = 255
                dst[di + 3] = 255
            } else {
                dst[di] = 0
                dst[di + 1] = 0
                dst[di + 2] = 0
                dst[di + 3] = 0
            }
        }
    }
    return out
}

func roundCorners(_ source: NSBitmapImageRep, radius: CGFloat) -> NSBitmapImageRep {
    let w = source.pixelsWide
    let h = source.pixelsHigh
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w,
        pixelsHigh: h,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    guard let cg = source.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
    ) else { return source }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.draw(cg, in: rect)
    NSGraphicsContext.restoreGraphicsState()
    return out
}

func png(_ rep: NSBitmapImageRep) -> Data {
    rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ name: String) throws {
    let url = outDir.appendingPathComponent(name)
    try data.write(to: url)
    print("wrote \(url.path)")
}

let master: NSBitmapImageRep
if FileManager.default.fileExists(atPath: pngURL.path) {
    master = loadPNG(pngURL)
    print("using \(pngURL.path)")
} else if FileManager.default.fileExists(atPath: svgURL.path) {
    master = rasterizeSVG()
    print("using \(svgURL.path)")
} else {
    fatalError("missing marmot.png or marmot.svg")
}
let appIcon = roundCorners(master, radius: 1024 * 0.28)
try write(png(appIcon), "AppIcon-1024.png")
let mark = paddedMark(tightCrop(master, padding: 0), inset: 0.07)
try write(png(punchTemplate(scaled(mark, size: 44))), "StatusItem.png")
try write(png(punchTemplate(scaled(mark, size: 88))), "StatusItem@2x.png")

let publicSVG = root.appendingPathComponent("public/icon.svg")
if FileManager.default.fileExists(atPath: publicSVG.path) {
    try FileManager.default.removeItem(at: publicSVG)
}
try FileManager.default.copyItem(at: svgURL, to: publicSVG)
print("wrote \(publicSVG.path)")

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, px) in sizes {
    try png(scaled(appIcon, size: px)).write(to: iconset.appendingPathComponent(name))
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("wrote \(icns.path)")
