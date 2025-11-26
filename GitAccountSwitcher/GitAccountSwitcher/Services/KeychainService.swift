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
    /// - Parameters:
    ///   - username: GitHub username for current account
    ///   - token: Personal Access Token for current account
    func updateGitHubCredential(username: String, token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // First, try to update existing entry (most common after first setup)
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
            // NOTE: No kSecAttrAccount in query - we update THE entry for github.com
        ]

        let updateAttributes: [String: Any] = [
            kSecAttrAccount as String: username,  // Update username
            kSecValueData as String: tokenData,    // Update password (token)
            kSecAttrLabel as String: "github.com (\(username))",
            kSecAttrComment as String: "GitHub Personal Access Token - Managed by GitAccountSwitcher",
            // SECURITY: Maintain security attributes on update
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return // Successfully updated
        }

        // If no entry exists, create it (first-time setup)
        if updateStatus == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: githubServer,
                kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
                kSecAttrAccount as String: username,
                kSecValueData as String: tokenData,
                kSecAttrLabel as String: "github.com (\(username))",
                kSecAttrComment as String: "GitHub Personal Access Token - Managed by GitAccountSwitcher",
                // SECURITY: Only accessible when device is unlocked, non-migratable
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                // SECURITY: Prevent iCloud Keychain sync - tokens stay local
                kSecAttrSynchronizable as String: false
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        // Unexpected error
        throw KeychainError.unexpectedStatus(updateStatus)
    }

    // MARK: - Delete GitHub Credential

    /// Deletes THE SINGLE GitHub credential from Keychain
    /// Call this when deleting the active account or when app needs to clear credentials
    func deleteGitHubCredential() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
            // NOTE: No kSecAttrAccount - we delete THE entry for github.com
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
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
