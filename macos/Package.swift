// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LumenInstaller",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LumenInstaller", path: "Sources/LumenInstaller")
    ]
)
