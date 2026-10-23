import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: verify_icon_alpha.swift PNG\n", stderr)
    exit(64)
}

let path = CommandLine.arguments[1]
guard
    let data = FileManager.default.contents(atPath: path),
    let bitmap = NSBitmapImageRep(data: data)
else {
    fputs("cannot decode PNG: \(path)\n", stderr)
    exit(1)
}

guard bitmap.pixelsWide == bitmap.pixelsHigh, bitmap.hasAlpha else {
    fputs("expected a square PNG with alpha\n", stderr)
    exit(1)
}

func rgba(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
    guard
        let color = bitmap.colorAt(x: x, y: y)?
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

func alpha(_ x: Int, _ y: Int) -> Int {
    guard let color = rgba(x, y) else { return -1 }
    return Int((color.3 * 255).rounded())
}

let corners = [
    alpha(0, 0),
    alpha(bitmap.pixelsWide - 1, 0),
    alpha(0, bitmap.pixelsHigh - 1),
    alpha(bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1),
]
let center = alpha(bitmap.pixelsWide / 2, bitmap.pixelsHigh / 2)

guard corners.allSatisfy({ $0 == 0 }) else {
    fputs("icon corners are not fully transparent: \(corners)\n", stderr)
    exit(1)
}

if bitmap.pixelsWide == 1024 {
    guard center == 255 else {
        fputs("icon center is not opaque: \(center)\n", stderr)
        exit(1)
    }

    var minX = bitmap.pixelsWide
    var minY = bitmap.pixelsHigh
    var maxX = -1
    var maxY = -1
    var opaqueCount = 0
    var navyCount = 0
    var whiteCount = 0
    var cyanCount = 0
    var goldCount = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide where alpha(x, y) >= 16 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            guard let color = rgba(x, y), color.3 >= 0.5 else { continue }
            opaqueCount += 1
            let red = color.0
            let green = color.1
            let blue = color.2
            let spread = max(red, max(green, blue)) - min(red, min(green, blue))
            if blue > red + 0.07, blue > green + 0.03, (red + green + blue) / 3 < 0.45 {
                navyCount += 1
            }
            if min(red, green, blue) >= 0.65, spread <= 0.22 {
                whiteCount += 1
            }
            if green >= 0.50, blue >= 0.60, green > red + 0.25, blue > red + 0.30 {
                cyanCount += 1
            }
            if red >= 0.55, green >= 0.30, red > blue + 0.20, green > blue + 0.08 {
                goldCount += 1
            }
        }
    }
    let margins = [
        minX,
        minY,
        bitmap.pixelsWide - 1 - maxX,
        bitmap.pixelsHigh - 1 - maxY,
    ]
    guard margins.allSatisfy({ $0 >= 32 && $0 <= 200 }) else {
        fputs("icon subject is outside safe bounds: margins=\(margins)\n", stderr)
        exit(1)
    }
    guard
        opaqueCount >= 550_000,
        navyCount >= 450_000,
        whiteCount >= 20_000,
        cyanCount >= 8_000,
        goldCount >= 2_500
    else {
        fputs(
            "master semantic colors were removed or reduced: " +
            "opaque=\(opaqueCount) navy=\(navyCount) white=\(whiteCount) " +
            "cyan=\(cyanCount) gold=\(goldCount)\n",
            stderr
        )
        exit(1)
    }
    print(
        "corners=\(corners.map(String.init).joined(separator: ",")) " +
        "center=\(center) safeBounds=pass margins=\(margins) subjects=pass " +
        "opaque=\(opaqueCount) navy=\(navyCount) white=\(whiteCount) " +
        "cyan=\(cyanCount) gold=\(goldCount)"
    )
    exit(0)
}

guard bitmap.pixelsWide == 16 || bitmap.pixelsWide == 32 else {
    fputs("palette verification only supports 16, 32, or 1024 pixels\n", stderr)
    exit(1)
}

func linear(_ component: CGFloat) -> CGFloat {
    component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
}

func luminance(_ color: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CGFloat {
    0.2126 * linear(color.0) +
        0.7152 * linear(color.1) +
        0.0722 * linear(color.2)
}

var opaqueCount = 0
var navyCount = 0
var whiteCount = 0
var cyanCount = 0
var whiteCoreCount = 0
var cyanCoreCount = 0
var navyLuminance: CGFloat = 0
var whiteLuminance: CGFloat = 0
var cyanLuminance: CGFloat = 0
var whiteMask = [Bool](repeating: false, count: bitmap.pixelsWide * bitmap.pixelsHigh)
var cyanMask = [Bool](repeating: false, count: bitmap.pixelsWide * bitmap.pixelsHigh)

for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        guard let color = rgba(x, y), color.3 >= 0.25 else { continue }
        let red = color.0
        let green = color.1
        let blue = color.2
        let spread = max(red, max(green, blue)) - min(red, min(green, blue))
        if color.3 >= 0.5 {
            opaqueCount += 1
            if blue > red + 0.07, blue > green + 0.03, luminance(color) < 0.28 {
                navyCount += 1
                navyLuminance += luminance(color)
            }
            if min(red, green, blue) >= 0.65, spread <= 0.22 {
                whiteCoreCount += 1
                whiteLuminance += luminance(color)
            }
            if green >= 0.50, blue >= 0.60, green > red + 0.25, blue > red + 0.30 {
                cyanCoreCount += 1
                cyanLuminance += luminance(color)
            }
        }
        if min(red, green, blue) >= 0.45, spread <= 0.30 {
            whiteCount += 1
            whiteMask[y * bitmap.pixelsWide + x] = true
        }
        if green >= 0.30, blue >= 0.40, green > red + 0.20, blue > red + 0.25 {
            cyanCount += 1
            cyanMask[y * bitmap.pixelsWide + x] = true
        }
    }
}

