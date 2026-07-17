// swift-tools-version: 6.0
import Foundation
import PackageDescription

let sweetCookieKitPath = "../SweetCookieKit"
// Fork note: default to the sibling checkout when present — upstream SweetCookieKit
// releases require Swift tools 6.2, and this fork builds with Xcode 16.2 (tools 6.0)
// against a locally tools-downgraded clone.
let useLocalSweetCookieKit =
    ProcessInfo.processInfo.environment["CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT"] == "1"
        || FileManager.default.fileExists(atPath: sweetCookieKitPath)
let sweetCookieKitDependency: Package.Dependency =
    useLocalSweetCookieKit && FileManager.default.fileExists(atPath: sweetCookieKitPath)
    ? .package(path: sweetCookieKitPath)
    : .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.4.1")

let sqlite3LibDir = ProcessInfo.processInfo.environment["CODEXBAR_SQLITE3_LIB_DIR"]?
    .trimmingCharacters(in: .whitespacesAndNewlines)
let sqlite3LinkerSettings: [LinkerSetting] = if let sqlite3LibDir, !sqlite3LibDir.isEmpty {
    [.unsafeFlags(["-L\(sqlite3LibDir)"], .when(platforms: [.linux]))]
} else {
    []
}

let package = Package(
    name: "CodexBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: {
        var products: [Product] = [
            .library(name: "CodexBarCore", targets: ["CodexBarCore"]),
            .executable(name: "CodexBarCLI", targets: ["CodexBarCLI"]),
            // Offline adaptive-refresh replay harness. Keep the supporting library package-internal.
            .executable(name: "AdaptiveReplayCLI", targets: ["AdaptiveReplayCLI"]),
        ]

        #if os(macOS)
        products.append(contentsOf: [
            .executable(name: "CodexBar", targets: ["CodexBar"]),
            .executable(name: "CodexBarClaudeWatchdog", targets: ["CodexBarClaudeWatchdog"]),
            .executable(name: "CodexBarWidget", targets: ["CodexBarWidget"]),
            .executable(name: "CodexBarClaudeWebProbe", targets: ["CodexBarClaudeWebProbe"]),
        ])
        #endif

        return products
    }(),
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
        .package(url: "https://github.com/steipete/Commander", from: "0.2.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        // Pinned to 1.8.0: newer swift-log needs Swift tools 6.1/6.2, this fork builds with Xcode 16.2.
        .package(url: "https://github.com/apple/swift-log", exact: "1.8.0"),
        // Pinned to 2.3.0: 2.4.0 needs Swift tools 6.1, this fork builds with Xcode 16.2 (tools 6.0).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.3.0"),
        .package(url: "https://github.com/zats/Vortex", revision: "ef5392088d4aeb255c4eee83157dbdafcd31bf07"),
        sweetCookieKitDependency,
    ],
    targets: {
        var targets: [Target] = [
            // Host pkg-config paths contaminate cross-musl links; the module map supplies sqlite3 linkage.
            .systemLibrary(
                name: "CSQLite3",
                providers: [
                    .apt(["libsqlite3-dev"]),
                    .brew(["sqlite3"]),
                ]),
            .target(
                name: "CodexBarCore",
                dependencies: [
                    .target(name: "CSQLite3", condition: .when(platforms: [.linux])),
                    .product(name: "Crypto", package: "swift-crypto"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                swiftSettings: [
                ],
                linkerSettings: sqlite3LinkerSettings),
            .executableTarget(
                name: "CodexBarCLI",
                dependencies: [
                    "CodexBarCore",
                    .product(name: "Commander", package: "Commander"),
                    .product(name: "Crypto", package: "swift-crypto"),
                ],
                path: "Sources/CodexBarCLI",
                swiftSettings: [
                ],
                linkerSettings: sqlite3LinkerSettings),
            // Sole owner of the adaptive refresh decision table. Package-internal so the app and
            // offline replay tool share behavior without publishing another library product.
            .target(
                name: "AdaptiveRefreshCore",
                dependencies: [],
                path: "Sources/AdaptiveRefreshCore",
                swiftSettings: [
                ]),
            // Offline adaptive-refresh replay harness: pure Foundation,
            // no CodexBar/CodexBarCore dependency, so it builds anywhere CodexBarCore does.
            .target(
                name: "AdaptiveReplayKit",
                dependencies: ["AdaptiveRefreshCore"],
                path: "Sources/AdaptiveReplayKit",
                exclude: ["README.md"],
                swiftSettings: [
                ]),
            .executableTarget(
                name: "AdaptiveReplayCLI",
                dependencies: ["AdaptiveReplayKit"],
                path: "Sources/AdaptiveReplayCLI",
                swiftSettings: [
                ]),
            .testTarget(
                name: "AdaptiveReplayCLITests",
                dependencies: ["AdaptiveReplayCLI", "AdaptiveReplayKit"],
                path: "Tests/AdaptiveReplayCLITests",
                swiftSettings: [
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
            .testTarget(
                name: "AdaptiveReplayKitTests",
                dependencies: ["AdaptiveRefreshCore", "AdaptiveReplayKit"],
                path: "Tests/AdaptiveReplayKitTests",
                swiftSettings: [
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
            .testTarget(
                name: "CodexBarLinuxTests",
                dependencies: [
                    "CodexBarCore",
                    "CodexBarCLI",
                    .target(name: "CSQLite3", condition: .when(platforms: [.linux])),
                ],
                path: "TestsLinux",
                swiftSettings: [
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
        ]

        #if os(macOS)
        targets.append(contentsOf: [
            .executableTarget(
                name: "CodexBarClaudeWatchdog",
                dependencies: [],
                path: "Sources/CodexBarClaudeWatchdog",
                swiftSettings: [
                ]),
            .executableTarget(
                name: "CodexBar",
                dependencies: [
                    .product(name: "Sparkle", package: "Sparkle"),
                    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                    .product(name: "Vortex", package: "Vortex"),
                    "AdaptiveRefreshCore",
                    "CodexBarCore",
                ],
                path: "Sources/CodexBar",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    // Opt into Swift 6 strict concurrency (approachable migration path).
                    .define("ENABLE_SPARKLE"),
                ]),
            .executableTarget(
                name: "CodexBarWidget",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarWidget",
                swiftSettings: [
                ]),
            .executableTarget(
                name: "CodexBarClaudeWebProbe",
                dependencies: ["CodexBarCore"],
                path: "Sources/CodexBarClaudeWebProbe",
                swiftSettings: [
                ]),
        ])

        targets.append(.testTarget(
            name: "CodexBarTests",
            dependencies: ["CodexBar", "CodexBarCore", "CodexBarCLI", "CodexBarWidget"],
            path: "Tests",
            exclude: ["AdaptiveReplayCLITests", "AdaptiveReplayKitTests"],
            resources: [
                .copy("CodexBarTests/Fixtures"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("SwiftTesting"),
            ]))
        #endif

        return targets
    }())
