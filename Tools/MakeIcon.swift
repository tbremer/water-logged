// Generates a 1024x1024 opaque app icon (white water drop on a blue gradient).
// Usage: swift Tools/MakeIcon.swift <output.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let w = CGFloat(size)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("Could not create context") }

// Work in top-left coordinates (y grows downward).
ctx.translateBy(x: 0, y: w)
ctx.scaleBy(x: 1, y: -1)

// Background gradient: lighter at top, deeper blue at bottom.
let bg = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.16, green: 0.62, blue: 0.97, alpha: 1),
        CGColor(red: 0.02, green: 0.27, blue: 0.62, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: w), options: [])

// Water drop: pointed top, round bottom (original proportions).
let cx = w / 2
let topY = w * 0.16
let bulgeR = w * 0.265
let centerY = w * 0.62
let drop = CGMutablePath()
drop.move(to: CGPoint(x: cx, y: topY))
drop.addCurve(
    to: CGPoint(x: cx + bulgeR, y: centerY),
    control1: CGPoint(x: cx + bulgeR * 0.55, y: topY + bulgeR * 0.9),
    control2: CGPoint(x: cx + bulgeR, y: centerY - bulgeR * 0.85)
)
drop.addArc(center: CGPoint(x: cx, y: centerY), radius: bulgeR,
            startAngle: 0, endAngle: .pi, clockwise: false)
drop.addCurve(
    to: CGPoint(x: cx, y: topY),
    control1: CGPoint(x: cx - bulgeR, y: centerY - bulgeR * 0.85),
    control2: CGPoint(x: cx - bulgeR * 0.55, y: topY + bulgeR * 0.9)
)
drop.closeSubpath()

// Scale the whole drop to 85% (15% smaller) about the icon center for padding,
// preserving the original teardrop proportions.
let iconCenter = CGPoint(x: cx, y: w / 2)
ctx.saveGState()
ctx.translateBy(x: iconCenter.x, y: iconCenter.y)
ctx.scaleBy(x: 0.85, y: 0.85)
ctx.translateBy(x: -iconCenter.x, y: -iconCenter.y)

ctx.addPath(drop)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
ctx.fillPath()

// Small highlight on the drop for a touch of depth.
ctx.addEllipse(in: CGRect(x: cx - bulgeR * 0.45, y: centerY - bulgeR * 0.35,
                          width: bulgeR * 0.45, height: bulgeR * 0.6))
ctx.setFillColor(CGColor(red: 0.16, green: 0.62, blue: 0.97, alpha: 0.18))
ctx.fillPath()

ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("Could not render image") }

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fatalError("Could not create destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write PNG") }
print("Wrote \(outPath)")
