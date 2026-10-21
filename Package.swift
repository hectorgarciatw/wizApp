// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LuzWiz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LuzWiz", path: "Sources/LuzWiz")
    ]
)
