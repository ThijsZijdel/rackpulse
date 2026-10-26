// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Rackpulse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../packages/HetznerKit"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Rackpulse",
            dependencies: [
                .product(name: "HetznerKit", package: "HetznerKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Rackpulse",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
