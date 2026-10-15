// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "soluna-cal",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LunarCore",
            path: "Sources/LunarCore"
        ),
        .target(
            name: "SolunaUI",
            dependencies: ["LunarCore"],
            path: "Sources/SolunaUI"
        ),
        .executableTarget(
            name: "SolunaCal",
            dependencies: ["LunarCore", "SolunaUI"],
            path: "Sources/SolunaCal"
        ),
        .executableTarget(
            name: "RenderHarness",
            dependencies: ["LunarCore", "SolunaUI"],
            path: "Sources/RenderHarness"
        ),
        .testTarget(
            name: "LunarCoreTests",
            dependencies: ["LunarCore", "SolunaUI"],
            path: "Tests/LunarCoreTests"
        )
    ]
)
