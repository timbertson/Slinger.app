// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Slinger",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .executable(name: "Slinger", targets: ["Slinger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/timbertson/AXSwift", from: "0.2.4"),
        .package(url: "https://github.com/timbertson/MASShortcut", from: "2.4.8"),
        .package(url: "https://github.com/timbertson/Cairo", from: "1.2.4"),
        // .package(url: "../../scratch/MASShortcut", from: "2.4.7"),
    ],
    targets: [
        .target(
            name: "Slinger",
            dependencies: ["AXSwift", "MASShortcut", "Cairo"],
            path: "src",
            exclude: [
                "res/.gup",
                "res.gup",
            ],
            resources: [
                .copy("res/cocoa_impl.js"),
                .copy("res/icon.png"),
                .copy("res/icon-fade.png"),
            ]
        )
    ]
)
