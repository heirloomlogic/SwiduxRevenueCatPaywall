// swift-tools-version: 6.2

import Foundation
import PackageDescription

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
        // 1.10.0 is the published Swidux version pinned and exercised by this package.
        .package(url: "https://github.com/HeirloomLogic/Swidux", from: "1.10.0"),
        // 5.90.1 stopped the SDK from delivering a previous user's CustomerInfo after an identity
        // change (RevenueCat/purchases-ios#7758). Below it, `RevenueCatPaywall.logIn` can race a
        // stale anonymous fetch and report a paying user as free.
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.90.1"),
    ],
    targets: [
        .target(
            name: "SwiduxRevenueCatPaywall",
            dependencies: [
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ]
        ),
        .target(
            name: "SwiduxRevenueCatPaywallUI",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCatUI", package: "purchases-ios-spm"),
            ]
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallTests",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "Swidux", package: "Swidux"),
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ]
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallUITests",
            dependencies: [
                "SwiduxRevenueCatPaywallUI",
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ]
        ),
    ]
)

// MARK: - Dev-only tooling
//
// Dev-only tooling (the Persnoop swift-format linter and the DocC command plugin) must not
// leak into downstream consumers' dependency graphs. A build-tool plugin attached to a
// shipping target follows that target into every consumer — as a forced "trust and enable"
// prompt in Xcode, not merely a wasted checkout. SwiftPM has no first-class dev
// dependencies, so gate them on a gitignored `.dev-tooling` sentinel, present only in this
// package's own working clone (and created as a CI step, before the first resolve).
//
// `#filePath` anchors the lookup to this manifest's directory, independent of the current
// working directory. Attaching the plugin here, after the package is constructed, keeps the
// target list above free of gating noise.
//
// Toggling the sentinel on an already-evaluated package requires `swift package purge-cache`:
// SwiftPM caches the evaluated manifest keyed on its source text alone, so a gate that reads
// an external file is invisible to that cache key.

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path

if FileManager.default.fileExists(atPath: devSentinel) {
    package.dependencies += [
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ]
    for target in package.targets where target.type != .plugin && target.type != .binary {
        target.plugins = (target.plugins ?? []) + [.plugin(name: "Persnoop", package: "Persnicket")]
    }
}
