import AppKit
import DocuDeskCore

// Brand asset tool.
//   swift run BrandAssets icon <output.icns>          builds the app icon from BrandMark
//   swift run BrandAssets check <artwork.png> <out>   overlays the vector mark on the source artwork

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BrandAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

func buildIcon(output: URL) throws {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            guard let image = BrandMark.appIconImage(side: points * scale) else { continue }
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try writePNG(image, to: iconset.appendingPathComponent(name))
        }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "BrandAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
    print("Wrote \(output.path)")
}

func check(artwork: URL, output: URL) throws {
    let original = NSBitmapImageRep(data: try Data(contentsOf: artwork))!
    let width = original.pixelsWide, height = original.pixelsHigh
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    // Bounding box of the mark in the supplied 1726 × 1716 artwork.
    BrandMark.draw(in: context, rect: CGRect(x: 476, y: 458, width: 777, height: 799))
    let drawn = NSBitmapImageRep(cgImage: context.makeImage()!)
    var mismatched = 0
    var total = 0
    for y in stride(from: 400, to: min(1300, height), by: 2) {
        for x in stride(from: 420, to: min(1300, width), by: 2) {
            var a = [Int](repeating: 0, count: 4)
            var b = [Int](repeating: 0, count: 4)
            original.getPixel(&a, atX: x, y: y)
            drawn.getPixel(&b, atX: x, y: y)
            func region(_ p: [Int]) -> Int { p[2] > 230 && p[0] > 230 ? 0 : (p[1] > 125 ? 1 : 2) }
            total += 1
            if region(a) != region(b) { mismatched += 1 }
        }
    }
    print(String(format: "mismatch %.2f%%", Double(mismatched) * 100 / Double(max(total, 1))))
    try writePNG(context.makeImage()!, to: output)
}

let arguments = CommandLine.arguments
do {
    switch arguments.count > 1 ? arguments[1] : "" {
    case "icon" where arguments.count == 3:
        try buildIcon(output: URL(fileURLWithPath: arguments[2]))
    case "check" where arguments.count == 4:
        try check(artwork: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]))
    default:
        print("usage: BrandAssets icon <output.icns> | check <artwork.png> <output.png>")
        exit(2)
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
