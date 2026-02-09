// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "aura",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .executable(name: "aura", targets: ["aura"])
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "aura",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios"),
            ],
            swiftSettings: [.enableExperimentalFeature("SwiftUIApp")]
        )
    ]
)
