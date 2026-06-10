// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Focula",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FoculaCore", targets: ["FoculaCore"]),
        .executable(name: "Focula", targets: ["Focula"])
    ],
    targets: [
        .target(
            name: "FoculaCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Focula",
            dependencies: ["FoculaCore"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "FoculaCoreTests",
            dependencies: ["FoculaCore"]
        )
    ]
)
