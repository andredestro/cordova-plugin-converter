import Foundation

/// Handles checking remote Git repositories for Package.swift files
public class GitRepositoryChecker {
    private let logger: Logger
    
    public init(logger: Logger) {
        self.logger = logger
    }
    
    /// Check if a Package.swift file exists in a remote Git repository at a specific tag/branch
    /// - Parameters:
    ///   - gitUrl: The Git repository URL
    ///   - reference: The tag, branch, or commit to check (defaults to "main")
    /// - Returns: True if Package.swift exists, false otherwise
    public func hasPackageSwift(in gitUrl: String, at reference: String = "main") async -> Bool {
        logger.debug("Checking for Package.swift in \(gitUrl) at \(reference)")
        
        // Try GitHub API first (most common case)
        if let githubResult = await checkGitHubRepository(gitUrl: gitUrl, reference: reference) {
            return githubResult
        }
        
        // Try GitLab API
        if let gitlabResult = await checkGitLabRepository(gitUrl: gitUrl, reference: reference) {
            return gitlabResult
        }
        
        // Fallback to git ls-remote + git show
        return await checkRepositoryWithGit(gitUrl: gitUrl, reference: reference)
    }
    
    /// Fetch Package.swift content from a remote Git repository
    /// - Parameters:
    ///   - gitUrl: The Git repository URL
    ///   - reference: The tag, branch, or commit to check
    /// - Returns: Package.swift content if found, nil otherwise
    public func fetchPackageSwiftContent(from gitUrl: String, at reference: String = "main") async -> String? {
        logger.debug("Fetching Package.swift content from \(gitUrl) at \(reference)")
        
        // Try GitHub API first
        if let content = await fetchFromGitHub(gitUrl: gitUrl, reference: reference) {
            return content
        }
        
        // Try GitLab API
        if let content = await fetchFromGitLab(gitUrl: gitUrl, reference: reference) {
            return content
        }
        
        // Fallback to git show
        return await fetchWithGit(gitUrl: gitUrl, reference: reference)
    }
    
    // MARK: - GitHub API Methods
    
    private func checkGitHubRepository(gitUrl: String, reference: String) async -> Bool? {
        guard let (owner, repo) = parseGitHubUrl(gitUrl) else {
            return nil
        }
        
        let apiUrl = "https://api.github.com/repos/\(owner)/\(repo)/contents/Package.swift?ref=\(reference)"
        return await makeHttpHeadRequest(to: apiUrl)
    }
    
    private func fetchFromGitHub(gitUrl: String, reference: String) async -> String? {
        guard let (owner, repo) = parseGitHubUrl(gitUrl) else {
            return nil
        }
        
        let apiUrl = "https://api.github.com/repos/\(owner)/\(repo)/contents/Package.swift?ref=\(reference)"
        return await fetchFileContentFromGitHub(apiUrl: apiUrl)
    }
    
    private func parseGitHubUrl(_ gitUrl: String) -> (owner: String, repo: String)? {
        // Handle various GitHub URL formats
        let patterns = [
            #"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$"#,
            #"^([^/]+)/([^/]+?)(?:\.git)?/?$"# // Short format like "owner/repo"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: gitUrl, options: [], range: NSRange(
                   location: 0,
                   length: gitUrl.count
               )) {
                let ownerRange = Range(match.range(at: 1), in: gitUrl)
                let repoRange = Range(match.range(at: 2), in: gitUrl)
                
                if let ownerRange, let repoRange {
                    let owner = String(gitUrl[ownerRange])
                    let repo = String(gitUrl[repoRange])
                    return (owner, repo)
                }
            }
        }
        
        return nil
    }
    
    private func fetchFileContentFromGitHub(apiUrl: String) async -> String? {
        guard let url = URL(string: apiUrl) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let contentBase64 = json["content"] as? String else {
                return nil
            }
            
            // GitHub API returns base64 encoded content
            let cleanedBase64 = contentBase64.replacingOccurrences(of: "\n", with: "")
            guard let decodedData = Data(base64Encoded: cleanedBase64),
                  let content = String(data: decodedData, encoding: .utf8) else {
                return nil
            }
            
            return content
            
        } catch {
            logger.debug("Failed to fetch from GitHub API: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - GitLab API Methods
    
    private func checkGitLabRepository(gitUrl: String, reference: String) async -> Bool? {
        guard let (host, projectPath) = parseGitLabUrl(gitUrl) else {
            return nil
        }
        
        let encodedPath = projectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectPath
        let apiUrl = "https://\(host)/api/v4/projects/\(encodedPath)/repository/files/Package.swift?ref=\(reference)"
        
        return await makeHttpHeadRequest(to: apiUrl)
    }
    
    private func fetchFromGitLab(gitUrl: String, reference: String) async -> String? {
        guard let (host, projectPath) = parseGitLabUrl(gitUrl) else {
            return nil
        }
        
        let encodedPath = projectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectPath
        let apiUrl = "https://\(host)/api/v4/projects/\(encodedPath)/repository/files/Package.swift/raw" +
            "?ref=\(reference)"
        
        return await fetchFileContent(from: apiUrl)
    }
    
    private func parseGitLabUrl(_ gitUrl: String) -> (host: String, projectPath: String)? {
        let pattern = #"([^:/]+)[:/](.+?)(?:\.git)?/?$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: gitUrl, options: [], range: NSRange(location: 0, length: gitUrl.count)) else {
            return nil
        }
        
        let hostRange = Range(match.range(at: 1), in: gitUrl)
        let pathRange = Range(match.range(at: 2), in: gitUrl)
        
        guard let hostRange, let pathRange else {
            return nil
        }
        
        let host = String(gitUrl[hostRange])
        let projectPath = String(gitUrl[pathRange])
        
        // Only handle gitlab.com for now, but could be extended
        if host.contains("gitlab") {
            return (host, projectPath)
        }
        
        return nil
    }
    
    // MARK: - Git Command Fallback Methods
    
    private func checkRepositoryWithGit(gitUrl: String, reference: String) async -> Bool {
        logger.debug("Checking repository with git command: \(gitUrl) at \(reference)")
        
        let command = "git ls-remote --exit-code \(gitUrl) \(reference) > /dev/null 2>&1 && " +
            "git archive --remote=\(gitUrl) \(reference) Package.swift > /dev/null 2>&1"
        
        return await executeCommand(command) == 0
    }
    
    private func fetchWithGit(gitUrl: String, reference: String) async -> String? {
        logger.debug("Fetching Package.swift with git command from \(gitUrl) at \(reference)")
        
        let command = "git archive --remote=\(gitUrl) \(reference) Package.swift | tar -xO"
        
        return await executeCommandWithOutput(command)
    }
    
    // MARK: - Helper Methods
    
    private func makeHttpHeadRequest(to urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10.0
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            
            return false
        } catch {
            logger.debug("HTTP HEAD request failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func fetchFileContent(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            return String(data: data, encoding: .utf8)
        } catch {
            logger.debug("Failed to fetch file content: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func executeCommand(_ command: String) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = ["bash", "-c", command]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
    
    private func executeCommandWithOutput(_ command: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = ["bash", "-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                continuation.resume(returning: output)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
