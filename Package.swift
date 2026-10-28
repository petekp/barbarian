// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Barbarian",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Barbarian", targets: ["BarbarianApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
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
            dependencies: ["BarbarianCore", "BarbarianSystem", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "BarbarianCoreTests",
            dependencies: ["BarbarianCore"]
        ),
    ]
)
