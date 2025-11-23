import Foundation

/// Service for managing git configuration
final class GitConfigService {

    // MARK: - Errors

    enum GitConfigError: LocalizedError {
        case gitNotFound
        case commandFailed(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .gitNotFound:
                return "Git executable not found"
            case .commandFailed(let message):
                return "Git command failed: \(message)"
            case .parseError(let message):
                return "Parse error: \(message)"
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

    // MARK: - Git Config Operations

    /// Gets the current global user.name
    func getGlobalUserName() throws -> String? {
        try getConfig(key: "user.name", scope: .global)
    }

    /// Gets the current global user.email
    func getGlobalUserEmail() throws -> String? {
        try getConfig(key: "user.email", scope: .global)
    }

    /// Sets the global user.name
    func setGlobalUserName(_ name: String) throws {
        try setConfig(key: "user.name", value: name, scope: .global)
    }

    /// Sets the global user.email
    func setGlobalUserEmail(_ email: String) throws {
        try setConfig(key: "user.email", value: email, scope: .global)
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
        do {
            let output = try runGitCommand(["config", scope.rawValue, "--get", key])
            return output.isEmpty ? nil : output
        } catch GitConfigError.commandFailed {
            // git config --get returns exit code 1 if key not found
            return nil
        }
    }

    private func setConfig(key: String, value: String, scope: ConfigScope) throws {
        _ = try runGitCommand(["config", scope.rawValue, key, value])
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
            throw GitConfigError.commandFailed(stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr)
        }

        return stdout
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
