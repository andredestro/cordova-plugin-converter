import Foundation
import SWXMLHash

/// Errors that can occur during XML parsing
public enum XMLParsingError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidXML(String)
    case missingPluginId
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "Plugin XML file not found at: \(path)"
        case let .invalidXML(reason):
            "Invalid XML content: \(reason)"
        case .missingPluginId:
            "Plugin XML is missing required 'id' attribute"
        case let .parsingFailed(reason):
            "Failed to parse XML: \(reason)"
        }
    }
}

/// Handles parsing of Cordova plugin.xml files
public class XMLParser {
    /// Parse plugin.xml file and extract metadata
    /// - Parameter xmlPath: Path to the plugin.xml file
    /// - Returns: Parsed plugin metadata
    /// - Throws: XMLParsingError if parsing fails
    public static func parsePluginXML(at xmlPath: String) throws -> PluginMetadata {
        // Read file content
        guard let xmlContent = try? String(contentsOfFile: xmlPath, encoding: .utf8) else {
            throw XMLParsingError.fileNotFound(xmlPath)
        }

        return try parsePluginXML(content: xmlContent)
    }

    /// Parse plugin.xml content and extract metadata
    /// - Parameter content: Raw XML content as string
    /// - Returns: Parsed plugin metadata
    /// - Throws: XMLParsingError if parsing fails
    public static func parsePluginXML(content: String) throws -> PluginMetadata {
        let xml = XMLHash.parse(content)

        // Extract plugin ID
        guard let pluginId = xml["plugin"].element?.attribute(by: "id")?.text else {
            throw XMLParsingError.missingPluginId
        }

        // Extract pod dependencies from all platforms
        var allDependencies: [PodDependency] = []
        var hasPodspec = false

        // Look for podspec sections only in iOS platform
        for platform in xml["plugin"]["platform"].all {
            // Only process iOS platforms
            if let platformName = platform.element?.attribute(by: "name")?.text,
               platformName.lowercased() == "ios" {
                if platform["podspec"].element != nil {
                    hasPodspec = true

                    // Look for pod elements in the podspec
                    let podElements = platform["podspec"]["pods"]["pod"].all

                    for podElement in podElements {
                        if let name = podElement.element?.attribute(by: "name")?.text,
                           let spec = podElement.element?.attribute(by: "spec")?.text {
                            let dependency = PodDependency(name: name, spec: spec)
                            // Avoid duplicates
                            if !allDependencies.contains(dependency) {
                                allDependencies.append(dependency)
                            }
                        }
                    }
                }
            }
        }

        return PluginMetadata(
            pluginId: pluginId,
            dependencies: allDependencies,
            hasPodspec: hasPodspec,
            originalXmlContent: content
        )
    }

    /// Generate updated plugin.xml content with package="swift" added and optionally podspec removed
    /// - Parameters:
    ///   - metadata: Original plugin metadata
    ///   - removePodspec: Whether to remove the podspec section (default: true)
    /// - Returns: Updated XML content with package="swift" for iOS platform
    public static func generateUpdatedXML(from metadata: PluginMetadata, removePodspec: Bool = true) -> String {
        var updatedContent = metadata.originalXmlContent

        // First: Always ensure iOS platform has package="swift" attribute
        let platformPattern = #"<platform\s+name="ios"([^>]*?)>"#
        guard let platformRegex = try? NSRegularExpression(pattern: platformPattern, options: []) else {
            return updatedContent // Return original content if regex fails
        }

        let nsString = updatedContent as NSString
        let matches = platformRegex.matches(in: updatedContent, range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let matchedString = nsString.substring(with: match.range)
            let replacement: String = if matchedString.contains("package=") {
                // Replace existing package attribute with "swift"
                matchedString.replacingOccurrences(
                    of: #"package="[^"]*""#,
                    with: #"package="swift""#,
                    options: .regularExpression
                )
            } else {
                // Add package="swift" attribute
                matchedString.replacingOccurrences(of: ">", with: " package=\"swift\">")
            }

            updatedContent = (updatedContent as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        // Second: Remove podspec section using regex (only if requested)
        if removePodspec {
            let podspecPattern = #"<podspec>[\s\S]*?</podspec>"#
            updatedContent = updatedContent.replacingOccurrences(
                of: podspecPattern,
                with: "",
                options: .regularExpression
            )
        }

        return updatedContent
    }
}
