// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMonitorContracts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMonitorContracts", targets: ["CodexMonitorContracts"])
    ],
    targets: [
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "CodexMonitorContracts", dependencies: ["CSQLite"]),
        .testTarget(
            name: "CodexMonitorContractsTests",
            dependencies: ["CodexMonitorContracts", "CSQLite"],
            resources: [.process("Fixtures")]
        )
    ]
)
