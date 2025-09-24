import XCTest
@testable import cdv2spm

final class XMLParserBasicTests: XCTestCase {
    func testParseValidPluginXML() throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plugin xmlns="http://apache.org/cordova/ns/plugins/1.0"
                id="com.example.testplugin"
                version="1.0.0">
            <name>Test Plugin</name>
            <description>A test plugin</description>

            <platform name="ios">
                <podspec>
                    <pods>
                        <pod name="AFNetworking" spec="~> 4.0"/>
                        <pod name="SDWebImage" spec="~> 5.0"/>
                    </pods>
                </podspec>
            </platform>
        </plugin>
        """

        let metadata = try XMLParser.parsePluginXML(content: xmlContent)

        XCTAssertEqual(metadata.pluginId, "com.example.testplugin")
        XCTAssertEqual(metadata.dependencies.count, 2)
        XCTAssertTrue(metadata.hasPodspec)
        XCTAssertEqual(metadata.originalXmlContent, xmlContent)

        let afnetworking = metadata.dependencies.first { $0.name == "AFNetworking" }
        XCTAssertNotNil(afnetworking)
        XCTAssertEqual(afnetworking?.spec, "~> 4.0")

        let sdwebimage = metadata.dependencies.first { $0.name == "SDWebImage" }
        XCTAssertNotNil(sdwebimage)
        XCTAssertEqual(sdwebimage?.spec, "~> 5.0")
    }

    func testParsePluginXMLWithoutPods() throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plugin xmlns="http://apache.org/cordova/ns/plugins/1.0"
                id="com.example.simple"
                version="1.0.0">
            <name>Simple Plugin</name>
            <platform name="ios">
                <source-file src="src/ios/SimplePlugin.m"/>
            </platform>
        </plugin>
        """

        let metadata = try XMLParser.parsePluginXML(content: xmlContent)

        XCTAssertEqual(metadata.pluginId, "com.example.simple")
        XCTAssertEqual(metadata.dependencies.count, 0)
        XCTAssertFalse(metadata.hasPodspec)
        XCTAssertFalse(metadata.hasDependencies)
    }

    func testParsePluginXMLMissingId() {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plugin xmlns="http://apache.org/cordova/ns/plugins/1.0"
                version="1.0.0">
            <name>Missing ID Plugin</name>
        </plugin>
        """

        XCTAssertThrowsError(try XMLParser.parsePluginXML(content: xmlContent)) { error in
            XCTAssertTrue(error is XMLParsingError)
            if case XMLParsingError.missingPluginId = error {
                // Expected error
            } else {
                XCTFail("Expected XMLParsingError.missingPluginId")
            }
        }
    }

    func testParseInvalidXML() {
        let invalidXML = """
        This is not valid XML content
        <plugin id="test" but missing closing tag
        """

        XCTAssertThrowsError(try XMLParser.parsePluginXML(content: invalidXML)) { error in
            // SWXMLHash doesn't always throw parsingFailed for malformed XML
            // It may successfully parse but then fail to find the plugin id
            XCTAssertTrue(error is XMLParsingError)
        }
    }

    func testGenerateUpdatedXMLRemovesPodspec() {
        let originalXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plugin id="test.plugin" version="1.0.0">
            <platform name="ios">
                <podspec>
                    <pods>
                        <pod name="AFNetworking" spec="~> 4.0"/>
                    </pods>
                </podspec>
                <source-file src="src/ios/Plugin.m"/>
            </platform>
        </plugin>
        """

        let metadata = PluginMetadata(
            pluginId: "test.plugin",
            dependencies: [PodDependency(name: "AFNetworking", spec: "~> 4.0")],
            hasPodspec: true,
            originalXmlContent: originalXML
        )

        let updatedXML = XMLParser.generateUpdatedXML(from: metadata)

        XCTAssertFalse(updatedXML.contains("<podspec>"))
        XCTAssertFalse(updatedXML.contains("</podspec>"))
        XCTAssertFalse(updatedXML.contains("AFNetworking"))
        XCTAssertTrue(updatedXML.contains("source-file"))
    }

    func testGenerateUpdatedXMLAddsSwiftPackage() {
        let originalXML = """
        <plugin id="test.plugin">
            <platform name="ios">
                <source-file src="Plugin.m"/>
            </platform>
        </plugin>
        """

        let metadata = PluginMetadata(
            pluginId: "test.plugin",
            dependencies: [],
            hasPodspec: false,
            originalXmlContent: originalXML
        )

        let updatedXML = XMLParser.generateUpdatedXML(from: metadata)

        XCTAssertTrue(updatedXML.contains("package=\"swift\""))
    }

    func testXMLParsingErrorDescriptions() {
        let fileNotFoundError = XMLParsingError.fileNotFound("/path/to/file")
        let invalidXMLError = XMLParsingError.invalidXML("Missing closing tag")
        let missingPluginIdError = XMLParsingError.missingPluginId
        let parsingFailedError = XMLParsingError.parsingFailed("Unexpected token")

        XCTAssertEqual(fileNotFoundError.errorDescription, "Plugin XML file not found at: /path/to/file")
        XCTAssertEqual(invalidXMLError.errorDescription, "Invalid XML content: Missing closing tag")
        XCTAssertEqual(missingPluginIdError.errorDescription, "Plugin XML is missing required 'id' attribute")
        XCTAssertEqual(parsingFailedError.errorDescription, "Failed to parse XML: Unexpected token")
    }

    func testParseXMLWithSpecialCharactersInPluginId() throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plugin id="com.example.special-chars_123" version="1.0.0">
            <platform name="ios">
                <source-file src="src/ios/Plugin.m"/>
            </platform>
        </plugin>
        """

        let metadata = try XMLParser.parsePluginXML(content: xmlContent)

        XCTAssertEqual(metadata.pluginId, "com.example.special-chars_123")
        XCTAssertFalse(metadata.hasPodspec)
        XCTAssertEqual(metadata.dependencies.count, 0)
    }

    func testParseXMLWithAndroidAndIOSPlatforms() throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plugin id="com.example.crossplatform" version="1.0.0">
            <platform name="android">
                <!-- Android specific stuff should be ignored -->
                <source-file src="android/Plugin.java"/>
            </platform>
            <platform name="ios">
                <podspec>
                    <pods>
                        <pod name="IOSOnlyPod" spec="1.0.0"/>
                    </pods>
                </podspec>
            </platform>
            <platform name="browser">
                <!-- Browser platform should be ignored -->
                <js-module src="www/plugin.js"/>
            </platform>
        </plugin>
        """

        let metadata = try XMLParser.parsePluginXML(content: xmlContent)

        // Should only process iOS platform
        XCTAssertEqual(metadata.dependencies.count, 1)
        XCTAssertEqual(metadata.dependencies.first?.name, "IOSOnlyPod")
        XCTAssertTrue(metadata.hasPodspec)
    }
}
