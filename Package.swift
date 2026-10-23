// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlightLog",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "FlightLog", targets: ["FlightLog"])
    ],
    targets: [
        .executableTarget(
            name: "FlightLog",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FlightLogTests",
            dependencies: ["FlightLog"]
        )
    ]
)
