// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stage1Probes",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "mac-manager-probe", targets: ["ProbeCLI"])],
    dependencies: [.package(path: "../../Packages/MacManagerCore")],
    targets: [
        .target(name: "HardwareBridge", linkerSettings: [
            .linkedFramework("IOKit"), .linkedFramework("CoreFoundation")
        ]),
        .target(name: "ProbeCore", dependencies: ["HardwareBridge", .product(name: "MacManagerCore", package: "MacManagerCore")]),
        .executableTarget(name: "ProbeCLI", dependencies: ["ProbeCore"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"])
    ]
)
