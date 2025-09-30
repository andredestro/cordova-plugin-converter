import Foundation

// MARK: - CocoaPods Models

/// Represents a CocoaPods dependency from plugin.xml
public struct PodDependency: Equatable, Codable {
    public let name: String
    public let spec: String

    public init(name: String, spec: String) {
        self.name = name
        self.spec = spec
    }

    /// Human-readable description
    public var description: String {
        "\(name) (\(spec))"
    }
}

/// Types of CocoaPods source configurations
public enum PodSourceType: Equatable {
    case git(url: String, tag: String?, branch: String?)
    case http(url: String)
    case local(path: String)
    case unknown
    
    public var description: String {
        switch self {
        case let .git(url, tag, branch):
            var desc = "Git: \(url)"
            if let tag = tag { desc += " (tag: \(tag))" }
            if let branch = branch { desc += " (branch: \(branch))" }
            return desc
        case let .http(url):
            return "HTTP: \(url)"
        case let .local(path):
            return "Local: \(path)"
        case .unknown:
            return "Unknown source type"
        }
    }
}

/// Represents information extracted from a CocoaPods specification
public struct PodSpecInfo: Equatable {
    public let name: String
    public let version: String
    public let sourceType: PodSourceType
    public let homepage: String?
    public let vendoredFrameworks: String?

    public init(
        name: String,
        version: String,
        sourceType: PodSourceType,
        homepage: String? = nil,
        vendoredFrameworks: String? = nil
    ) {
        self.name = name
        self.version = version
        self.sourceType = sourceType
        self.homepage = homepage
        self.vendoredFrameworks = vendoredFrameworks
    }
}

// MARK: - Swift Package Manager Models

/// Represents different types of SPM dependency requirements
public enum SPMRequirement: Equatable {
    case exact(String)
    case from(String)
    case upToNextMajor(String)
    case upToNextMinor(String)
    case branch(String)
    case tag(String)
    
    public var description: String {
        switch self {
        case let .exact(version):
            "exact: \"\(version)\""
        case let .from(version):
            "from: \"\(version)\""
        case let .upToNextMajor(version):
            ".upToNextMajor(from: \"\(version)\")"
        case let .upToNextMinor(version):
            ".upToNextMinor(from: \"\(version)\")"
        case let .branch(branch):
            "branch: \"\(branch)\""
        case let .tag(tag):
            "exact: \"\(tag)\""
        }
    }
}

/// Represents a resolved Swift Package Manager dependency
public struct SPMDependency: Equatable {
    public let url: String
    public let requirement: SPMRequirement
    public let productName: String?
    
    public init(url: String, requirement: SPMRequirement, productName: String? = nil) {
        self.url = url
        self.requirement = requirement
        self.productName = productName
    }
}

/// Represents package information extracted from a Package.swift file
public struct SPMPackageInfo: Equatable {
    public let name: String
    public let dependencies: [SPMDependency]
    public let products: [SPMProduct]
    public let targets: [SPMTarget]
    
    public init(
        name: String,
        dependencies: [SPMDependency] = [],
        products: [SPMProduct] = [],
        targets: [SPMTarget] = []
    ) {
        self.name = name
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
    }
}

/// Types of SPM products
public enum SPMProductType: Equatable {
    case library
    case executable
    
    public var description: String {
        switch self {
        case .library: "library"
        case .executable: "executable"
        }
    }
}

/// Represents a Swift Package Manager product
public struct SPMProduct: Equatable {
    public let name: String
    public let type: SPMProductType
    public let targets: [String]
    
    public init(name: String, type: SPMProductType, targets: [String]) {
        self.name = name
        self.type = type
        self.targets = targets
    }
}

/// Represents a Swift Package Manager target
public struct SPMTarget: Equatable {
    public let name: String
    public let dependencies: [String]

    public init(name: String, dependencies: [String] = []) {
        self.name = name
        self.dependencies = dependencies
    }
}

// MARK: - Dependency Resolution Models

