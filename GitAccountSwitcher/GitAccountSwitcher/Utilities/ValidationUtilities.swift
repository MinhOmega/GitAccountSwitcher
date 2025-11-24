import Foundation

/// Centralized validation utilities for input validation and security
enum ValidationUtilities {

    // MARK: - Email Validation

    /// Validates email format with strict rules
    /// - Prevents leading/trailing dots
    /// - Prevents consecutive dots
    /// - Requires 2+ character TLD
    /// - Parameter email: Email address to validate
    /// - Returns: True if email is valid
    static func isValidEmail(_ email: String) -> Bool {
        // Email validation: prevents leading/trailing dots, consecutive dots, single-char TLDs
        let emailRegex = #"^[a-zA-Z0-9]([a-zA-Z0-9._+-]*[a-zA-Z0-9])?@[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    /// Validates email with error throwing for server-side validation
    /// - Parameter email: Email address to validate
    /// - Returns: Validated email string
    /// - Throws: ValidationError if email is invalid
    static func validateEmail(_ email: String) throws -> String {
        guard isValidEmail(email) else {
            throw ValidationError.invalidEmail
        }
        return email
    }

    // MARK: - GitHub Username Validation

    /// Validates GitHub username format
    /// - GitHub usernames: alphanumeric or hyphens, 1-39 chars, cannot start/end with hyphen
    /// - Parameter username: GitHub username to validate
    /// - Returns: True if username is valid
    static func isValidGitHubUsername(_ username: String) -> Bool {
        let githubRegex = #"^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$"#
        return username.range(of: githubRegex, options: .regularExpression) != nil
    }

    // MARK: - GitHub Token Validation

    /// Validates GitHub Personal Access Token format
    /// Supports:
    /// - Classic PAT: ghp_[40 alphanumeric chars]
    /// - Fine-grained PAT: github_pat_[82+ base62 chars]
    /// - Fallback: 20+ chars with minimum entropy
    /// - Parameter token: GitHub PAT to validate
    /// - Returns: True if token is valid
    static func isValidGitHubToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespaces)

        // Check for classic PAT format: ghp_[40 alphanumeric chars]
        if trimmed.hasPrefix("ghp_") {
            let suffix = trimmed.dropFirst(4)
            return suffix.count == 40 && suffix.allSatisfy { $0.isLetter || $0.isNumber }
        }

        // Check for fine-grained PAT format: github_pat_[82+ base62 encoded chars]
        if trimmed.hasPrefix("github_pat_") {
            let suffix = trimmed.dropFirst(11)
            let base62Chars = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_")
            return suffix.count >= 82 && suffix.rangeOfCharacter(from: base62Chars.inverted) == nil
        }

        // For backwards compatibility or future token formats
        // SECURITY: Require minimum entropy to prevent weak tokens
        if trimmed.count >= 20 && trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            let uniqueChars = Set(trimmed)
            let hasLetters = trimmed.contains(where: { $0.isLetter })
            let hasNumbers = trimmed.contains(where: { $0.isNumber })
            // Require at least 10 unique characters and mix of letters and numbers
            return uniqueChars.count >= 10 && hasLetters && hasNumbers
        }

        return false
    }

    // MARK: - Git Config Key Validation

    /// Validates git config key format to prevent path traversal
    /// - Parameter key: Git config key (e.g., "user.name", "user.email")
    /// - Returns: True if key is valid
    /// - Throws: ValidationError if key is invalid
    static func validateGitConfigKey(_ key: String) throws {
        // Git config key format: section.subsection.key
        let keyRegex = #"^[a-zA-Z][a-zA-Z0-9-]*(\.[a-zA-Z][a-zA-Z0-9-]*)*$"#
        let keyPredicate = NSPredicate(format: "SELF MATCHES %@", keyRegex)

        guard keyPredicate.evaluate(with: key) else {
            throw ValidationError.invalidConfigKey
        }

        // SECURITY: Prevent path traversal attempts
        guard !key.contains("..") && !key.contains("/") && !key.contains("\\") else {
            throw ValidationError.pathTraversal
        }
    }

    // MARK: - Git Config Value Validation

    /// Validates and sanitizes git config values to prevent injection attacks
    /// - Parameters:
    ///   - value: Config value to validate
    ///   - field: Field name for error messages
    /// - Returns: Validated value
    /// - Throws: ValidationError if value is invalid
    static func validateGitConfigValue(_ value: String, field: String) throws -> String {
        // SECURITY: Check for control characters (including newlines, tabs, null bytes)
        // These could be used to inject arbitrary git configuration
        let controlCharacters = CharacterSet.controlCharacters
        if value.rangeOfCharacter(from: controlCharacters) != nil {
            throw ValidationError.invalidControlCharacters(field)
        }

        // SECURITY: Check for git special characters that could affect config parsing
        let dangerousChars = CharacterSet(charactersIn: "[]")
        if value.rangeOfCharacter(from: dangerousChars) != nil {
            throw ValidationError.invalidCharacters(field)
        }

        // Enforce reasonable length limits (git config has internal limits)
        guard value.count <= 255 else {
            throw ValidationError.inputTooLong(field, 255)
        }

        // Must not be empty or only whitespace
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyValue(field)
        }

        return value
    }

    // MARK: - Input Sanitization

    /// Checks for control characters in input
    /// - Parameter input: Input string to check
    /// - Returns: True if input contains control characters
    static func containsControlCharacters(_ input: String) -> Bool {
        return input.rangeOfCharacter(from: .controlCharacters) != nil || input.contains("\0")
    }

    /// Sanitizes git error messages to prevent information disclosure
    /// - Parameter stderr: Git stderr output
    /// - Returns: Sanitized error message
    static func sanitizeGitError(_ stderr: String) -> String {
        if stderr.isEmpty {
            return "Git command failed"
        }

        // SECURITY: Remove file paths that could leak system information
        // Use bounded quantifiers and specific character sets to prevent ReDoS attacks
        let homePatterns: [(pattern: String, replacement: String)] = [
            (#"/Users/[A-Za-z0-9_.-]{1,255}"#, "[HOME]"),
            (#"/home/[A-Za-z0-9_.-]{1,255}"#, "[HOME]"),
            (#"~(?:/[^\s]{0,255})?"#, "[HOME]"),
            (#"~(?=\s|$)"#, "[HOME]")
        ]

        var sanitized = stderr
        for (pattern, replacement) in homePatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

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

    // MARK: - Error Types

    enum ValidationError: LocalizedError {
        case invalidEmail
        case invalidGitHubUsername
        case invalidToken
        case invalidConfigKey
        case pathTraversal
        case invalidControlCharacters(String)
        case invalidCharacters(String)
        case inputTooLong(String, Int)
        case emptyValue(String)

        var errorDescription: String? {
            switch self {
            case .invalidEmail:
                return "Invalid email format"
            case .invalidGitHubUsername:
                return "Invalid GitHub username format (alphanumeric, hyphens only, max 39 chars)"
            case .invalidToken:
                return "Invalid Personal Access Token format"
            case .invalidConfigKey:
                return "Invalid config key format"
            case .pathTraversal:
                return "Config key contains invalid path characters"
            case .invalidControlCharacters(let field):
                return "\(field) contains invalid control characters"
            case .invalidCharacters(let field):
                return "\(field) contains invalid characters"
            case .inputTooLong(let field, let maxLength):
                return "\(field) exceeds maximum length (\(maxLength) characters)"
            case .emptyValue(let field):
                return "\(field) cannot be empty"
            }
        }
    }
}
