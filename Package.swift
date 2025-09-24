// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cdv2spm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "cdv2spm",
            targets: ["cdv2spm"]
        )
    ],
    dependencies: [
        // ArgumentParser for CLI handling
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        // SWXMLHash for XML parsing
        .package(url: "https://github.com/drmohundro/SWXMLHash.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "cdv2spm",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SWXMLHash", package: "SWXMLHash")
            ],
            path: "Sources/CordovaPluginConverter"
        ),
        .testTarget(
            name: "cdv2spmTests",
            dependencies: ["cdv2spm"],
            path: "Tests/CordovaPluginConverterTests"
        )
    ]
)
