// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZonePort",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ZonePort", targets: ["ZonePort"])],
    targets: [
        .target(name: "ZoneNative", path: "Native", exclude: ["Zone-Bridging-Header.h"], publicHeadersPath: "include"),
        .target(
            name: "ZonePort", dependencies: ["ZoneNative"], path: ".",
            exclude: ["Native", "Scripts", "Tests", "Engine", "Docs", "Licenses", "Resources/Info.plist", "project.yml", "project-engine.yml", "xtool.yml", "README.md", "LICENSE", "STATUS.md", ".github"],
            sources: ["App"], resources: [.process("Resources/ZoneBackdrop.jpg")],
            linkerSettings: [.linkedFramework("UIKit"), .linkedFramework("GameController"), .linkedFramework("UniformTypeIdentifiers")]
        )
    ],
    swiftLanguageModes: [.v5]
)
