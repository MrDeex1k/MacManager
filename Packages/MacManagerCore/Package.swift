// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacManagerCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MacManagerCore", targets: ["MacManagerCore"])],
    targets: [
        .target(name: "MacManagerCore"),
        .testTarget(name: "MacManagerCoreTests", dependencies: ["MacManagerCore"])
    ]
)
