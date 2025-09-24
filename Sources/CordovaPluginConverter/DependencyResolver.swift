import Foundation

/// Handles automatic resolution of CocoaPods dependencies to Swift Package Manager equivalents
public class DependencyResolver {
    private let podSpecResolver: PodSpecResolver
    private let gitChecker: GitRepositoryChecker
    private let spmParser: SPMPackageParser
    private let logger: Logger
    
    public init(logger: Logger) {
        self.logger = logger
        self.podSpecResolver = PodSpecResolver(logger: logger)
        self.gitChecker = GitRepositoryChecker(logger: logger)
        self.spmParser = SPMPackageParser(logger: logger)
    }
    
    /// Attempt to automatically resolve CocoaPods dependencies to SPM equivalents
    /// - Parameters:
    ///   - dependencies: Array of CocoaPods dependencies to resolve
    ///   - timeout: Maximum time to spend on resolution (default: 30 seconds)
    /// - Returns: Array of resolved SPM dependencies
    public func resolveCocoaPodDependencies(
        _ dependencies: [PodDependency],
        timeout: TimeInterval = 30.0
    ) async
        -> [ResolvedDependency] {
        logger.info("Attempting to automatically resolve \(dependencies.count) CocoaPods dependencies...")
        
        var resolvedDependencies: [ResolvedDependency] = []
        
        // Process dependencies concurrently with timeout
        await withTaskGroup(of: ResolvedDependency?.self) { group in
            for dependency in dependencies {
                group.addTask {
                    await self.resolveSingleDependency(dependency, timeout: timeout)
                }
            }
            
            for await result in group {
                if let resolved = result {
                    resolvedDependencies.append(resolved)
                }
            }
        }
        
        let successCount = resolvedDependencies.filter { $0.spmDependency != nil }.count
        logger.info("Successfully resolved \(successCount) out of \(dependencies.count) dependencies")
        
        return resolvedDependencies
    }
    
    /// Resolve a single CocoaPods dependency
    /// - Parameters:
    ///   - dependency: The CocoaPods dependency to resolve
    ///   - timeout: Maximum time to spend on this dependency
    /// - Returns: ResolvedDependency with SPM equivalent if found
    private func resolveSingleDependency(
        _ dependency: PodDependency,
        timeout: TimeInterval
    ) async
        -> ResolvedDependency? {
        await withTaskGroup(of: ResolvedDependency?.self) { group in
            group.addTask {
                await self.performResolution(for: dependency)
            }
            
            // Add timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1000000000))
                return ResolvedDependency(
                    originalPod: dependency,
                    spmDependency: nil,
                    status: .timeout
                )
            }
            
            // Return the first result (either success or timeout)
            for await result in group {
                if let resolved = result {
                    group.cancelAll()
                    return resolved
                }
            }
            
            return nil
        }
    }
    
    /// Perform the actual resolution process for a dependency
    /// - Parameter dependency: The CocoaPods dependency to resolve
    /// - Returns: ResolvedDependency with results
    private func performResolution(for dependency: PodDependency) async -> ResolvedDependency {
        logger.debug("Resolving \(dependency.name)...")
        
        // Step 1: Get pod spec information
        guard let podSpecInfo = await podSpecResolver.resolvePodSpec(for: dependency) else {
            return ResolvedDependency(
                originalPod: dependency,
                spmDependency: nil,
                status: .podSpecNotFound
            )
        }
        
        // Step 2: Check if we have a Git source URL
        guard let sourceUrl = podSpecInfo.sourceUrl else {
            return ResolvedDependency(
                originalPod: dependency,
                spmDependency: nil,
                status: .noGitSource
            )
        }
        
        // Step 3: Determine which reference to check (tag, branch, or default)
        let reference = podSpecInfo.sourceTag ?? podSpecInfo.sourceBranch ?? "main"
        
        // Step 4: Check if Package.swift exists in the repository
        let hasPackageSwift = await gitChecker.hasPackageSwift(in: sourceUrl, at: reference)
        
        if !hasPackageSwift {
            return ResolvedDependency(
                originalPod: dependency,
                spmDependency: nil,
                status: .noPackageSwift
            )
        }
        
        // Step 5: Fetch and parse Package.swift content
        guard let packageContent = await gitChecker.fetchPackageSwiftContent(from: sourceUrl, at: reference) else {
            return ResolvedDependency(
                originalPod: dependency,
                spmDependency: nil,
                status: .packageSwiftNotAccessible
            )
        }
        
        // Step 6: Parse Package.swift to extract library information
        guard let packageInfo = spmParser.parsePackageSwift(packageContent),
              spmParser.isLibraryPackage(packageContent) else {
            return ResolvedDependency(
                originalPod: dependency,
                spmDependency: nil,
                status: .notALibrary
            )
        }
        
        // Step 7: Create SPM dependency
        let requirement = PodSpecResolver.convertSpecToSPMRequirement(
            dependency.spec,
            sourceTag: podSpecInfo.sourceTag
        )
        
        // Use the parsed package info to get the main library name
        let productName = packageInfo.products.first(where: { $0.type == .library })?.name ?? packageInfo.name
        
        let spmDependency = SPMDependency(
            url: sourceUrl,
            requirement: requirement,
            productName: productName
        )
        
        return ResolvedDependency(
            originalPod: dependency,
            spmDependency: spmDependency,
            status: .resolved
        )
    }
}
