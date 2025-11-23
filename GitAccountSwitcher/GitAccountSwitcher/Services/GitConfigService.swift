import Foundation

/// Service for managing git configuration
final class GitConfigService {

    // MARK: - Errors

    enum GitConfigError: LocalizedError {
        case gitNotFound
        case commandFailed(String)
        case parseError(String)
        case validationError(String)

        var errorDescription: String? {
            switch self {
            case .gitNotFound:
                return "Git executable not found"
            case .commandFailed(let message):
                return "Git command failed: \(message)"
            case .parseError(let message):
                return "Parse error: \(message)"
            case .validationError(let message):
                return "Validation error: \(message)"
            }
        }
    }

    // MARK: - Git Path Discovery

    /// Finds git executable from common locations or using `which`
    private var gitPath: String {
        // Check common locations in order of preference
        let possiblePaths = [
            "/usr/bin/git",           // Default macOS location
            "/opt/homebrew/bin/git",  // Homebrew on Apple Silicon
            "/usr/local/bin/git",     // Homebrew on Intel / manual install
            "/opt/local/bin/git"      // MacPorts
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fallback: try to find using `which`
        if let path = findGitUsingWhich() {
            return path
        }

        // Last resort default
        return "/usr/bin/git"
    }

    private func findGitUsingWhich() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Ignore errors
        }
        return nil
    }

    // MARK: - Singleton

    static let shared = GitConfigService()
    private init() {}

    // MARK: - Input Validation

    /// Validates and sanitizes git config values to prevent injection attacks
    private func validateConfigValue(_ value: String, field: String) throws -> String {
        // SECURITY: Check for control characters (including newlines, tabs, null bytes)
        // These could be used to inject arbitrary git configuration
        let controlCharacters = CharacterSet.controlCharacters
        if value.rangeOfCharacter(from: controlCharacters) != nil {
            throw GitConfigError.validationError("\(field) contains invalid control characters")
        }

        // SECURITY: Check for git special characters that could affect config parsing
        let dangerousChars = CharacterSet(charactersIn: "[]")
        if value.rangeOfCharacter(from: dangerousChars) != nil {
            throw GitConfigError.validationError("\(field) contains invalid characters")
        }

        // Enforce reasonable length limits (git config has internal limits)
        guard value.count <= 255 else {
            throw GitConfigError.validationError("\(field) exceeds maximum length (255 characters)")
        }

        // Must not be empty or only whitespace
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw GitConfigError.validationError("\(field) cannot be empty")
        }

        return value
    }

    /// Validates email format (RFC 5322 basic compliance)
    private func validateEmail(_ email: String) throws -> String {
        let validated = try validateConfigValue(email, field: "email")

        // Basic email regex validation
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)

        guard emailPredicate.evaluate(with: validated) else {
            throw GitConfigError.validationError("Invalid email format")
        }

        return validated
    }

    /// Validates git config keys to prevent path traversal
    private func validateConfigKey(_ key: String) throws {
        // Git config key format: section.subsection.key
        let keyRegex = #"^[a-zA-Z][a-zA-Z0-9-]*(\.[a-zA-Z][a-zA-Z0-9-]*)*$"#
        let keyPredicate = NSPredicate(format: "SELF MATCHES %@", keyRegex)

        guard keyPredicate.evaluate(with: key) else {
            throw GitConfigError.validationError("Invalid config key format")
        }

        // SECURITY: Prevent path traversal attempts
        guard !key.contains("..") && !key.contains("/") && !key.contains("\\") else {
            throw GitConfigError.validationError("Config key contains invalid path characters")
        }
    }

    // MARK: - Git Config Operations

    /// Gets the current global user.name
    func getGlobalUserName() throws -> String? {
        try getConfig(key: "user.name", scope: .global)
    }

    /// Gets the current global user.email
    func getGlobalUserEmail() throws -> String? {
        try getConfig(key: "user.email", scope: .global)
    }

    /// Sets the global user.name with validation
    func setGlobalUserName(_ name: String) throws {
        let validatedName = try validateConfigValue(name, field: "user.name")
        try setConfig(key: "user.name", value: validatedName, scope: .global)
    }

    /// Sets the global user.email with validation
    func setGlobalUserEmail(_ email: String) throws {
        let validatedEmail = try validateEmail(email)
        try setConfig(key: "user.email", value: validatedEmail, scope: .global)
    }

    /// Sets both user.name and user.email atomically
    func setGlobalUserConfig(name: String, email: String) throws {
        try setGlobalUserName(name)
        try setGlobalUserEmail(email)
    }

    /// Gets the current credential helper
    func getCredentialHelper() throws -> String? {
        try getConfig(key: "credential.helper", scope: .global)
    }

    /// Lists all global config values
    func listGlobalConfig() throws -> [String: String] {
        let output = try runGitCommand(["config", "--global", "--list"])
        var result: [String: String] = [:]

        for line in output.components(separatedBy: .newlines) {
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separatorIndex])
            let value = String(line[line.index(after: separatorIndex)...])
            result[key] = value
        }

        return result
    }

    // MARK: - Private Helpers

    enum ConfigScope: String {
        case system = "--system"
        case global = "--global"
        case local = "--local"
    }

    private func getConfig(key: String, scope: ConfigScope) throws -> String? {
        try validateConfigKey(key)

        do {
            let output = try runGitCommand(["config", scope.rawValue, "--get", key])
            return output.isEmpty ? nil : output
        } catch GitConfigError.commandFailed {
            // git config --get returns exit code 1 if key not found
            return nil
        }
    }

    private func setConfig(key: String, value: String, scope: ConfigScope) throws {
        try validateConfigKey(key)
        _ = try runGitCommand(["config", scope.rawValue, "--replace-all", key, value])
    }

    @discardableResult
    private func runGitCommand(_ arguments: [String]) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GitConfigError.gitNotFound
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let sanitizedError = sanitizeGitError(stderr, arguments: arguments)
            throw GitConfigError.commandFailed(sanitizedError)
        }

        return stdout
    }

    /// Sanitizes git error messages to prevent information disclosure
    private func sanitizeGitError(_ stderr: String, arguments: [String]) -> String {
        if stderr.isEmpty {
            return "Git command failed"
        }

        // SECURITY: Remove file paths that could leak system information
        var sanitized = stderr.replacingOccurrences(
            of: #"/Users/[^/\s']+"#,
            with: "[HOME]",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: #"~[^/\s']*"#,
            with: "[HOME]",
            options: .regularExpression
        )

        // Return generic messages for common errors
        if sanitized.contains("permission denied") {
            return "Permission denied accessing git config"
        }
        if sanitized.contains("not found") {
            return "Git config key not found"
        }

        // Generic error with command context
        return "Git config operation failed"
    }
}

// MARK: - Git Config File Paths

extension GitConfigService {

    /// Returns the path to the global git config file
    var globalConfigPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitconfig")
    }

    /// Returns the path to the XDG config location
    var xdgConfigPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/git/config")
    }

    /// Checks if git is available
    var isGitAvailable: Bool {
        FileManager.default.fileExists(atPath: gitPath)
    }

    /// Gets the git version
    func getGitVersion() -> String? {
        try? runGitCommand(["--version"])
    }
}

// MARK: - Async Support

extension GitConfigService {

    /// Async version of setGlobalUserConfig
    func setGlobalUserConfigAsync(name: String, email: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.setGlobalUserConfig(name: name, email: email)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Async version of getCurrentConfig
    func getCurrentConfigAsync() async throws -> (name: String?, email: String?) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let name = try self.getGlobalUserName()
                    let email = try self.getGlobalUserEmail()
                    continuation.resume(returning: (name, email))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
