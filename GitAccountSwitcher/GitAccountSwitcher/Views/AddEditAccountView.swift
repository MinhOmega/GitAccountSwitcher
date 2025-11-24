import SwiftUI

/// View for adding or editing a GitHub account
struct AddEditAccountView: View {

    enum Mode: Identifiable {
        case add
        case edit(GitAccount)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let account): return account.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .add: return "Add Account"
            case .edit: return "Edit Account"
            }
        }

        var buttonTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }

        var account: GitAccount? {
            switch self {
            case .add: return nil
            case .edit(let account): return account
            }
        }
    }

    // MARK: - Validation Error

    enum ValidationError: LocalizedError {
        case invalidCharacters(String)
        case inputTooLong(String)
        case invalidEmail
        case invalidGitHubUsername
        case invalidToken

        var errorDescription: String? {
            switch self {
            case .invalidCharacters(let field):
                return "\(field) contains invalid control characters"
            case .inputTooLong(let field):
                return "\(field) exceeds maximum length"
            case .invalidEmail:
                return "Invalid email format"
            case .invalidGitHubUsername:
                return "Invalid GitHub username format (alphanumeric, hyphens only, max 39 chars)"
            case .invalidToken:
                return "Invalid Personal Access Token format"
            }
        }
    }

    @EnvironmentObject var accountStore: AccountStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    // Form fields
    @State private var displayName = ""
    @State private var githubUsername = ""
    @State private var personalAccessToken = ""
    @State private var gitUserName = ""
    @State private var gitUserEmail = ""

    // State
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showingError = false
    @State private var showingTokenHelp = false

    // Validation
    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !githubUsername.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidGitHubToken(personalAccessToken.trimmingCharacters(in: .whitespaces)) &&
        !gitUserName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !gitUserEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(gitUserEmail.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Form
            Form {
                displaySection
                credentialsSection
                gitConfigSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Actions
            actionsView
        }
        .frame(width: 400, height: 480)
        .onAppear(perform: loadExistingAccount)
        .onDisappear {
            // SECURITY: Clear token from memory when view closes
            personalAccessToken = ""
        }
        .alert("Error", isPresented: $showingError, presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(isPresented: $showingTokenHelp) {
            TokenHelpView()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(mode.title)
                .font(.headline)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Form Sections

    private var displaySection: some View {
        Section {
            TextField("Display Name", text: $displayName)
                .textFieldStyle(.roundedBorder)
        } header: {
            Text("Display")
        } footer: {
            Text("A friendly name to identify this account (e.g., \"Personal\", \"Work\")")
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("GitHub Username", text: $githubUsername)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            HStack {
                SecureField("Personal Access Token", text: $personalAccessToken)
                    .textFieldStyle(.roundedBorder)

                Button(action: { showingTokenHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("GitHub Credentials")
        } footer: {
            Text("Your GitHub username and Personal Access Token (PAT)")
        }
    }

    private var gitConfigSection: some View {
        Section {
            TextField("Name", text: $gitUserName)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $gitUserEmail)
                .textFieldStyle(.roundedBorder)
        } header: {
            Text("Git Config")
        } footer: {
            Text("These values will be set as git config user.name and user.email")
        }
    }

    // MARK: - Actions

    private var actionsView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: save) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 60)
                } else {
                    Text(mode.buttonTitle)
                        .frame(width: 60)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Validation Helpers

    /// Validates comprehensive input before saving
    private func validateInputs() throws {
        // Validate no control characters in any field
        let inputs: [(String, String)] = [
            (displayName, "Display name"),
            (githubUsername, "GitHub username"),
            (gitUserName, "Name"),
            (gitUserEmail, "Email")
        ]

        for (input, fieldName) in inputs {
            guard !ValidationUtilities.containsControlCharacters(input) else {
                throw ValidationError.invalidCharacters(fieldName)
            }
        }

        // Validate lengths
        guard displayName.count <= 100 else {
            throw ValidationError.inputTooLong("Display name")
        }
        guard githubUsername.count <= 39 else {  // GitHub's max username length
            throw ValidationError.inputTooLong("GitHub username")
        }
        guard gitUserName.count <= 200 else {
            throw ValidationError.inputTooLong("Name")
        }
        guard gitUserEmail.count <= 254 else {  // RFC 5321 max email length
            throw ValidationError.inputTooLong("Email")
        }

        // Validate GitHub username format
        guard ValidationUtilities.isValidGitHubUsername(githubUsername) else {
            throw ValidationError.invalidGitHubUsername
        }

        // Validate email format
        guard isValidEmail(gitUserEmail) else {
            throw ValidationError.invalidEmail
        }

        // Validate token format
        guard isValidGitHubToken(personalAccessToken) else {
            throw ValidationError.invalidToken
        }
    }

    /// Validates email format
    private func isValidEmail(_ email: String) -> Bool {
        return ValidationUtilities.isValidEmail(email)
    }

    /// Validates GitHub Personal Access Token format
    private func isValidGitHubToken(_ token: String) -> Bool {
        return ValidationUtilities.isValidGitHubToken(token)
    }

    // MARK: - Actions

    private func loadExistingAccount() {
        guard case .edit(let account) = mode else { return }

        displayName = account.displayName
        githubUsername = account.githubUsername
        gitUserName = account.gitUserName
        gitUserEmail = account.gitUserEmail

        // Try to load token from keychain
        if let fullAccount = try? accountStore.getAccountWithToken(account) {
            personalAccessToken = fullAccount.personalAccessToken
        }
    }

    private func save() {
        isSaving = true

        Task {
            defer {
                Task { @MainActor in
                    isSaving = false
                    // SECURITY: Clear token from memory after save attempt
                    personalAccessToken = ""
                }
            }

            do {
                // SECURITY: Validate all inputs before processing
                try validateInputs()

                // Create account with trimmed values
                let account = GitAccount(
                    id: mode.account?.id ?? UUID(),
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    githubUsername: githubUsername.trimmingCharacters(in: .whitespaces),
                    personalAccessToken: personalAccessToken.trimmingCharacters(in: .whitespaces),
                    gitUserName: gitUserName.trimmingCharacters(in: .whitespaces),
                    gitUserEmail: gitUserEmail.trimmingCharacters(in: .whitespaces),
                    isActive: mode.account?.isActive ?? false,
                    createdAt: mode.account?.createdAt ?? Date(),
                    lastUsedAt: mode.account?.lastUsedAt
                )

                switch mode {
                case .add:
                    try accountStore.addAccount(account)
                case .edit:
                    try accountStore.updateAccount(account)
                }

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    saveError = error
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Token Help View

struct TokenHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personal Access Token")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Text("A Personal Access Token (PAT) is required to authenticate with GitHub.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("How to create a PAT:")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("1. Go to GitHub Settings > Developer settings > Personal access tokens")
                Text("2. Click \"Generate new token (classic)\"")
                Text("3. Give it a name and select the required scopes:")

                VStack(alignment: .leading, spacing: 2) {
                    Text("  \u{2022} repo (for private repositories)")
                    Text("  \u{2022} read:user")
                    Text("  \u{2022} user:email")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

                Text("4. Click \"Generate token\" and copy it")
            }
            .font(.callout)

            Spacer()

            HStack {
                Spacer()
                Link("Open GitHub Settings", destination: URL(string: "https://github.com/settings/tokens")!)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

// MARK: - Preview

#Preview("Add Account") {
    AddEditAccountView(mode: .add)
        .environmentObject(AccountStore())
}

#Preview("Edit Account") {
    AddEditAccountView(mode: .edit(.preview))
        .environmentObject(AccountStore())
}
