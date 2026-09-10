// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacManagerCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MacManagerCore", targets: ["MacManagerCore"])],
    targets: [
        .target(name: "MMHardware", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "MMInput", linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("IOKit")]),
        .target(name: "MacManagerCore", dependencies: ["MMHardware", "MMInput"]),
        .testTarget(name: "MacManagerCoreTests", dependencies: ["MacManagerCore"])
    ]
)
