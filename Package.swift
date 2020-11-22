// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Slinger",
    // products: [
    //     .executable(name: "Slinger", targets: ["Slinger"]),
    // ],
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/timbertson/AXSwift", from: "0.2.4"),
        // .package(url: "https://github.com/rampatra/MASShortcut", from: "2.4.1"),
        .package(url: "../../scratch/MASShortcut", from: "2.4.7"),
    ],
    targets: [
        .target(
            name: "Slinger",
            dependencies: ["AXSwift", "MASShortcut"],
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
        // .target(
        //     name: "Slinger-stubs",
        //     dependencies: ["AXSwift", "MASShortcut"],
        //     path: "stub",
        //     cSettings: [
        //       .headerSearchPath("Internal"),
        //     ]),
    ]
)
