import Foundation
import SwiftUI

/// Observable store for managing GitHub accounts
@MainActor @preconcurrency
final class AccountStore: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var accounts: [GitAccount] = [] {
        didSet {
            // PERFORMANCE: Invalidate active account cache when accounts array changes
            _cachedActiveAccount = nil
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?
    @Published private(set) var currentGitConfig: (name: String?, email: String?) = (nil, nil)

    // MARK: - Services

    private let keychainService = KeychainService.shared
    private let gitConfigService = GitConfigService.shared

    // MARK: - Concurrency Control

    /// Task handle for the current account switch operation
    /// Ensures serial execution: new switches wait for the previous to complete
    private var currentSwitchTask: Task<Void, Error>?

    // MARK: - Storage Keys

    private let accountsStorageKey = "savedAccounts"

    // MARK: - Performance Cache

    /// Cache for active account lookup to avoid O(n) search on every access
    /// Invalidated automatically via accounts.didSet
    private var _cachedActiveAccount: GitAccount?

    // MARK: - Computed Properties

    var activeAccount: GitAccount? {
        // PERFORMANCE: Cache active account lookup for O(1) access
        if let cached = _cachedActiveAccount {
            return cached
        }

        let active = accounts.first(where: { $0.isActive })
        _cachedActiveAccount = active
        return active
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    // MARK: - Initialization

    init() {
        loadAccounts()
        Task {
            await refreshCurrentGitConfig()
        }
    }

    // MARK: - Account Management

    /// Adds a new account to the store
    func addAccount(_ account: GitAccount) throws {
        // Check for duplicate GitHub username
        if accounts.contains(where: { $0.githubUsername.lowercased() == account.githubUsername.lowercased() }) {
            throw AccountStoreError.duplicateAccount(account.githubUsername)
        }

        var newAccount = account

        // Store token in keychain
        try keychainService.storeAccountToken(for: newAccount.id, token: newAccount.personalAccessToken)

        // Clear token from in-memory object (we'll retrieve from keychain when needed)
        newAccount.personalAccessToken = ""

        // If this is the first account, make it active
        if accounts.isEmpty {
            newAccount.isActive = true
        }

        accounts.append(newAccount)
        saveAccounts()
    }

    /// Updates an existing account
    func updateAccount(_ account: GitAccount) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        var updatedAccount = account

        // Update token in keychain if provided
        if !account.personalAccessToken.isEmpty {
            try keychainService.storeAccountToken(for: account.id, token: account.personalAccessToken)
            updatedAccount.personalAccessToken = ""
        }

        accounts[index] = updatedAccount
        saveAccounts()
    }

    /// Removes an account from the store
    func removeAccount(_ account: GitAccount) throws {
        // Remove token from keychain
        try keychainService.deleteAccountToken(for: account.id)

        accounts.removeAll { $0.id == account.id }
        saveAccounts()
    }

    // MARK: - Account Switching

    /// Switches to the specified account
    /// Uses task-based serialization to ensure only one switch operation runs at a time
    func switchToAccount(_ account: GitAccount) async throws {
        // Wait for any in-flight switch operation to complete
        // This provides proper serialization following Apple's concurrency best practices
        _ = try? await currentSwitchTask?.value

        // Create new switch task
        let switchTask = Task { @MainActor in
            isLoading = true
            lastError = nil

            defer {
                isLoading = false
            }

            do {
                // Retrieve token from keychain
                guard let token = try keychainService.retrieveAccountToken(for: account.id) else {
                    throw AccountStoreError.tokenNotFound
                }

                // Update GitHub Keychain credential
                try keychainService.updateGitHubCredential(
                    username: account.githubUsername,
                    token: token
                )

                // Update git config
                try await gitConfigService.setGlobalUserConfigAsync(
                    name: account.gitUserName,
                    email: account.gitUserEmail
                )

                // Update active state in store (atomic update protected by MainActor)
                for i in accounts.indices {
                    accounts[i].isActive = accounts[i].id == account.id
                    if accounts[i].id == account.id {
                        accounts[i].lastUsedAt = Date()
                    }
                }

                saveAccounts()

                // Refresh current config
                await refreshCurrentGitConfig()

            } catch {
                lastError = error
                throw error
            }
        }

        // Store task reference for serialization
        currentSwitchTask = switchTask

        // Await completion and propagate any errors
        try await switchTask.value
    }

    /// Refreshes the current git configuration
    func refreshCurrentGitConfig() async {
        do {
            currentGitConfig = try await gitConfigService.getCurrentConfigAsync()
        } catch {
            currentGitConfig = (nil, nil)
        }
    }

    // MARK: - Persistence

    private func saveAccounts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(accounts)
            UserDefaults.standard.set(data, forKey: accountsStorageKey)
        } catch {
            // ERROR HANDLING: Log encoding failure and set lastError for UI feedback
            lastError = AccountStoreError.persistenceError("Failed to save accounts: \(error.localizedDescription)")
            print("ERROR: Failed to encode accounts for persistence: \(error)")
        }
    }

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsStorageKey) else {
            // No saved data is not an error - fresh install
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            accounts = try decoder.decode([GitAccount].self, from: data)
        } catch {
            // ERROR HANDLING: Log decoding failure but don't crash - start with empty state
            lastError = AccountStoreError.persistenceError("Failed to load accounts: \(error.localizedDescription)")
            print("ERROR: Failed to decode saved accounts: \(error)")
            accounts = []
        }
    }

    // MARK: - Error Types

    enum AccountStoreError: LocalizedError {
        case tokenNotFound
        case accountNotFound
        case duplicateAccount(String)
        case persistenceError(String)

        var errorDescription: String? {
            switch self {
            case .tokenNotFound:
                return "Account token not found in keychain"
            case .accountNotFound:
                return "Account not found"
            case .duplicateAccount(let username):
                return "An account with GitHub username '\(username)' already exists"
            case .persistenceError(let message):
                return message
            }
        }
    }
}

// MARK: - Token Retrieval for Editing

extension AccountStore {

    /// Retrieves the full account with token for editing
    func getAccountWithToken(_ account: GitAccount) throws -> GitAccount {
        var fullAccount = account
        fullAccount.personalAccessToken = try keychainService.retrieveAccountToken(for: account.id) ?? ""
        return fullAccount
    }
}

// MARK: - Sync with System Keychain

extension AccountStore {

    /// Syncs accounts with current system keychain state
    func syncWithSystemKeychain() async {
        do {
            // Get current credential from system keychain
            if let credential = try keychainService.readGitHubCredential() {
                // Find matching account and mark as active
                for i in accounts.indices {
                    let isMatch = accounts[i].githubUsername.lowercased() == credential.username.lowercased()
                    if accounts[i].isActive != isMatch {
                        accounts[i].isActive = isMatch
                    }
                }
                saveAccounts()
            }
        } catch {
            // Ignore errors during sync
        }
    }
}
