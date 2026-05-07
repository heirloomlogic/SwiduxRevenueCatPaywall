// swift-tools-version: 6.2

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
        .package(url: "https://github.com/HeirloomLogic/Swidux", from: "1.0.0"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.0.0"),
        .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SwiduxRevenueCatPaywall",
            dependencies: [
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .target(
            name: "SwiduxRevenueCatPaywallUI",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCatUI", package: "purchases-ios-spm"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallTests",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "SwiduxPaywall", package: "Swidux"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
    ]
)
