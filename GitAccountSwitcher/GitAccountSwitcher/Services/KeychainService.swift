import Foundation
import Security
import LocalAuthentication

/// Service for managing GitHub credentials in macOS Keychain
final class KeychainService {

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case invalidData
        case encodingFailed
        case biometricAuthFailed(String)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Keychain item not found"
            case .duplicateItem:
                return "Keychain item already exists"
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error: \(status)"
            case .invalidData:
                return "Invalid data format"
            case .encodingFailed:
                return "Failed to encode data"
            case .biometricAuthFailed(let message):
                return "Biometric authentication failed: \(message)"
            }
        }
    }

    // MARK: - Constants

    private let githubServer = "github.com"

    // MARK: - Singleton

    static let shared = KeychainService()
    private init() {}

    // MARK: - Biometric Authentication

    /// Authentication method available on the device
    enum AuthMethod {
        case touchID
        case faceID
        case opticID
        case password
        case none

        var displayName: String {
            switch self {
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .opticID: return "Optic ID"
            case .password: return "Password"
            case .none: return "None"
            }
        }
    }

    /// Returns the available authentication method on this device
    func availableAuthMethod() -> AuthMethod {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .touchID:
                return .touchID
            case .faceID:
                return .faceID
            case .opticID:
                return .opticID
            case .none:
                return .password
            @unknown default:
                return .password
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .password
        }

        return .none
    }

    /// Requests biometric authentication before accessing sensitive Keychain items
    /// SECURITY: Adds an extra layer of protection for token retrieval
    /// - Parameter reason: The reason displayed to the user for authentication
    /// - Returns: True if authentication succeeded
    func authenticateWithBiometrics(reason: String) async throws {
        let context = LAContext()
        var error: NSError?

        // Configure context for better UX
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"

        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Try biometric authentication first
            do {
                try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
                return // Success
            } catch let authError as LAError {
                // If user chose fallback or biometrics failed, try password
                if authError.code == .userFallback || authError.code == .biometryLockout {
                    try await authenticateWithPassword(context: context, reason: reason)
                    return
                }
                // User cancelled or other error
                throw KeychainError.biometricAuthFailed(authError.localizedDescription)
            }
        }

        // Biometrics not available, try password authentication
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw KeychainError.biometricAuthFailed(
                "Authentication not available: \(error?.localizedDescription ?? "unknown error")"
            )
        }

        try await authenticateWithPassword(context: context, reason: reason)
    }

    /// Authenticates using device password
    private func authenticateWithPassword(context: LAContext, reason: String) async throws {
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw KeychainError.biometricAuthFailed("Password authentication failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Read GitHub Credential (with Biometric Auth)

    /// Reads the current GitHub credential from Keychain with biometric authentication
    /// SECURITY: Requires Touch ID, Face ID, or password before returning sensitive token data
    /// - Parameter reason: The reason displayed to the user for authentication
    /// - Returns: Tuple of (username, token) if found and authenticated
    func readGitHubCredentialWithAuth(reason: String = "Access GitHub credentials") async throws -> (username: String, token: String)? {
        // First authenticate with biometrics/password
        try await authenticateWithBiometrics(reason: reason)

        // Then read the credential
        return try readGitHubCredential()
    }

    /// Reads the current GitHub credential from Keychain (no authentication required)
    /// - Returns: Tuple of (username, token) if found
    func readGitHubCredential() throws -> (username: String, token: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let dict = result as? [String: Any],
              let account = dict[kSecAttrAccount as String] as? String,
              let passwordData = dict[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return (account, password)
    }

    /// Reads all GitHub credentials from Keychain
    /// - Returns: Array of (username, token) tuples
    func readAllGitHubCredentials() throws -> [(username: String, token: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict in
            guard let account = dict[kSecAttrAccount as String] as? String,
                  let passwordData = dict[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: .utf8) else {
                return nil
            }
            return (account, password)
        }
    }

    // MARK: - Update/Add GitHub Credential (Single Entry)

    /// Updates or adds THE SINGLE GitHub credential in Keychain
    /// This app maintains only ONE github.com entry that gets updated on account switch
    /// Uses the exact format that git credential-osxkeychain expects
    /// - Parameters:
    ///   - username: GitHub username for current account
    ///   - token: Personal Access Token for current account
    func updateGitHubCredential(username: String, token: String) throws {
        // First, delete any existing github.com credential to ensure clean state
        // This is the most reliable approach as git credential-osxkeychain
        // expects a specific format that may conflict with Security framework defaults
        try? deleteGitHubCredential()

        // Use git credential-osxkeychain store to add the credential
        // This ensures the format is exactly what git expects
        try storeCredentialUsingGit(username: username, token: token)
    }

    /// Stores credential using git credential-osxkeychain for perfect compatibility
    private func storeCredentialUsingGit(username: String, token: String) throws {
        try runGitCredentialCommand(
            action: "store",
            input: """
            protocol=https
            host=github.com
            username=\(username)
            password=\(token)

            """
        )
    }

    /// Runs a git credential-osxkeychain command with the given action and input
    private func runGitCredentialCommand(action: String, input: String) throws {
        let process = Process()
        let inputPipe = Pipe()

        // Use GitConfigService's validated git path (includes code signature verification)
        let gitPath: String
        do {
            gitPath = try GitConfigService.shared.getValidatedGitPath()
        } catch {
            // Fallback to standard path if GitConfigService fails
            gitPath = "/usr/bin/git"
        }

        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["credential-osxkeychain", action]
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Sanitize environment (matches GitConfigService pattern)
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8"
        ]

        do {
            try process.run()

            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                try? inputPipe.fileHandleForWriting.close()
            }

            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw KeychainError.unexpectedStatus(OSStatus(process.terminationStatus))
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.unexpectedStatus(-1)
        }
    }

    // MARK: - Delete GitHub Credential

    /// Deletes THE SINGLE GitHub credential from Keychain
    /// Call this when deleting the active account or when app needs to clear credentials
    func deleteGitHubCredential() throws {
        // Use git credential-osxkeychain erase for proper cleanup
        eraseCredentialUsingGit()

        // Also try Security framework delete as backup
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Erases credential using git credential-osxkeychain for proper cleanup
    private func eraseCredentialUsingGit() {
        // Use the same helper as storeCredentialUsingGit for consistency
        // Ignore errors since credential might not exist
        try? runGitCredentialCommand(
            action: "erase",
            input: """
            protocol=https
            host=github.com

            """
        )
    }

    // MARK: - Verify Credential

    /// Checks if a GitHub credential exists in Keychain
    /// - Parameter username: Optional username to check for specific account
    /// - Returns: True if credential exists
    func hasGitHubCredential(for username: String? = nil) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let username = username {
            query[kSecAttrAccount as String] = username
        }

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - App-specific Keychain Storage (DEPRECATED - PATs now stored in UserDefaults)
//
// This code is kept for reference but is NO LONGER USED.
// PATs are now stored directly in the GitAccount model (saved to UserDefaults).
// Only ONE github.com Keychain entry is maintained and updated on account switch.
