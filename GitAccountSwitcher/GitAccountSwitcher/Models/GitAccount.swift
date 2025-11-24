import Foundation

/// Represents a GitHub account configuration for switching
/// Conforms to Sendable for safe usage across actor boundaries (Swift 6 compatibility)
struct GitAccount: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var displayName: String       // e.g., "Personal", "Work"
    var githubUsername: String    // GitHub account username
    var personalAccessToken: String // PAT - NOT serialized, stored in Keychain only
    var gitUserName: String       // git config user.name
    var gitUserEmail: String      // git config user.email
    var isActive: Bool
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        githubUsername: String,
        personalAccessToken: String = "",
        gitUserName: String,
        gitUserEmail: String,
        isActive: Bool = false,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.githubUsername = githubUsername
        self.personalAccessToken = personalAccessToken
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// Creates a copy with updated active state
    func withActiveState(_ active: Bool) -> GitAccount {
        var copy = self
        copy.isActive = active
        if active {
            copy.lastUsedAt = Date()
        }
        return copy
    }
}

// MARK: - Codable (PAT excluded for security)

extension GitAccount: Codable {
    enum CodingKeys: String, CodingKey {
        case id, displayName, githubUsername, gitUserName, gitUserEmail
        case isActive, createdAt, lastUsedAt
        // personalAccessToken intentionally excluded - stored in Keychain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        githubUsername = try container.decode(String.self, forKey: .githubUsername)
        gitUserName = try container.decode(String.self, forKey: .gitUserName)
        gitUserEmail = try container.decode(String.self, forKey: .gitUserEmail)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        personalAccessToken = ""  // Never loaded from storage - retrieved from Keychain when needed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(githubUsername, forKey: .githubUsername)
        try container.encode(gitUserName, forKey: .gitUserName)
        try container.encode(gitUserEmail, forKey: .gitUserEmail)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        // personalAccessToken intentionally NOT encoded
    }
}

// MARK: - Debug String (Security)

extension GitAccount: CustomDebugStringConvertible, CustomStringConvertible {
    /// String representation that redacts sensitive token data
    var description: String {
        "GitAccount(displayName: \(displayName), username: @\(githubUsername))"
    }

    /// Debug description that shows all fields except the sensitive token
    var debugDescription: String {
        """
        GitAccount {
            id: \(id.uuidString)
            displayName: \(displayName)
            githubUsername: @\(githubUsername)
            personalAccessToken: [REDACTED]
            gitUserName: \(gitUserName)
            gitUserEmail: \(gitUserEmail)
            isActive: \(isActive)
            createdAt: \(createdAt)
            lastUsedAt: \(lastUsedAt?.description ?? "nil")
        }
        """
    }
}

// MARK: - Preview/Testing Support
extension GitAccount {
    static let preview = GitAccount(
        displayName: "Personal",
        githubUsername: "preview-user",
        personalAccessToken: "",  // SECURITY: Always empty in preview - tokens never needed for UI
        gitUserName: "Preview User",
        gitUserEmail: "preview@example.com",
        isActive: true
    )

    static let previewWork = GitAccount(
        displayName: "Work",
        githubUsername: "preview-work",
        personalAccessToken: "",  // SECURITY: Always empty in preview
        gitUserName: "Preview Work User",
        gitUserEmail: "work@example.com",
        isActive: false
    )
}
