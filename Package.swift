// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Barbarian",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Barbarian", targets: ["BarbarianApp"]),
    ],
    targets: [
        .target(name: "BarbarianCore"),
        .target(
            name: "BarbarianSystem",
            dependencies: ["BarbarianCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "BarbarianApp",
            dependencies: ["BarbarianCore", "BarbarianSystem"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "BarbarianCoreTests",
            dependencies: ["BarbarianCore"]
        ),
    ]
)
