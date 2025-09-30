import Foundation

/// Handles resolution of CocoaPods specifications to Swift Package Manager dependencies
public class PodSpecResolver {
    private let logger: Logger
    
    public init(logger: Logger) {
        self.logger = logger
    }
    
    /// Resolve a CocoaPods dependency to SPM information
    /// - Parameter dependency: The CocoaPods dependency to resolve
    /// - Returns: PodSpecInfo if successfully resolved, nil otherwise
    public func resolvePodSpec(for dependency: PodDependency) async -> PodSpecInfo? {
        logger.debug("Resolving pod spec for \(dependency.name) (\(dependency.spec))")
        
        do {
            let podSpecInfo = try await fetchPodSpecInfo(name: dependency.name, version: dependency.spec)
            logger.debug("Successfully resolved pod spec for \(dependency.name)")
            return podSpecInfo
        } catch {
            logger.debug("Failed to resolve pod spec for \(dependency.name): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Converts CocoaPods version specifications to equivalent Swift Package Manager requirements.
    /// Follows the CocoaPods and RubyGems versioning patterns documented at:
    /// - https://guides.cocoapods.org/syntax/podfile.html#pod
    /// - https://guides.rubygems.org/patterns/#semantic-versioning
    ///
    /// Supported conversions:
    /// - `= 1.0.0` → `.exact("1.0.0")`
    /// - `> 1.0.0`, `>= 1.0.0` → `.from("1.0.0")`
    /// - `~> 2.1` → `.upToNextMajor("2.1")` (>= 2.1.0, < 3.0.0)
    /// - `~> 2.1.3` → `.upToNextMinor("2.1.3")` (>= 2.1.3, < 2.2.0)
    /// - `< 2.0.0`, `<= 2.0.0` → `.upToNextMajor("2.0.0")` (SPM limitation)
    ///
    /// - Parameters:
    ///   - spec: The CocoaPods version specification
    ///   - sourceTag: Optional source tag that takes precedence over version spec
    /// - Returns: Equivalent SPM requirement
    public static func convertSpecToSPMRequirement(_ spec: String, sourceTag: String? = nil) -> SPMRequirement {
        let trimmedSpec = spec.trimmingCharacters(in: .whitespaces)
        
        // If we have a source tag, prefer using it
        if let tag = sourceTag {
            return .tag(tag)
        }
        
        // Handle common CocoaPods version patterns
        if trimmedSpec.hasPrefix("~>") {
            let version = String(trimmedSpec.dropFirst(2).trimmingCharacters(in: .whitespaces))
            // ~> works based on the last component specified
            // ~> 2.1 means >= 2.1.0 and < 3.0.0 (upToNextMajor)
            // ~> 2.1.3 means >= 2.1.3 and < 2.2.0 (upToNextMinor)
            let components = version.split(separator: ".").map(String.init)
            if components.count >= 3 {
                // Has patch version, use upToNextMinor
                return .upToNextMinor(version)
            } else {
                // Only major.minor, use upToNextMajor
                return .upToNextMajor(version)
            }
        } else if trimmedSpec.hasPrefix(">=") {
            let version = String(trimmedSpec.dropFirst(2).trimmingCharacters(in: .whitespaces))
            return .from(version)
        } else if trimmedSpec.hasPrefix("<=") {
            let version = String(trimmedSpec.dropFirst(2).trimmingCharacters(in: .whitespaces))
            return .upToNextMajor(version) // SPM doesn't have direct <=, use closest equivalent
        } else if trimmedSpec.hasPrefix("=") {
            let version = String(trimmedSpec.dropFirst(1).trimmingCharacters(in: .whitespaces))
            return .exact(version)
        } else if trimmedSpec.hasPrefix("<") {
            let version = String(trimmedSpec.dropFirst(1).trimmingCharacters(in: .whitespaces))
            // SPM doesn't have direct <, use upToNextMajor as closest equivalent
            return .upToNextMajor(version)
        } else if trimmedSpec.hasPrefix(">") {
            let version = String(trimmedSpec.dropFirst(1).trimmingCharacters(in: .whitespaces))
            return .from(version)
        } else {
            // Default to exact version if no prefix
            return .exact(trimmedSpec)
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchPodSpecInfo(name: String, version: String) async throws -> PodSpecInfo {
        let command = "pod spec cat \(name)"
        let versionCommand = version.isEmpty ? command : "\(command) --version=\(version)"
        
        logger.debug("Executing: \(versionCommand)")
        
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["bash", "-c", versionCommand]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: PodSpecError.invalidOutput("Could not decode pod spec output"))
                    return
                }
                
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: PodSpecError.commandFailed("pod spec cat failed: \(output)"))
                    return
                }
                
                do {
                    let podSpecInfo = try self.parsePodSpecOutput(output, name: name, version: version)
                    continuation.resume(returning: podSpecInfo)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation
                    .resume(throwing: PodSpecError
                        .commandFailed("Failed to execute pod spec cat: \(error.localizedDescription)"))
            }
        }
    }
    
