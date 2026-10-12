// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContextEnglishAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ContextEnglishCore",
            targets: ["ContextEnglishCore"]
        ),
        .executable(
            name: "ContextEnglishAssistant",
            targets: ["ContextEnglishAssistantApp"]
        ),
        .executable(
            name: "ContextEnglishCoreChecks",
            targets: ["ContextEnglishCoreChecks"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3"
        ),
        .target(
            name: "ContextEnglishCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "ContextEnglishAssistantApp",
            dependencies: ["ContextEnglishCore", "CSQLite"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "ContextEnglishCoreChecks",
            dependencies: ["ContextEnglishCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ContextEnglishCoreTests",
            dependencies: ["ContextEnglishCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
