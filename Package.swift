// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PersonalAI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PersonalAI", targets: ["PersonalAI"])],
    targets: [.executableTarget(name: "PersonalAI", linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("Carbon"),
        .linkedFramework("Security"), .linkedFramework("ServiceManagement")
    ])]
)
