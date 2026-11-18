// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChiikawaDesktop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ChiikawaDesktop", targets: ["ChiikawaDesktop"])
    ],
    targets: [
        .executableTarget(
            name: "ChiikawaDesktop",
            path: "Sources/ChiikawaDesktop"
        )
    ]
)
