// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Wisp", targets: ["Wisp"])],
    targets: [.executableTarget(name: "Wisp", linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("Carbon"),
        .linkedFramework("Security"), .linkedFramework("ServiceManagement")
    ])]
)
