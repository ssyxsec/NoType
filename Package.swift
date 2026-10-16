// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoType",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NoType", targets: ["NoType"]), .library(name: "NoTypeCore", targets: ["NoTypeCore"])],
    targets: [
        .target(name: "NoTypeCore"),
        .executableTarget(name: "NoType", dependencies: ["NoTypeCore"]),
        .testTarget(name: "NoTypeCoreTests", dependencies: ["NoTypeCore"])
    ]
)
