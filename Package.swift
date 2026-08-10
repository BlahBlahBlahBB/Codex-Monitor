// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMonitorContracts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMonitorContracts", targets: ["CodexMonitorContracts"])
    ],
    targets: [
        .target(name: "CodexMonitorContracts"),
        .testTarget(
            name: "CodexMonitorContractsTests",
            dependencies: ["CodexMonitorContracts"],
            resources: [.process("Fixtures")]
        )
    ]
)
