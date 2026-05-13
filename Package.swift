// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatchMyBack",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WatchMyBackCore", targets: ["WatchMyBackCore"]),
        .executable(name: "WatchMyBack", targets: ["WatchMyBack"])
    ],
    targets: [
        .target(
            name: "WatchMyBackCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "WatchMyBack",
            dependencies: ["WatchMyBackCore"]
        ),
        .testTarget(
            name: "WatchMyBackCoreTests",
            dependencies: ["WatchMyBackCore"]
        )
    ]
)
