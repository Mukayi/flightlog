import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render_icon_master.swift INPUT OUTPUT\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: inputURL) else {
    fputs("cannot load icon source: \(inputURL.path)\n", stderr)
    exit(1)
}

let side = 1024
guard let bitmap = NSBitmapImageRep(
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
    fputs("cannot allocate icon bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("cannot create icon graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

// Preserve the generated composition and add only a small mechanical safety margin.
let padding: CGFloat = 20
source.draw(
    in: NSRect(
        x: padding,
        y: padding,
        width: CGFloat(side) - 2 * padding,
        height: CGFloat(side) - 2 * padding
    ),
    from: .zero,
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)
graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pixels = bitmap.bitmapData else {
    fputs("cannot access icon pixels\n", stderr)
    exit(1)
}

let bytesPerRow = bitmap.bytesPerRow
var visited = [Bool](repeating: false, count: side * side)
var queue = [(Int, Int)]()
queue.reserveCapacity(side * 4)

func offset(_ x: Int, _ y: Int) -> Int {
    y * bytesPerRow + x * 4
}

func isExteriorCandidate(_ x: Int, _ y: Int) -> Bool {
    let index = offset(x, y)
    let alpha = pixels[index + 3]
    let red = pixels[index]
    let green = pixels[index + 1]
    let blue = pixels[index + 2]
    let brightest = max(red, max(green, blue))
    let darkest = min(red, min(green, blue))

    // GenerateImage exported V2 over a baked light neutral checkerboard. Flood
    // only edge-connected neutral pixels, so the disconnected white plane and
    // gold stamp remain untouched while no checkerboard is synthesized.
    let neutralSpread = Int(brightest) - Int(darkest)
    let generatedBackdrop = brightest >= 72 && neutralSpread <= 42
    return alpha == 0 || generatedBackdrop
}

func enqueue(_ x: Int, _ y: Int) {
    let index = y * side + x
    guard !visited[index], isExteriorCandidate(x, y) else { return }
    visited[index] = true
    queue.append((x, y))
}

for coordinate in 0..<side {
    enqueue(coordinate, 0)
    enqueue(coordinate, side - 1)
    enqueue(0, coordinate)
    enqueue(side - 1, coordinate)
}

var cursor = 0
while cursor < queue.count {
    let (x, y) = queue[cursor]
    cursor += 1
    let pixelOffset = offset(x, y)
    pixels[pixelOffset] = 0
    pixels[pixelOffset + 1] = 0
    pixels[pixelOffset + 2] = 0
    pixels[pixelOffset + 3] = 0

    if x > 0 { enqueue(x - 1, y) }
    if x + 1 < side { enqueue(x + 1, y) }
    if y > 0 { enqueue(x, y - 1) }
    if y + 1 < side { enqueue(x, y + 1) }
}

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("cannot encode icon PNG\n", stderr)
    exit(1)
}
do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("cannot write icon PNG: \(error)\n", stderr)
    exit(1)
}
