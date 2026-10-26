// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HetznerKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "HetznerKit", targets: ["HetznerKit"])
    ],
    targets: [
        .target(name: "HetznerKit"),
        .testTarget(
            name: "HetznerKitTests",
            dependencies: ["HetznerKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
