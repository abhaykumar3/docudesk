import CoreGraphics

/// The DocuDesk "D" mark as vector geometry, traced from the brand artwork so it stays sharp at
/// every size (sidebar, setup screen, app icon). Coordinates use a 777 × 799 box, y pointing down.
public enum BrandMark {
    public static let size = CGSize(width: 777, height: 799)

    /// Brand colours in Display P3, as in the source artwork.
    public static let lightP3: (red: CGFloat, green: CGFloat, blue: CGFloat) = (89 / 255, 151 / 255, 247 / 255)
    public static let darkP3: (red: CGFloat, green: CGFloat, blue: CGFloat) = (50 / 255, 95 / 255, 172 / 255)

    /// Upper, lighter stroke of the D.
    public static func upperPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 514, y: 0))
        // Outer bowl: circle centred (514, 262), r 262, from the top round to the tip at x = 539.
        appendArc(to: path, center: CGPoint(x: 514, y: 262), rx: 262, ry: 262, from: -90, to: 84.5)
        // Inner cut: circle centred (259, 522), r 280, back up to the inner top edge.
        appendArc(to: path, center: CGPoint(x: 259, y: 522), rx: 280, ry: 280, from: 0, to: -90)
        path.addLine(to: CGPoint(x: 151, y: 242))
        path.closeSubpath()
        return transformed(path, into: rect)
    }

    /// Lower, darker stroke of the D.
    public static func lowerPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 181, y: 524))
        path.addLine(to: CGPoint(x: 539, y: 524))
        appendArc(to: path, center: CGPoint(x: 269, y: 524), rx: 270, ry: 275, from: 0, to: 90)
        path.addLine(to: CGPoint(x: 31, y: 799))
        path.closeSubpath()
        return transformed(path, into: rect)
    }

    /// Arc as fine line segments (angles in degrees, y down), which avoids platform differences
    /// in arc direction and supports the slightly elliptical lower bowl.
    private static func appendArc(to path: CGMutablePath, center: CGPoint, rx: CGFloat, ry: CGFloat, from start: CGFloat, to end: CGFloat) {
        let steps = 160
        for step in 0...steps {
            let degrees = start + (end - start) * CGFloat(step) / CGFloat(steps)
            let radians = degrees * .pi / 180
            path.addLine(to: CGPoint(x: center.x + rx * cos(radians), y: center.y + ry * sin(radians)))
        }
    }

    /// Fits the mark into `rect`, preserving its aspect ratio and centring it.
    private static func transformed(_ path: CGPath, into rect: CGRect) -> CGPath {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let offsetX = rect.minX + (rect.width - size.width * scale) / 2
        let offsetY = rect.minY + (rect.height - size.height * scale) / 2
        var transform = CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        return path.copy(using: &transform) ?? path
    }

    /// The app icon: the mark on a white rounded square, on the standard macOS icon grid
    /// (body inset 10% with a soft shadow). Draws into a y-down context of `side` × `side`.
    public static func drawAppIcon(in context: CGContext, side: CGFloat) {
        let inset = side * 0.098
        let body = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let radius = body.width * 0.225
        let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return }

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: side * 0.012), blur: side * 0.03,
                          color: CGColor(colorSpace: space, components: [0, 0, 0, 0.28]))
        context.addPath(shape)
        context.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let colors = [CGColor(colorSpace: space, components: [1, 1, 1, 1])!,
                      CGColor(colorSpace: space, components: [0.94, 0.955, 0.98, 1])!] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        }
        context.restoreGState()

        context.addPath(shape)
        context.setStrokeColor(CGColor(colorSpace: space, components: [0, 0, 0, 0.08])!)
        context.setLineWidth(max(1, side * 0.002))
        context.strokePath()

        let markHeight = body.height * 0.56
        let markRect = CGRect(x: body.midX - markHeight * size.width / size.height / 2, y: body.midY - markHeight / 2,
                              width: markHeight * size.width / size.height, height: markHeight)
        draw(in: context, rect: markRect)
    }

    /// Renders the app icon as a CGImage (Display P3, transparent outside the rounded square).
    public static func appIconImage(side: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        drawAppIcon(in: context, side: CGFloat(side))
        return context.makeImage()
    }

    /// Draws the mark into a y-down context (flip a Core Graphics context before calling).
    public static func draw(in context: CGContext, rect: CGRect) {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return }
        context.setFillColor(CGColor(colorSpace: space, components: [lightP3.red, lightP3.green, lightP3.blue, 1])!)
        context.addPath(upperPath(in: rect))
        context.fillPath()
        context.setFillColor(CGColor(colorSpace: space, components: [darkP3.red, darkP3.green, darkP3.blue, 1])!)
        context.addPath(lowerPath(in: rect))
        context.fillPath()
    }
}
