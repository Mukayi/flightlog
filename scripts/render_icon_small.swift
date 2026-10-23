import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: render_icon_small.swift MASTER SIZE OUTPUT\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let side = Int(CommandLine.arguments[2]),
    side == 16 || side == 32,
    let source = NSBitmapImageRep(
        data: try Data(contentsOf: inputURL)
    )
else {
    fputs("expected a readable master and size 16 or 32\n", stderr)
    exit(1)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let output = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: side * 4,
    bitsPerPixel: 32
) else {
    fputs("cannot allocate small icon bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: output) else {
    fputs("cannot create small icon graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
NSImage(contentsOf: inputURL)?.draw(
    in: NSRect(x: 0, y: 0, width: side, height: side),
    from: .zero,
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

func rgba(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int)
    -> (CGFloat, CGFloat, CGFloat, CGFloat)?
{
    guard let color = bitmap.colorAt(x: x, y: y)?
        .usingColorSpace(.deviceRGB)
    else {
        return nil
    }
    return (
        color.redComponent,
        color.greenComponent,
        color.blueComponent,
        color.alphaComponent
    )
}

for outputY in 0..<side {
    let sourceMinY = outputY * source.pixelsHigh / side
    let sourceMaxY = (outputY + 1) * source.pixelsHigh / side
    for outputX in 0..<side {
        let sourceMinX = outputX * source.pixelsWide / side
        let sourceMaxX = (outputX + 1) * source.pixelsWide / side
        let sampleCount = (sourceMaxX - sourceMinX) * (sourceMaxY - sourceMinY)
        var whiteCount = 0
        var cyanCount = 0
        var white = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0))
        var cyan = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0))

        for sourceY in sourceMinY..<sourceMaxY {
            for sourceX in sourceMinX..<sourceMaxX {
                guard let color = rgba(source, sourceX, sourceY), color.3 >= 0.5 else {
                    continue
                }
                let red = color.0
                let green = color.1
                let blue = color.2
                let spread = max(red, max(green, blue)) - min(red, min(green, blue))
                if min(red, green, blue) >= 0.68, spread <= 0.22 {
                    whiteCount += 1
                    white.red += red
                    white.green += green
                    white.blue += blue
                }
                if
                    green >= 0.55, blue >= 0.60,
                    green > red + 0.30, blue > red + 0.35
                {
                    cyanCount += 1
                    cyan.red += red
                    cyan.green += green
                    cyan.blue += blue
                }
            }
        }

        let whiteCoverage = CGFloat(whiteCount) / CGFloat(sampleCount)
        let cyanCoverage = CGFloat(cyanCount) / CGFloat(sampleCount)
        if whiteCoverage >= 0.08, whiteCoverage >= cyanCoverage {
            output.setColor(
                NSColor(
                    deviceRed: white.red / CGFloat(whiteCount),
                    green: white.green / CGFloat(whiteCount),
                    blue: white.blue / CGFloat(whiteCount),
                    alpha: 1
                ),
                atX: outputX,
                y: outputY
            )
        } else if cyanCoverage >= 0.04 {
            output.setColor(
                NSColor(
                    deviceRed: cyan.red / CGFloat(cyanCount),
                    green: cyan.green / CGFloat(cyanCount),
                    blue: cyan.blue / CGFloat(cyanCount),
                    alpha: 1
                ),
                atX: outputX,
                y: outputY
            )
        }
    }
}

guard let png = output.representation(using: .png, properties: [:]) else {
    fputs("cannot encode small icon PNG\n", stderr)
    exit(1)
}
do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("cannot write small icon PNG: \(error)\n", stderr)
    exit(1)
}
