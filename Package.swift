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
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.5.0")
    ],
    targets: [
        .executableTarget(
            name: "dincheck",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/dincheck"
        ),
    ]
)
