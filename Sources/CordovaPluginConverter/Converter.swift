import Foundation

/// Main converter class that orchestrates the entire conversion process
public class CordovaToSPMConverter {
    private let logger: Logger
    private let fileManager: FileSystemManager
    private let userInteraction: UserInteraction
    private let gitignoreManager: GitignoreManager
    private let options: ConversionOptions

    public init(options: ConversionOptions) {
        self.options = options
        logger = Logger(verbose: options.verbose)
        fileManager = FileSystemManager(logger: logger, dryRun: options.dryRun)
        userInteraction = UserInteraction(force: options.force, logger: logger)
        gitignoreManager = GitignoreManager(fileManager: fileManager, logger: logger)
    }

    /// Run the complete conversion process
    /// - Returns: Overall success/failure result
    public func convert() async -> Bool {
        logger.info("Starting Cordova plugin to Swift Package Manager conversion")

        // Resolve plugin.xml path
        let pluginXMLPath = fileManager.resolvePluginXMLPath(options.inputPath)
        logger.info("Using plugin.xml at: \(pluginXMLPath)")

        var resolvedDependencies: [ResolvedDependency]?
        
        do {
            // Step 1: Parse plugin.xml
            logger.debug("Parsing plugin.xml...")
            let metadata = try parsePluginXML(at: pluginXMLPath)

            // Step 2: Display plugin information
            displayPluginInfo(metadata)

            // Step 3: Generate and write Package.swift (includes auto-resolution if enabled)
            let (packageResult, resolvedDeps) = try await generatePackageSwiftWithDependencies(
                metadata,
                pluginDirectory: pluginXMLPath.directoryPath
            )
            resolvedDependencies = resolvedDeps

            // Step 4: Update plugin.xml if needed
            let xmlUpdateResult = try updatePluginXMLIfNeeded(metadata, at: pluginXMLPath)

            // Step 5: Add conditional Cordova imports to Swift files
            _ = addCordovaImportsToSwiftFiles(in: pluginXMLPath.directoryPath)

            // Step 6: Update .gitignore if requested (after plugin.xml update)
            if !options.noGitignore {
                updateGitignoreIfRequested(in: pluginXMLPath.directoryPath)
            }

            // Step 7: Display final summary
            displayFinalSummary(
                metadata,
                packageResult: packageResult,
                xmlUpdated: xmlUpdateResult,
                resolvedDependencies: resolvedDependencies
            )

            return true

        } catch let error as XMLParsingError {
            logger.error("XML parsing failed: \(error.localizedDescription)")
            return false
        } catch let error as FileOperationError {
            logger.error("File operation failed: \(error.localizedDescription)")
            return false
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Methods

    private func parsePluginXML(at path: String) throws -> PluginMetadata {
        guard fileManager.fileExists(at: path) else {
            throw XMLParsingError.fileNotFound(path)
        }

        return try XMLParser.parsePluginXML(at: path)
    }

    private func displayPluginInfo(_ metadata: PluginMetadata) {
        logger.info("Plugin ID: \(metadata.pluginId)")

        if metadata.hasDependencies {
            logger.info("Found \(metadata.dependencies.count) CocoaPods dependencies:")
            for dependency in metadata.dependencyDescriptions {
                logger.info("  - \(dependency)")
            }
        } else {
            logger.warn("No CocoaPods dependencies found")
        }
    }

    private func displayResolutionResults(_ resolvedDependencies: [ResolvedDependency]) {
        let resolvedCount = resolvedDependencies.filter(\.isResolved).count
        let totalCount = resolvedDependencies.count
        
        if resolvedCount > 0 {
            logger.success("Successfully resolved \(resolvedCount) out of \(totalCount) dependencies:")
            
            for resolved in resolvedDependencies {
                if resolved.isResolved {
                    if let spmDep = resolved.spmDependency {
                        logger.info("  ✅ \(resolved.originalPod.name) → \(spmDep.url)")
                    }
                } else {
                    logger.warn("  ❌ \(resolved.originalPod.name): \(resolved.status.description)")
                }
            }
        } else {
            logger.warn("Could not automatically resolve any dependencies")
            for resolved in resolvedDependencies {
                logger.debug("  \(resolved.originalPod.name): \(resolved.status.description)")
            }
        }
    }

    private func generatePackageSwiftWithDependencies(_ metadata: PluginMetadata,
                                                      pluginDirectory: String) async throws
        -> (ConversionResult, [ResolvedDependency]?) {
        let packageSwiftPath = pluginDirectory.appendingPathComponent("Package.swift")

        // Check if Package.swift already exists
        if fileManager.fileExists(at: packageSwiftPath) {
            let shouldOverwrite = userInteraction.confirmAction(
                "Package.swift already exists at \(packageSwiftPath). Overwrite?",
                defaultYes: false
            )

            if !shouldOverwrite {
                logger.info("Skipping Package.swift generation")
                return (.skipped("User chose not to overwrite existing Package.swift"), nil)
            }

            // Create backup before overwriting if backup flag is enabled
            if let backupPath = try fileManager.createBackupIfNeeded(
                of: packageSwiftPath,
                shouldBackup: options.backup
            ) {
                logger.info("Created backup: \(backupPath)")
            }
        }

        // Resolve dependencies automatically if requested
        var resolvedDependencies: [ResolvedDependency]?
        if options.autoResolve, metadata.hasDependencies {
            logger.info("Attempting automatic dependency resolution...")
            let resolver = DependencyResolver(logger: logger)
            resolvedDependencies = await resolver.resolveCocoaPodDependencies(metadata.dependencies)
            
            // Display resolution results
            displayResolutionResults(resolvedDependencies!)
        }

        // Generate Package.swift content
        let packageContent = PackageGenerator.generatePackageSwift(
            from: metadata,
            fileManager: fileManager,
            resolvedDependencies: resolvedDependencies
        )

        // Validate generated content
        guard PackageGenerator.validatePackageSwiftSyntax(packageContent) else {
            let errorInfo = [NSLocalizedDescriptionKey: "Generated Package.swift has invalid syntax"]
            let validationError = NSError(domain: "ValidationError", code: 1, userInfo: errorInfo)
            throw FileOperationError.writeError(packageSwiftPath, validationError)
        }

        // Write Package.swift
        try fileManager.writeFile(content: packageContent, to: packageSwiftPath)

        if options.dryRun {
            return (.success("[DRY-RUN] Package.swift would be generated at \(packageSwiftPath)"), resolvedDependencies)
        } else {
            return (.success("Package.swift generated at \(packageSwiftPath)"), resolvedDependencies)
        }
    }

    private func updateGitignoreIfRequested(in directory: String) {
        let shouldUpdate = userInteraction.confirmAction(
            "Update .gitignore with Swift Package Manager build artifacts?",
            defaultYes: true
        )

        if shouldUpdate {
            let result = gitignoreManager.updateGitignore(in: directory, shouldBackup: options.backup)
            switch result {
            case let .success(message):
                logger.success(message)
            case let .skipped(message):
                logger.info(message)
            case let .error(message):
                logger.warn(message)
            }
        } else {
            logger.info("Skipping .gitignore update")
        }
    }

    private func updatePluginXMLIfNeeded(_ metadata: PluginMetadata, at path: String) throws -> Bool {
        // Always add package="swift"
        logger.info("Adding package=\"swift\" attribute to iOS platform")

        var updateMessage = "Updated plugin.xml (added package=\"swift\" to iOS platform)"

        if metadata.hasPodspec {
            logger.info("Adding nospm=\"true\" attribute to <pod> elements in plugin.xml")
            updateMessage = "Updated plugin.xml (added package=\"swift\" and nospm=\"true\" to pod elements)"
        }

        // Create backup before modifying if backup flag is enabled
        if let backupPath = try fileManager.createBackupIfNeeded(of: path, shouldBackup: options.backup) {
            logger.info("Created backup: \(backupPath)")
        }

        // Generate updated XML content
        let updatedXML = XMLParser.generateUpdatedXML(from: metadata, addNospmAttribute: metadata.hasPodspec)

        // Write updated plugin.xml
        try fileManager.writeFile(content: updatedXML, to: path, createDirectories: false)

        if options.dryRun {
            logger.info("[DRY-RUN] plugin.xml would be updated")
        } else {
            logger.success(updateMessage)
        }

        return true
    }

    private func displayFinalSummary(
        _ metadata: PluginMetadata,
        packageResult: ConversionResult,
        xmlUpdated _: Bool,
        resolvedDependencies: [ResolvedDependency]?
    ) {
        if options.dryRun {
            logger.info("Dry run completed - no files were modified")
            return
        }

        if packageResult.isSuccess {
            logger.success("Package.swift conversion completed!")
        }

        // Show appropriate message based on dependency resolution results
        if metadata.hasDependencies {
            if let resolved = resolvedDependencies {
                let resolvedCount = resolved.filter(\.isResolved).count
                let totalCount = resolved.count
                
                if resolvedCount == totalCount {
                    // All dependencies were resolved automatically
                    logger.success("Conversion completed! All dependencies were automatically resolved.")
                    logger.info("Your Package.swift is ready to use.")
                } else if resolvedCount > 0 {
                    // Some dependencies were resolved
                    userInteraction.printImportantMessage("""
                    Manual steps required:
                    \(resolvedCount) out of \(totalCount) dependencies were automatically resolved.
                    The remaining unresolved dependencies were added as comments in Package.swift.
                    Please convert them manually to Swift Package Manager equivalents.
                    """)
                } else {
                    // No dependencies were resolved
                    userInteraction.printImportantMessage("""
                    Manual steps required:
                    CocoaPods dependencies could not be automatically resolved.
                    They were added as comments in Package.swift.
                    Please convert them manually to Swift Package Manager equivalents.
                    """)
                }
            } else {
                // Auto-resolution was not used
                userInteraction.printImportantMessage("""
                Manual steps required:
                CocoaPods dependencies were added as comments in Package.swift.
                Convert them manually to Swift Package Manager equivalents.
                Tip: Use --auto-resolve flag to attempt automatic conversion.
                """)
            }
        } else {
            logger.success("Conversion completed! Your Package.swift is ready to use.")
        }
    }
    
    /// Add conditional Cordova imports to Swift files in src/ios directory
    /// - Parameter pluginDirectory: The root directory of the plugin
    /// - Returns: True if successful, false otherwise
    private func addCordovaImportsToSwiftFiles(in pluginDirectory: String) -> Bool {
        let swiftImportManager = SwiftImportManager(logger: logger, fileManager: fileManager)
        return swiftImportManager.addCordovaImports(in: pluginDirectory)
    }
}
