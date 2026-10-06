// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plume",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
        // Mises à jour automatiques de l'app distribuée.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "PlumeKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Plume",
            dependencies: ["PlumeKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework est rangé dans Contents/Frameworks de l'app.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "PlumeKitTests",
            dependencies: ["PlumeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlumeTests",
            dependencies: ["Plume", "PlumeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
