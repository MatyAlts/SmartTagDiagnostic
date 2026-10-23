// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartTagDiagnostic",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SmartTagCore", targets: ["SmartTagCore"])],
    targets: [
        .target(name: "SmartTagCore"),
        .testTarget(name: "SmartTagCoreTests", dependencies: ["SmartTagCore"])
    ]
)
