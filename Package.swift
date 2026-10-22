// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMonitorContracts",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMonitorContracts", targets: ["CodexMonitorContracts"]),
        .executable(name: "CodexMonitorApp", targets: ["CodexMonitorApp"]),
        .executable(name: "ApprovalObserver", targets: ["ApprovalObserver"])
    ],
    dependencies: [
        // Pin the updater framework so signing, appcast generation, and
        // runtime behavior are reviewed together. Do not silently float to a
        // different Sparkle release in a production update channel.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "CodexMonitorContracts", dependencies: ["CSQLite"]),
        .executableTarget(
            name: "CodexMonitorApp",
            dependencies: [
                "CodexMonitorContracts",
                "CSQLite",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "ApprovalObserver", dependencies: ["CodexMonitorContracts"]),
        .testTarget(
            name: "CodexMonitorContractsTests",
            dependencies: ["CodexMonitorContracts", "CodexMonitorApp", "CSQLite"],
            resources: [.process("Fixtures")]
        )
    ]
)
