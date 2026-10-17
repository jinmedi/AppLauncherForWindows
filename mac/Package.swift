// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppLauncherForMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AppLauncher", targets: ["AppLauncher"]),
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
    ],
    targets: [
        // UI-independent logic: models, fuzzy search, ranking, usage history, settings, indexing.
        // Foundation only, so it also builds and tests on Linux.
        .target(
            name: "LauncherCore",
            path: "Sources/LauncherCore"
        ),
        // The menu-bar app: AppKit panel, Carbon global hotkey, status item.
        .executableTarget(
            name: "AppLauncher",
            dependencies: ["LauncherCore"],
            path: "Sources/AppLauncher",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "LauncherCoreTests",
            dependencies: ["LauncherCore"],
            path: "Tests/LauncherCoreTests"
        ),
    ]
)
