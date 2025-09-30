import XCTest
@testable import cdv2spm

final class PackageGeneratorTests: XCTestCase {
    func testGeneratePackageSwiftFromMetadata() {
        let dependencies = [
            PodDependency(name: "AFNetworking", spec: "~> 4.0"),
            PodDependency(name: "SDWebImage", spec: "~> 5.0")
        ]

        let metadata = PluginMetadata(
            pluginId: "com.example.testplugin",
            dependencies: dependencies,
            hasPodspec: true,
            originalXmlContent: ""
        )

        let packageContent = PackageGenerator.generatePackageSwift(from: metadata)

        XCTAssertTrue(packageContent.contains("name: \"com.example.testplugin\""))
        XCTAssertTrue(packageContent.contains("cordova-ios.git"))
        XCTAssertTrue(packageContent.contains("// TODO: Convert CocoaPods dependency: AFNetworking (~> 4.0)"))
        XCTAssertTrue(packageContent.contains("// TODO: Convert CocoaPods dependency: SDWebImage (~> 5.0)"))
        XCTAssertTrue(packageContent.contains("// TODO: Add Swift Package equivalent for: AFNetworking (~> 4.0)"))
        XCTAssertTrue(packageContent.contains("// TODO: Add Swift Package equivalent for: SDWebImage (~> 5.0)"))
    }

    func testGeneratePackageSwiftWithoutDependencies() {
        let metadata = PluginMetadata(
            pluginId: "com.example.simple",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: ""
        )

        let packageContent = PackageGenerator.generatePackageSwift(from: metadata)

        XCTAssertTrue(packageContent.contains("name: \"com.example.simple\""))
        XCTAssertTrue(packageContent.contains("cordova-ios.git"))
        XCTAssertFalse(packageContent.contains("TODO: Convert CocoaPods dependency"))
        XCTAssertFalse(packageContent.contains("TODO: Add Swift Package equivalent"))
    }

    func testValidatePackageSwiftSyntax() {
        let validPackage = """
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(
            name: "TestPackage",
            targets: [
                .target(name: "TestPackage")
            ]
        )
        """

        let invalidPackage = """
        This is not a valid Package.swift file
        """

        let incompletePackage = """
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(
            name: "TestPackage"
            // Missing targets
        )
        """

        XCTAssertTrue(PackageGenerator.validatePackageSwiftSyntax(validPackage))
        XCTAssertFalse(PackageGenerator.validatePackageSwiftSyntax(invalidPackage))
        XCTAssertFalse(PackageGenerator.validatePackageSwiftSyntax(incompletePackage))
    }

    func testPackageContentStructure() {
        let metadata = PluginMetadata(
            pluginId: "com.test.structure",
            dependencies: [PodDependency(name: "TestPod", spec: "1.0.0")],
            hasPodspec: true,
            originalXmlContent: ""
        )

        let packageContent = PackageGenerator.generatePackageSwift(from: metadata)

        // Check that the structure is valid Swift Package Manager format
        XCTAssertTrue(packageContent.hasPrefix("// swift-tools-version:5.9"))

        // Check for required sections in correct order
        let swiftToolsIndex = packageContent.range(of: "swift-tools-version")?.lowerBound
        let importIndex = packageContent.range(of: "import PackageDescription")?.lowerBound
        let packageIndex = packageContent.range(of: "let package = Package(")?.lowerBound

        XCTAssertNotNil(swiftToolsIndex)
        XCTAssertNotNil(importIndex)
        XCTAssertNotNil(packageIndex)

        // Verify order
        if let swift = swiftToolsIndex, let imp = importIndex, let pack = packageIndex {
            XCTAssertTrue(swift < imp)
            XCTAssertTrue(imp < pack)
        }
    }

    func testGeneratePackageSwiftWithCustomSourcePath() {
        let metadata = PluginMetadata(
            pluginId: "com.example.custompath",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: ""
        )

        let packageContent = PackageGenerator.generatePackageSwift(from: metadata, sourcePath: "custom/path")

        // Should use the custom source path
        XCTAssertTrue(packageContent.contains("path: \"custom/path\""))
        XCTAssertFalse(packageContent.contains("path: \"src/ios\""))
    }

    func testGeneratePackageSwiftWithoutHeaderFiles() {
        let metadata = PluginMetadata(
            pluginId: "com.example.noheaders",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: ""
        )

        // Use a non-existent path so no headers will be found
        let packageContent = PackageGenerator.generatePackageSwift(from: metadata, sourcePath: "nonexistent/path")

        // Should not contain publicHeadersPath when no headers are found
        XCTAssertFalse(packageContent.contains("publicHeadersPath"))
        XCTAssertTrue(packageContent.contains("path: \"nonexistent/path\""))
    }

    func testPublicHeadersPathDetection() {
        let metadata = PluginMetadata(
            pluginId: "com.example.withheaders",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: ""
        )

        // Test with Sources/CordovaPluginConverter which should have .swift files but no .h files
        let packageContent = PackageGenerator.generatePackageSwift(
            from: metadata,
            sourcePath: "Sources/CordovaPluginConverter"
        )

        // Should not contain publicHeadersPath for Swift source directory
        XCTAssertFalse(packageContent.contains("publicHeadersPath"))
        XCTAssertTrue(packageContent.contains("path: \"Sources/CordovaPluginConverter\""))
    }

    func testGeneratePackageSwiftWithFileManager() {
        let metadata = PluginMetadata(
            pluginId: "com.example.test",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: ""
        )

        // Create a mock FileSystemManager that finds headers
        let logger = Logger(verbose: false)
        let fileManager = MockFileSystemManager(logger: logger)

        let packageContent = PackageGenerator.generatePackageSwift(
            from: metadata,
            sourcePath: "src/ios",
            fileManager: fileManager
        )

        // Should contain publicHeadersPath when FileSystemManager finds headers
        XCTAssertTrue(packageContent.contains("publicHeadersPath: \".\""))
        XCTAssertTrue(packageContent.contains("path: \"src/ios\""))
    }

    func testGeneratePackageSwiftWithoutFileManager() {
        let metadata = PluginMetadata(
            pluginId: "com.example.test",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: ""
        )

        // Without FileSystemManager, no headers should be detected
        let packageContent = PackageGenerator.generatePackageSwift(
            from: metadata,
            sourcePath: "src/ios"
        )

        // Should not contain publicHeadersPath when no FileSystemManager is provided
        XCTAssertFalse(packageContent.contains("publicHeadersPath"))
        XCTAssertTrue(packageContent.contains("path: \"src/ios\""))
    }
}

// Mock FileSystemManager for testing
class MockFileSystemManager: FileSystemManager {
    override func findPublicHeadersPath(in _: String) -> String {
        // Mock behavior: always return "." to simulate headers in same directory
        "."
    }
}
