// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMonitorContracts",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMonitorContracts", targets: ["CodexMonitorContracts"]),
        .executable(name: "CodexMonitorApp", targets: ["CodexMonitorApp"])
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
            dependencies: ["CodexMonitorContracts", "CSQLite"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CodexMonitorContractsTests",
            dependencies: ["CodexMonitorContracts", "CodexMonitorApp", "CSQLite"],
            resources: [.process("Fixtures")]
        )
    ]
)
