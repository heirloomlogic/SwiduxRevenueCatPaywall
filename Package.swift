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
        .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
        .package(url: "https://github.com/HeirloomLogic/Swidux", branch: "main"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiduxRevenueCatPaywall",
            dependencies: [
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
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
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallTests",
            dependencies: [
                "SwiduxRevenueCatPaywall",
                .product(name: "SwiduxPaywall", package: "Swidux"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
        .testTarget(
            name: "SwiduxRevenueCatPaywallUITests",
            dependencies: [
                "SwiduxRevenueCatPaywallUI",
                .product(name: "SwiduxPaywall", package: "Swidux"),
            ],
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket")
            ]
        ),
    ]
)
