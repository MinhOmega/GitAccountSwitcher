import Foundation
import Security

/// Service for managing GitHub CLI (gh) operations
final class GitHubCLIService {

    // MARK: - Errors

    enum GitHubCLIError: LocalizedError {
        case cliNotInstalled
        case commandFailed(String)
        case notLoggedIn
        case accountNotFound(String)
        case invalidBinary(String)

        var errorDescription: String? {
            switch self {
            case .cliNotInstalled:
                return "GitHub CLI (gh) is not installed"
            case .commandFailed(let message):
                return "GitHub CLI command failed: \(message)"
            case .notLoggedIn:
                return "Not logged in to GitHub CLI"
            case .accountNotFound(let username):
                return "Account '\(username)' not found in GitHub CLI"
            case .invalidBinary(let message):
                return "Invalid GitHub CLI binary: \(message)"
            }
        }
    }

    // MARK: - Singleton

    static let shared = GitHubCLIService()
    private init() {}

    // MARK: - CLI Path Discovery

    private var _cachedGhPath: String?
    private let ghPathLock = NSLock()

    /// Finds gh executable from common locations
    /// SECURITY: Validates code signature on first discovery
    private var ghPath: String? {
        ghPathLock.lock()
        defer { ghPathLock.unlock() }

        // Return cached path if available
        if let cached = _cachedGhPath {
            return cached
        }

        // Check common locations in order of preference
        let possiblePaths = [
            "/opt/homebrew/bin/gh",   // Homebrew on Apple Silicon
            "/usr/local/bin/gh",      // Homebrew on Intel / manual install
            "/usr/bin/gh",            // System location (rare)
            "/opt/local/bin/gh"       // MacPorts
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                if isValidGhBinary(at: path) {
                    _cachedGhPath = path
                    return path
                }
            }
        }

        // Fallback: try to find using `which`
        if let path = findGhUsingWhich() {
            if isValidGhBinary(at: path) {
                _cachedGhPath = path
                return path
            }
        }

        return nil
    }

    /// Validates gh binary code signature and integrity
    private func isValidGhBinary(at path: String) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path),
              fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        // SECURITY: Use URL(fileURLWithPath:) to prevent URL injection
        let url = URL(fileURLWithPath: path)

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)

        guard status == errSecSuccess, let code = staticCode else {
            // Allow unsigned binaries from trusted locations (Homebrew)
            // Homebrew binaries may not be code-signed
            let trustedPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
            return trustedPaths.contains(path)
        }

        status = SecStaticCodeCheckValidity(code, [], nil)
        return status == errSecSuccess
    }

    private func findGhUsingWhich() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gh"]
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

    // MARK: - Public Properties

    /// Checks if GitHub CLI is installed
    var isInstalled: Bool {
        ghPath != nil
    }

    /// Returns the installation command for GitHub CLI
    var installCommand: String {
        "brew install gh"
    }

    /// Returns the login command for GitHub CLI
    var loginCommand: String {
        "gh auth login"
    }

    /// Returns the auth status command
    var authStatusCommand: String {
        "gh auth status"
    }

    // MARK: - Status Checking

    /// Combined status check for CLI installation and login state
    /// Returns (isInstalled: Bool, isLoggedIn: Bool)
    func checkFullStatus() async -> (isInstalled: Bool, isLoggedIn: Bool) {
        let installed = isInstalled
        guard installed else {
            return (false, false)
        }
        let loggedIn = await isLoggedIn()
        return (installed, loggedIn)
    }

    // MARK: - CLI Operations

    /// Checks if user is logged in to GitHub CLI
    func isLoggedIn() async -> Bool {
        guard let path = ghPath else { return false }

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["auth", "status"]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Sanitize environment
            process.environment = [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
                "LANG": "en_US.UTF-8"
            ]

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    /// Gets the list of authenticated accounts in GitHub CLI
    func getAuthenticatedAccounts() async throws -> [String] {
        guard let path = ghPath else {
            throw GitHubCLIError.cliNotInstalled
        }

        return try await Task.detached(priority: .userInitiated) {
            let output = try self.runGhCommand(path: path, arguments: ["auth", "status"])

            // Parse output to find usernames
            // Format: "Logged in to github.com account username (keyring)"
            var accounts: [String] = []
            for line in output.components(separatedBy: .newlines) {
                if line.contains("Logged in to") && line.contains("account") {
                    // Extract username from line
                    let components = line.components(separatedBy: " ")
                    if let accountIndex = components.firstIndex(of: "account"),
                       accountIndex + 1 < components.count {
                        let username = components[accountIndex + 1].trimmingCharacters(in: .punctuationCharacters)
                        accounts.append(username)
                    }
                }
            }

            return accounts
        }.value
    }

    /// Switches to the specified GitHub account using gh auth switch
    /// - Parameter username: The GitHub username to switch to
    func switchAccount(to username: String) async throws {
        guard let path = ghPath else {
            throw GitHubCLIError.cliNotInstalled
        }

        try await Task.detached(priority: .userInitiated) {
            // First check if user is logged in
            let isLoggedIn = try? self.runGhCommand(path: path, arguments: ["auth", "status"])
            guard isLoggedIn != nil else {
                throw GitHubCLIError.notLoggedIn
            }

            // Run gh auth switch --user <username>
            do {
                _ = try self.runGhCommand(path: path, arguments: ["auth", "switch", "--user", username])
            } catch GitHubCLIError.commandFailed(let message) {
                // Check if the error is because account not found
                if message.contains("not found") || message.contains("no accounts") {
                    throw GitHubCLIError.accountNotFound(username)
                }
                throw GitHubCLIError.commandFailed(message)
            }
        }.value
    }

    /// Opens Terminal to run gh auth login
    func openTerminalForLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "gh auth login"
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
    }

    /// Opens Terminal to install gh via Homebrew
    func openTerminalForInstall() {
        let script = """
        tell application "Terminal"
            activate
            do script "brew install gh && gh auth login"
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
    }

    // MARK: - Private Helpers

    @discardableResult
    private func runGhCommand(path: String, arguments: [String]) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Sanitize environment
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8",
            "GH_NO_UPDATE_NOTIFIER": "1"  // Disable update notifications
        ]

        do {
            try process.run()
        } catch {
            throw GitHubCLIError.cliNotInstalled
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // gh auth status returns exit code 1 when not logged in but still provides useful output
        if process.terminationStatus != 0 && !stdout.isEmpty {
            // Return stdout even if exit code is non-zero (for auth status parsing)
            return stdout + "\n" + stderr
        }

        guard process.terminationStatus == 0 else {
            throw GitHubCLIError.commandFailed(stderr.isEmpty ? "Unknown error" : stderr)
        }

        return stdout
    }
}
