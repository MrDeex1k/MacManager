// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stage1Probes",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "mac-manager-probe", targets: ["ProbeCLI"])],
    targets: [
        .target(name: "HardwareBridge", linkerSettings: [
            .linkedFramework("IOKit"), .linkedFramework("CoreFoundation")
        ]),
        .target(name: "ProbeCore", dependencies: ["HardwareBridge"]),
        .executableTarget(name: "ProbeCLI", dependencies: ["ProbeCore"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"])
    ]
)