    private func parsePodSpecOutput(_ output: String, name: String, version: String) throws -> PodSpecInfo {
        guard let data = output.data(using: .utf8) else {
            throw PodSpecError.invalidOutput("Could not encode pod spec output as UTF-8")
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PodSpecError.invalidJSON("Pod spec output is not valid JSON")
            }
            
            let extractedVersion = json["version"] as? String ?? version
            let homepage = json["homepage"] as? String
            let vendoredFrameworks = json["vendored_frameworks"] as? String
            
            // Extract and determine source type
            let sourceType = extractSourceType(from: json, podName: name)
            
            logger.debug("Parsed pod spec for \(name): version=\(extractedVersion), sourceType=\(sourceType.description)")
            
            return PodSpecInfo(
                name: name,
                version: extractedVersion,
                sourceType: sourceType,
                homepage: homepage,
                vendoredFrameworks: vendoredFrameworks
            )
            
        } catch {
            throw PodSpecError.invalidJSON("Failed to parse pod spec JSON: \(error.localizedDescription)")
        }
    }
    
    private func extractSourceType(from json: [String: Any], podName: String) -> PodSourceType {
        guard let source = json["source"] as? [String: Any] else {
            logger.debug("No source found in podspec for \(podName)")
            return .unknown
        }
        
        // Check for Git source
        if let gitUrl = source["git"] as? String {
            let tag = source["tag"] as? String
            let branch = source["branch"] as? String
            logger.debug("Found Git source for \(podName): \(gitUrl)")
            return .git(url: gitUrl, tag: tag, branch: branch)
        }
        
        // Check for HTTP source (ZIP, TAR, etc.)
        if let httpUrl = source["http"] as? String {
            logger.debug("Found HTTP source for \(podName): \(httpUrl)")
            return .http(url: httpUrl)
        }
        
        // Check for local source
        if let localPath = source["path"] as? String {
            logger.debug("Found local source for \(podName): \(localPath)")
            return .local(path: localPath)
        }
        
        // Check for other source types (SVN, Mercurial, etc.)
        if let svnUrl = source["svn"] as? String {
            logger.debug("Found SVN source for \(podName): \(svnUrl) (not supported)")
            return .unknown
        }
        
        if let hgUrl = source["hg"] as? String {
            logger.debug("Found Mercurial source for \(podName): \(hgUrl) (not supported)")
            return .unknown
        }
        
        logger.debug("Unknown source type for \(podName): \(source)")
        return .unknown
    }
    

}

/// Errors that can occur during pod spec resolution
public enum PodSpecError: Error, LocalizedError {
    case commandFailed(String)
    case invalidOutput(String)
    case invalidJSON(String)
    
    public var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            "Pod spec command failed: \(message)"
        case let .invalidOutput(message):
            "Invalid pod spec output: \(message)"
        case let .invalidJSON(message):
            "Invalid pod spec JSON: \(message)"
        }
    }
}
