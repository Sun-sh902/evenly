// Renders the 1024x1024 app icon: two overlapping rings on ink.
// Usage: swift ios/scripts/make-icon.swift ios/Evenly/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1])!
}

// Background with a soft diagonal glow.
ctx.setFillColor(rgb(0x16181D))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x1D3A2D), rgb(0x16181D)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 760, y: 820), startRadius: 0,
                       endCenter: CGPoint(x: 760, y: 820), endRadius: 700, options: [])

// Rings.
let r: CGFloat = 245
let line: CGFloat = 64
ctx.setLineWidth(line)
ctx.setStrokeColor(rgb(0xF5F3EE))
ctx.strokeEllipse(in: CGRect(x: 512 - 110 - r, y: 512 - r, width: r * 2, height: r * 2))
ctx.setStrokeColor(rgb(0x7FD1A8))
ctx.strokeEllipse(in: CGRect(x: 512 + 110 - r, y: 512 - r, width: r * 2, height: r * 2))

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: output)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(output)") }
print("wrote \(output)")
