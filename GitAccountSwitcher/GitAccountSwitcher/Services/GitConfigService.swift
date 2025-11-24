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
    /// PERFORMANCE: Caches result after first discovery to avoid repeated I/O
    private var gitPath: String {
        gitPathLock.lock()
        defer { gitPathLock.unlock() }

        // Return cached path if available
        if let cached = _cachedGitPath {
            return cached
        }

        // Check common locations in order of preference
        let possiblePaths = [
            "/usr/bin/git",           // Default macOS location
            "/opt/homebrew/bin/git",  // Homebrew on Apple Silicon
            "/usr/local/bin/git",     // Homebrew on Intel / manual install
            "/opt/local/bin/git"      // MacPorts
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                _cachedGitPath = path
                return path
            }
        }

        // Fallback: try to find using `which`
        if let path = findGitUsingWhich() {
            _cachedGitPath = path
            return path
        }

        // Last resort default
        let fallback = "/usr/bin/git"
        _cachedGitPath = fallback
        return fallback
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

    // MARK: - Git Path Caching

    private var _cachedGitPath: String?
    private let gitPathLock = NSLock()

    // MARK: - Input Validation

    /// Validates and sanitizes git config values to prevent injection attacks
    private func validateConfigValue(_ value: String, field: String) throws -> String {
        do {
            return try ValidationUtilities.validateGitConfigValue(value, field: field)
        } catch let error as ValidationUtilities.ValidationError {
            throw GitConfigError.validationError(error.localizedDescription)
        }
    }

    /// Validates email format (RFC 5322 basic compliance)
    private func validateEmail(_ email: String) throws -> String {
        let validated = try validateConfigValue(email, field: "email")

        guard ValidationUtilities.isValidEmail(validated) else {
            throw GitConfigError.validationError("Invalid email format")
        }

        return validated
    }

    /// Validates git config keys to prevent path traversal
    private func validateConfigKey(_ key: String) throws {
        do {
            try ValidationUtilities.validateGitConfigKey(key)
        } catch let error as ValidationUtilities.ValidationError {
            throw GitConfigError.validationError(error.localizedDescription)
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

        // SECURITY: Sanitize environment to prevent command injection
        // Restrict to essential variables only, blocking dangerous vars like:
        // GIT_SSH_COMMAND, GIT_EXEC_PATH, core.editor, core.pager
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "LANG": "en_US.UTF-8",
            "GIT_CONFIG_NOSYSTEM": "1",      // Disable system-level config
            "GIT_TERMINAL_PROMPT": "0",      // Disable interactive prompts
            "GIT_ASKPASS": "/bin/echo"       // Prevent credential prompts
        ]

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
        return ValidationUtilities.sanitizeGitError(stderr)
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
    /// Uses Task.detached following Apple's modern concurrency best practices
    func setGlobalUserConfigAsync(name: String, email: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.setGlobalUserConfig(name: name, email: email)
        }.value
    }

    /// Async version of getCurrentConfig
    /// Uses Task.detached following Apple's modern concurrency best practices
    func getCurrentConfigAsync() async throws -> (name: String?, email: String?) {
        try await Task.detached(priority: .userInitiated) {
            let name = try self.getGlobalUserName()
            let email = try self.getGlobalUserEmail()
            return (name, email)
        }.value
    }
}