/// Status of dependency resolution attempt
public enum ResolutionStatus: Equatable {
    case resolved
    case podSpecNotFound
    case noGitSource
    case noPackageSwift
    case packageSwiftNotAccessible
    case notALibrary
    case timeout
    case error(String)
    case httpSourceFound(gitUrl: String?)  // HTTP source found, optionally with inferred Git URL
    case xcframeworkFound(gitUrl: String?, downloadUrl: String)  // XCFramework found
    case requiresManualIntegration(reason: String)  // Cannot be automatically converted
    
    public var description: String {
        switch self {
        case .resolved:
            return "Successfully resolved"
        case .podSpecNotFound:
            return "Pod spec not found"
        case .noGitSource:
            return "No Git source URL"
        case .noPackageSwift:
            return "No Package.swift found"
        case .packageSwiftNotAccessible:
            return "Package.swift not accessible"
        case .notALibrary:
            return "Not a library package"
        case .timeout:
            return "Resolution timed out"
        case let .error(message):
            return "Error: \(message)"
        case let .httpSourceFound(gitUrl):
            if let url = gitUrl {
                return "HTTP source found, Git repository inferred: \(url)"
            } else {
                return "HTTP source found, no Git repository could be inferred"
            }
        case let .xcframeworkFound(gitUrl, downloadUrl):
            var desc = "XCFramework found at: \(downloadUrl)"
            if let url = gitUrl {
                desc += ", Git repository: \(url)"
            }
            return desc
        case let .requiresManualIntegration(reason):
            return "Requires manual integration: \(reason)"
        }
    }
    
    /// Whether this status indicates a successful resolution
    public var isSuccess: Bool {
        self == .resolved
    }
}

/// Result of resolving a single CocoaPods dependency to SPM
public struct ResolvedDependency: Equatable {
    public let originalPod: PodDependency
    public let spmDependency: SPMDependency?
    public let status: ResolutionStatus
    
    public init(
        originalPod: PodDependency,
        spmDependency: SPMDependency?,
        status: ResolutionStatus
    ) {
        self.originalPod = originalPod
        self.spmDependency = spmDependency
        self.status = status
    }
    
    /// Whether this dependency was successfully resolved
    public var isResolved: Bool {
        status == .resolved && spmDependency != nil
    }
}

/// Represents the complete metadata extracted from plugin.xml
public struct PluginMetadata: Equatable {
    public let pluginId: String
    public let dependencies: [PodDependency]
    public let hasPodspec: Bool
    public let originalXmlContent: String

    public init(pluginId: String, dependencies: [PodDependency], hasPodspec: Bool, originalXmlContent: String) {
        self.pluginId = pluginId
        self.dependencies = dependencies
        self.hasPodspec = hasPodspec
        self.originalXmlContent = originalXmlContent
    }

    /// Package name derived from plugin ID
    public var packageName: String {
        pluginId.isEmpty ? "UnknownPlugin" : pluginId
    }

    /// Whether this plugin has any CocoaPods dependencies
    public var hasDependencies: Bool {
        !dependencies.isEmpty
    }

    /// Dependency descriptions for logging
    public var dependencyDescriptions: [String] {
        dependencies.map(\.description)
    }
}

/// Configuration options for the conversion process
public struct ConversionOptions {
    public let force: Bool
    public let dryRun: Bool
    public let verbose: Bool
    public let noGitignore: Bool
    public let backup: Bool
    public let autoResolve: Bool
    public let inputPath: String?

    public init(
        force: Bool = false,
        dryRun: Bool = false,
        verbose: Bool = false,
        noGitignore: Bool = false,
        backup: Bool = false,
        autoResolve: Bool = false,
        inputPath: String? = nil
    ) {
        self.force = force
        self.dryRun = dryRun
        self.verbose = verbose
        self.noGitignore = noGitignore
        self.backup = backup
        self.autoResolve = autoResolve
        self.inputPath = inputPath
    }
}

/// Result of a conversion operation
public enum ConversionResult {
    case success(String)
    case skipped(String)
    case error(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
