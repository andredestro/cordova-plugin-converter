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

/// Represents information extracted from a CocoaPods specification
public struct PodSpecInfo: Equatable {
    public let name: String
    public let version: String
    public let sourceUrl: String?
    public let sourceTag: String?
    public let sourceBranch: String?

    public init(
        name: String,
        version: String,
        sourceUrl: String? = nil,
        sourceTag: String? = nil,
        sourceBranch: String? = nil
    ) {
        self.name = name
        self.version = version
        self.sourceUrl = sourceUrl
        self.sourceTag = sourceTag
        self.sourceBranch = sourceBranch
    }
}

// MARK: - Swift Package Manager Models

/// Represents different types of SPM dependency requirements
public enum SPMRequirement: Equatable {
    case exact(String)
    case from(String)
    case upToNextMajor(String)
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

/// Types of SPM targets
public enum SPMTargetType: String {
    case target
}

/// Represents a Swift Package Manager target
public struct SPMTarget: Equatable {
    public let name: String
    public let type: SPMTargetType
    public let dependencies: [String]

    public init(name: String, type: SPMTargetType, dependencies: [String] = []) {
        self.name = name
        self.type = type
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
    
    public var description: String {
        switch self {
        case .resolved:
            "Successfully resolved"
        case .podSpecNotFound:
            "Pod spec not found"
        case .noGitSource:
            "No Git source URL"
        case .noPackageSwift:
            "No Package.swift found"
        case .packageSwiftNotAccessible:
            "Package.swift not accessible"
        case .notALibrary:
            "Not a library package"
        case .timeout:
            "Resolution timed out"
        case let .error(message):
            "Error: \(message)"
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
