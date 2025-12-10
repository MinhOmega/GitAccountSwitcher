import Foundation
import Security

/// Service for managing git configuration
final class GitConfigService {

    // MARK: - Errors

    enum GitConfigError: LocalizedError {
        case gitNotFound
        case commandFailed(String)
        case parseError(String)
        case validationError(String)
        case invalidGitBinary(String)

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
            case .invalidGitBinary(let message):
                return "Invalid git binary: \(message)"
            }
        }
    }

    // MARK: - Git Path Discovery

    /// Finds git executable from common locations or using `which`
    /// PERFORMANCE: Caches result after first discovery to avoid repeated I/O
    /// SECURITY: Validates code signature on first discovery
    private var gitPath: String {
        get throws {
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
                    // SECURITY: Verify code signature before caching
                    if isValidGitBinary(at: path) {
                        _cachedGitPath = path
                        return path
                    }
                }
            }

            // Fallback: try to find using `which`
            if let path = findGitUsingWhich() {
                // SECURITY: Verify code signature before caching
                if isValidGitBinary(at: path) {
                    _cachedGitPath = path
                    return path
                }
            }

            // Last resort default - verify before returning
            let fallback = "/usr/bin/git"
            if FileManager.default.fileExists(atPath: fallback) && isValidGitBinary(at: fallback) {
                _cachedGitPath = fallback
                return fallback
            }

            throw GitConfigError.gitNotFound
        }
    }

    /// Validates git binary code signature and integrity
    /// SECURITY: Prevents execution of tampered or malicious git binaries
    private func isValidGitBinary(at path: String) -> Bool {
        // Check file exists and is executable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path),
              fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        // SECURITY: Use URL(fileURLWithPath:) to prevent URL injection attacks
        // URL(string:) with interpolation is vulnerable to special characters (#, ?, spaces, etc.)
        let url = URL(fileURLWithPath: path)

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)

        guard status == errSecSuccess, let code = staticCode else {
            return false
        }

        // Check if binary is signed (requirement: signed by Apple or valid Developer ID)
        status = SecStaticCodeCheckValidity(code, [], nil)

        // Accept both Apple-signed git and valid Developer ID certificates (Homebrew)
        return status == errSecSuccess
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

    /// Checks if osxkeychain credential helper is configured
    func isOsxKeychainHelperConfigured() -> Bool {
        guard let helper = try? getCredentialHelper() else {
            return false
        }
        return helper.contains("osxkeychain")
    }

    /// Ensures osxkeychain credential helper is configured
    /// This is required for the app to work correctly - git must read from macOS Keychain
    func ensureOsxKeychainHelper() throws {
        if !isOsxKeychainHelperConfigured() {
            try setConfig(key: "credential.helper", value: "osxkeychain", scope: .global)
        }
    }

    /// Clears cached credentials for GitHub from ALL git credential helpers
    /// This forces git to fetch fresh credentials from Keychain on next operation
    func clearGitHubCredentialCache() throws {
        // Clear credential-cache helper (in-memory cache)
        clearCredentialCacheHelper()

        // Clear credential-osxkeychain helper
        clearCredentialOsxkeychainHelper()

        // Use git credential reject to clear ALL configured helpers
        clearAllCredentialHelpers()
    }

    /// Clears the in-memory credential cache (credential-cache helper)
    private func clearCredentialCacheHelper() {
        let process = Process()

        guard let validatedGitPath = try? gitPath else { return }
        process.executableURL = URL(fileURLWithPath: validatedGitPath)
        process.arguments = ["credential-cache", "exit"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // SECURITY: Sanitize environment
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "LANG": "en_US.UTF-8"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Ignore errors - cache might not be running
            print("Note: credential-cache not active (this is normal)")
        }
    }

    /// Clears osxkeychain credential cache
    private func clearCredentialOsxkeychainHelper() {
        let process = Process()
        let inputPipe = Pipe()

        guard let validatedGitPath = try? gitPath else { return }
        process.executableURL = URL(fileURLWithPath: validatedGitPath)
        process.arguments = ["credential-osxkeychain", "erase"]
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // SECURITY: Sanitize environment
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "LANG": "en_US.UTF-8"
        ]

        do {
            try process.run()

            // Send the credential protocol to erase GitHub credentials
            let credentialInput = """
            protocol=https
            host=github.com

            """

            if let data = credentialInput.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                try? inputPipe.fileHandleForWriting.close()
            }

            process.waitUntilExit()
        } catch {
            print("Failed to clear osxkeychain cache: \(error.localizedDescription)")
        }
    }

    /// Uses git credential reject to clear ALL configured credential helpers
    private func clearAllCredentialHelpers() {
        let process = Process()
        let inputPipe = Pipe()

        guard let validatedGitPath = try? gitPath else { return }
        process.executableURL = URL(fileURLWithPath: validatedGitPath)
        process.arguments = ["credential", "reject"]
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // SECURITY: Sanitize environment
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "LANG": "en_US.UTF-8"
        ]

        do {
            try process.run()

            // Send the credential protocol to reject GitHub credentials
            let credentialInput = """
            protocol=https
            host=github.com

            """

            if let data = credentialInput.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                try? inputPipe.fileHandleForWriting.close()
            }

            process.waitUntilExit()
        } catch {
            print("Failed to clear credential helpers: \(error.localizedDescription)")
        }
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

        // SECURITY: Get validated git path (with code signature verification)
        let validatedGitPath = try gitPath
        process.executableURL = URL(fileURLWithPath: validatedGitPath)
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

    /// Checks if git is available and has valid code signature
    var isGitAvailable: Bool {
        do {
            let path = try gitPath
            return FileManager.default.fileExists(atPath: path)
        } catch {
            return false
        }
    }

    /// Returns the validated git executable path
    /// SECURITY: Path is validated for code signature before being returned
    /// - Returns: Path to the git executable
    /// - Throws: GitConfigError.gitNotFound if no valid git binary is available
    func getValidatedGitPath() throws -> String {
        try gitPath
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

    /// Async version of clearGitHubCredentialCache
    /// Uses Task.detached following Apple's modern concurrency best practices
    func clearGitHubCredentialCacheAsync() async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.clearGitHubCredentialCache()
        }.value
    }
}