let scale = bitmap.pixelsWide / 16
let minimums = (
    opaque: 100 * scale * scale,
    navy: 64 * scale * scale,
    white: 8 * scale * scale,
    cyan: bitmap.pixelsWide == 16 ? 8 : 24
)
guard
    opaqueCount >= minimums.opaque,
    navyCount >= minimums.navy,
    whiteCount >= minimums.white,
    cyanCount >= minimums.cyan
else {
    fputs(
        "small icon palette pixel counts are too low: " +
        "opaque=\(opaqueCount) navy=\(navyCount) white=\(whiteCount) cyan=\(cyanCount)\n",
        stderr
    )
    exit(1)
}

guard whiteCoreCount >= 2 * scale, cyanCoreCount >= 2 * scale else {
    fputs(
        "small icon lacks solid white or cyan core pixels: " +
        "whiteCore=\(whiteCoreCount) cyanCore=\(cyanCoreCount)\n",
        stderr
    )
    exit(1)
}

let averageNavy = navyLuminance / CGFloat(navyCount)
let averageWhite = whiteLuminance / CGFloat(whiteCoreCount)
let averageCyan = cyanLuminance / CGFloat(cyanCoreCount)
let whiteContrast = (averageWhite + 0.05) / (averageNavy + 0.05)
let cyanContrast = (averageCyan + 0.05) / (averageNavy + 0.05)
guard whiteContrast >= 4.5, cyanContrast >= 3.0 else {
    fputs(
        "small icon contrast is too low: " +
        "white=\(whiteContrast) cyan=\(cyanContrast)\n",
        stderr
    )
    exit(1)
}

struct Component {
    var count: Int
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

func largestComponent(in mask: [Bool], side: Int) -> Component? {
    var visited = [Bool](repeating: false, count: mask.count)
    var largest: Component?
    let neighbors = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0),            (1, 0),
        (-1, 1),  (0, 1),   (1, 1),
    ]

    for start in mask.indices where mask[start] && !visited[start] {
        var queue = [start]
        visited[start] = true
        var cursor = 0
        var component = Component(
            count: 0,
            minX: side,
            minY: side,
            maxX: -1,
            maxY: -1
        )
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % side
            let y = index / side
            component.count += 1
            component.minX = min(component.minX, x)
            component.minY = min(component.minY, y)
            component.maxX = max(component.maxX, x)
            component.maxY = max(component.maxY, y)
            for (dx, dy) in neighbors {
                let nextX = x + dx
                let nextY = y + dy
                guard
                    nextX >= 0, nextX < side,
                    nextY >= 0, nextY < side
                else { continue }
                let next = nextY * side + nextX
                if mask[next], !visited[next] {
                    visited[next] = true
                    queue.append(next)
                }
            }
        }
        if largest == nil || component.count > largest!.count {
            largest = component
        }
    }
    return largest
}

guard
    let plane = largestComponent(in: whiteMask, side: bitmap.pixelsWide),
    let route = largestComponent(in: cyanMask, side: bitmap.pixelsWide)
else {
    fputs("small icon is missing plane or route components\n", stderr)
    exit(1)
}

let minimumPlaneSpan = 4 * scale
guard
    plane.count >= minimums.white,
    plane.width >= minimumPlaneSpan,
    plane.height >= minimumPlaneSpan
else {
    fputs("white plane is not a substantial connected shape: \(plane)\n", stderr)
    exit(1)
}

let side = bitmap.pixelsWide
guard
    route.count >= minimums.cyan,
    route.width * 100 >= side * 30,
    route.height * 100 >= side * 25,
    route.minX * 100 <= side * 40,
    route.maxX * 100 >= side * 50
else {
    fputs("cyan route does not span the icon substantially: \(route)\n", stderr)
    exit(1)
}

func axisDistance(_ firstMin: Int, _ firstMax: Int, _ secondMin: Int, _ secondMax: Int) -> Int {
    if firstMax < secondMin { return secondMin - firstMax }
    if secondMax < firstMin { return firstMin - secondMax }
    return 0
}

let componentDistance = max(
    axisDistance(route.minX, route.maxX, plane.minX, plane.maxX),
    axisDistance(route.minY, route.maxY, plane.minY, plane.maxY)
)
guard componentDistance <= 2 * scale else {
    fputs("cyan route does not approach the white plane: distance=\(componentDistance)\n", stderr)
    exit(1)
}

print(
    "corners=\(corners.map(String.init).joined(separator: ",")) " +
    "palette=pass opaque=\(opaqueCount) navy=\(navyCount) " +
    "white=\(whiteCount) cyan=\(cyanCount) " +
    "whiteCore=\(whiteCoreCount) cyanCore=\(cyanCoreCount) contrast=pass " +
    "whiteRatio=\(String(format: "%.2f", Double(whiteContrast))) " +
    "cyanRatio=\(String(format: "%.2f", Double(cyanContrast))) " +
    "shape=pass " +
    "planeComponent=\(plane.count):\(plane.width)x\(plane.height) " +
    "routeComponent=\(route.count):\(route.width)x\(route.height) " +
    "componentDistance=\(componentDistance)"
)
