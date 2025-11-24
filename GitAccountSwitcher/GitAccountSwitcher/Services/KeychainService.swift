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

    /// Requests biometric authentication before accessing sensitive Keychain items
    /// SECURITY: Adds an extra layer of protection for token retrieval
    private func authenticateWithBiometrics(reason: String) async throws {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fallback to password authentication if biometrics not available
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw KeychainError.biometricAuthFailed("Authentication not available: \(error?.localizedDescription ?? "unknown error")")
            }

            // Use device password as fallback
            do {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            } catch {
                throw KeychainError.biometricAuthFailed("Password authentication failed: \(error.localizedDescription)")
            }
            return
        }

        // Evaluate biometric policy
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            throw KeychainError.biometricAuthFailed(error.localizedDescription)
        }
    }

    // MARK: - Read GitHub Credential

    /// Reads the current GitHub credential from Keychain
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

    // MARK: - Update/Add GitHub Credential

    /// Updates or adds GitHub credential in Keychain
    /// - Parameters:
    ///   - username: GitHub username
    ///   - token: Personal Access Token
    func updateGitHubCredential(username: String, token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try to add first (most common case for new installs)
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

        if addStatus == errSecSuccess {
            return // Successfully added
        }

        // If duplicate exists, update instead
        if addStatus == errSecDuplicateItem {
            try updateExistingGitHubCredential(username: username, tokenData: tokenData)
            return
        }

        // Unexpected error
        throw KeychainError.unexpectedStatus(addStatus)
    }

    /// Helper to update an existing GitHub credential
    private func updateExistingGitHubCredential(username: String, tokenData: Data) throws {
        // Query must include account to update the correct entry
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: username
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: tokenData,
            kSecAttrLabel as String: "github.com (\(username))",
            kSecAttrComment as String: "GitHub Personal Access Token - Managed by GitAccountSwitcher",
            // SECURITY: Maintain security attributes on update
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        guard updateStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    // MARK: - Delete GitHub Credential

    /// Deletes a specific GitHub credential from Keychain
    /// - Parameter username: GitHub username to delete
    func deleteGitHubCredential(username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: username
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes all GitHub credentials from Keychain
    func deleteAllGitHubCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
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

// MARK: - App-specific Keychain Storage

extension KeychainService {

    private static let appService = "com.gitaccountswitcher.accounts"

    /// Stores account tokens securely in app's own Keychain entries
    /// These are stored separately from the GitHub Keychain entry
    func storeAccountToken(for accountId: UUID, token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.appService,
            kSecAttrAccount as String: accountId.uuidString
        ]

        // Try to add first with security attributes
        var addQuery = query
        addQuery[kSecValueData as String] = tokenData
        addQuery[kSecAttrLabel as String] = "GitAccountSwitcher (\(accountId.uuidString.prefix(8)))"
        addQuery[kSecAttrComment as String] = "GitHub Personal Access Token - Managed by GitAccountSwitcher"
        // SECURITY: Only accessible when device is unlocked, non-migratable
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // SECURITY: Prevent iCloud Keychain sync - tokens stay local
        addQuery[kSecAttrSynchronizable as String] = false

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            return // Successfully added
        }

        // If duplicate, try to update instead
        if addStatus == errSecDuplicateItem {
            let updateAttributes: [String: Any] = [
                kSecValueData as String: tokenData,
                kSecAttrLabel as String: "GitAccountSwitcher (\(accountId.uuidString.prefix(8)))",
                kSecAttrComment as String: "GitHub Personal Access Token - Managed by GitAccountSwitcher",
                // SECURITY: Maintain security attributes on update
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrSynchronizable as String: false
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }

        // Unexpected error
        throw KeychainError.unexpectedStatus(addStatus)
    }

    /// Retrieves account token from app's Keychain storage
    func retrieveAccountToken(for accountId: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.appService,
            kSecAttrAccount as String: accountId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return token
    }

    /// Retrieves account token with biometric authentication (async version)
    /// SECURITY: Requires biometric or device password authentication before token retrieval
    func retrieveAccountTokenWithAuth(for accountId: UUID) async throws -> String? {
        // SECURITY: Request biometric authentication before accessing token
        try await authenticateWithBiometrics(reason: "Authenticate to access GitHub account token")

        // After successful authentication, retrieve token
        return try retrieveAccountToken(for: accountId)
    }

    /// Deletes account token from app's Keychain storage
    func deleteAccountToken(for accountId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.appService,
            kSecAttrAccount as String: accountId.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
