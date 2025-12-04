// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "dincheck",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "dincheck", targets: ["dincheck"]),
    ],
    targets: [
        .executableTarget(
            name: "dincheck",
            path: "Sources/dincheck"
        ),
    ]
)
