// Renders the "wallet" app icon (default, dark, tinted) at 1024x1024.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let u = S / 100 // design grid is 100x100

/// Rounded rectangle with continuous-curvature corners: each corner is a quarter
/// superellipse spanning ~1.53r along the edges, like Apple's `.continuous` style.
func continuousRect(_ r: CGRect, radius: CGFloat) -> CGPath {
    let e = min(radius * 1.528, r.width / 2, r.height / 2)
    let n: CGFloat = 3.3
    let p = CGMutablePath()
    // corners: (centre of superellipse, start angle) going clockwise in y-down space
    let corners: [(CGPoint, CGFloat)] = [
        (CGPoint(x: r.maxX - e, y: r.minY + e), -.pi / 2), // top-right
        (CGPoint(x: r.maxX - e, y: r.maxY - e), 0),        // bottom-right
        (CGPoint(x: r.minX + e, y: r.maxY - e), .pi / 2),  // bottom-left
        (CGPoint(x: r.minX + e, y: r.minY + e), .pi),      // top-left
    ]
    var first = true
    for (c, a0) in corners {
        for i in 0...24 {
            let t = a0 + CGFloat(i) / 24 * (.pi / 2)
            let ct = cos(t), st = sin(t)
            let x = c.x + e * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
            let y = c.y + e * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
            if first { p.move(to: CGPoint(x: x, y: y)); first = false } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
    }
    p.closeSubpath()
    return p
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

struct Look { let background: CGColor?; let back, middle, front, stripe: CGColor }

func render(_ look: Look, to file: String) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = look.background == nil ? .premultipliedLast : .noneSkipLast
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: alpha.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1) // y-down like the design grid
    if let bg = look.background { ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S)) }
    func card(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ c: CGColor) {
        ctx.addPath(continuousRect(CGRect(x: x * u, y: y * u, width: w * u, height: h * u), radius: r * u))
        ctx.setFillColor(c); ctx.fillPath()
    }
    // Three cards stacked back to front, optically centred (content spans y 19...81).
    card(24, 19, 52, 34, 9, look.back)
    card(20, 31, 60, 38, 10, look.middle)
    card(16, 44, 68, 37, 11, look.front)
    // The mint stripe on the front card: the one accent, like a balance on a card.
    card(25, 67, 22, 5, 2.5, look.stripe)
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: file) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let out = CommandLine.arguments[1]
// Default: ink cards on the app's warm paper, matching the home screen.
render(Look(background: rgb(0xF3F0E8), back: rgb(0x434951), middle: rgb(0x2B3038), front: rgb(0x16181D), stripe: rgb(0x7FD1A8)),
       to: out + "/AppIcon.png")
// Dark: transparent so the system's dark backdrop shows; cards lighten toward the
// front so the stack still reads against near-black.
render(Look(background: nil, back: rgb(0x33383F), middle: rgb(0x454B54), front: rgb(0x5B626C), stripe: rgb(0x8EDBB3)),
       to: out + "/AppIcon-Dark.png")
// Tinted: grayscale on transparent; the system tints by brightness, so the stripe is brightest.
render(Look(background: nil, back: rgb(0x6E6E6E), middle: rgb(0x9A9A9A), front: rgb(0xC8C8C8), stripe: rgb(0xFFFFFF)),
       to: out + "/AppIcon-Tinted.png")
print("ok")
