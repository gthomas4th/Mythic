// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "GameHubCore", platforms: [.macOS(.v14)],
    products: [.library(name: "GameHubCore", targets: ["GameHubCore"])],
    targets: [.target(name: "GameHubCore"), .testTarget(name: "GameHubCoreTests", dependencies: ["GameHubCore"])]
)
