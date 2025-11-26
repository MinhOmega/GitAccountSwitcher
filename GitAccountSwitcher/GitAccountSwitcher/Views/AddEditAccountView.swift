import SwiftUI

/// View for adding or editing a GitHub account with enhanced visual effects
struct AddEditAccountView: View {
    // MARK: - Visual Effects State
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @State private var isHoveringClose = false
    @State private var isHoveringCancel = false
    @State private var isHoveringSave = false
    @State private var isHoveringTokenHelp = false

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
    @State private var originalToken = "" // Track original token for edit mode

    // MARK: - Token Validation Helper

    /// Checks if token is valid, considering edit mode where unchanged tokens are accepted
    private var isTokenValidForSave: Bool {
        let trimmedToken = personalAccessToken.trimmingCharacters(in: .whitespaces)

        // In edit mode, accept unchanged non-empty token without format validation
        if case .edit = mode, trimmedToken == originalToken, !trimmedToken.isEmpty {
            return true
        }

        // Otherwise, validate token format
        return isValidGitHubToken(trimmedToken)
    }

    // MARK: - Form Validation

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !githubUsername.trimmingCharacters(in: .whitespaces).isEmpty &&
        isTokenValidForSave &&
        !gitUserName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !gitUserEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(gitUserEmail.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Enhanced header with material background
            Group {
                if enableVisualEffects {
                    headerView
                        .background(Material.bar)
                } else {
                    headerView
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            }

            Divider()

            // Enhanced form with glass material
            Form {
                displaySection
                credentialsSection
                gitConfigSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .ultraThin, fallbackColor: .clear))

            Divider()

            // Enhanced actions with material background
            Group {
                if enableVisualEffects {
                    actionsView
                        .background(Material.bar)
                } else {
                    actionsView
                        .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .frame(width: 420, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear(perform: loadExistingAccount)
        .onDisappear {
            // SECURITY: Securely zero token from memory when view closes
            ValidationUtilities.secureZeroString(&personalAccessToken)
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
                .foregroundStyle(.primary)

            Spacer()

            Button(action: {
                withAnimation(.spring(duration: 0.3)) {
                    dismiss()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isHoveringClose ? .primary : .secondary)
                    .scaleEffect(isHoveringClose ? 1.1 : 1.0)
                    .animation(.spring(duration: 0.2), value: isHoveringClose)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringClose = hovering
            }
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

                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        showingTokenHelp = true
                    }
                }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(isHoveringTokenHelp ? .blue : .secondary)
                        .scaleEffect(isHoveringTokenHelp ? 1.1 : 1.0)
                        .animation(.spring(duration: 0.2), value: isHoveringTokenHelp)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringTokenHelp = hovering
                }
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
                withAnimation(.spring(duration: 0.3)) {
                    dismiss()
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isHoveringCancel ? .primary : .secondary)
            .scaleEffect(isHoveringCancel ? 1.05 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: isHoveringCancel)
            .onHover { hovering in
                isHoveringCancel = hovering
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: save) {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Saving...")
                            .font(.system(size: 13))
                    }
                    .frame(width: 90)
                } else {
                    Text(mode.buttonTitle)
                        .frame(width: 90)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!isValid || isSaving)
            .scaleEffect(isHoveringSave && isValid && !isSaving ? 1.05 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: isHoveringSave)
            .onHover { hovering in
                if isValid && !isSaving {
                    isHoveringSave = hovering
                }
            }
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

        // Validate token format (reuses isTokenValidForSave logic)
        guard isTokenValidForSave else {
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
        // Load token directly from account model (stored in local storage)
        personalAccessToken = account.personalAccessToken
        // Save original token to allow unchanged token in validation
        originalToken = account.personalAccessToken
    }

    private func save() {
        isSaving = true

        Task {
            defer {
                Task { @MainActor in
                    isSaving = false
                    // SECURITY: Securely zero token from memory after save attempt
                    ValidationUtilities.secureZeroString(&personalAccessToken)
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
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @State private var isHoveringClose = false
    @State private var isHoveringLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personal Access Token")
                    .font(.headline)
                Spacer()
                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        dismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(isHoveringClose ? .primary : .secondary)
                        .scaleEffect(isHoveringClose ? 1.1 : 1.0)
                        .animation(.spring(duration: 0.2), value: isHoveringClose)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringClose = hovering
                }
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
                    .controlSize(.regular)
                    .scaleEffect(isHoveringLink ? 1.05 : 1.0)
                    .animation(.spring(duration: 0.2, bounce: 0.3), value: isHoveringLink)
                    .onHover { hovering in
                        isHoveringLink = hovering
                    }
            }
        }
        .padding()
        .frame(width: 420, height: 370)
        .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .ultraThin, fallbackColor: Color(nsColor: .windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
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
