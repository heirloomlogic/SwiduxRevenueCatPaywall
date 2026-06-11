// swift-tools-version: 6.2

import PackageDescription
import Foundation

// Dev-only tooling (the Persnoop swift-format linter and swift-docc-plugin) must not
// leak into downstream consumers' dependency graphs. SwiftPM has no first-class
// dev-dependencies, so gate them on a gitignored `.dev-tooling` sentinel, present only
// in this package's own working clone (and created as a step in CI). `#filePath` anchors
// the lookup to this manifest's directory, independent of the current working directory.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path
let isDevBuild = FileManager.default.fileExists(atPath: devSentinel)

let devDependencies: [Package.Dependency] = isDevBuild
    ? [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ]
    : []

let devPlugins: [Target.PluginUsage] = isDevBuild
    ? [.plugin(name: "Persnoop", package: "Persnicket")]
    : []

let package = Package(
    name: "SwiduxRevenueCatPaywall",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "SwiduxRevenueCatPaywall", targets: ["SwiduxRevenueCatPaywall"]),
        .library(name: "SwiduxRevenueCatPaywallUI", targets: ["SwiduxRevenueCatPaywallUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/HeirloomLogic/Swidux", from: "1.3.0"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.0.0"),
    ] + devDependencies,
    targets: [
        .target(
            name: "SwiduxRevenueCatPaywall",
            dependencies: [
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            plugins: devPlugins
        ),
        .target(
            name: "SwiduxRevenueCatPaywallUI",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCatUI", package: "purchases-ios-spm"),
            ],
            plugins: devPlugins
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallTests",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            plugins: devPlugins
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallUITests",
            dependencies: [
                "SwiduxRevenueCatPaywallUI",
                .product(name: "SwiduxPaywall", package: "Swidux"),
            ],
            plugins: devPlugins
        ),
    ]
)
