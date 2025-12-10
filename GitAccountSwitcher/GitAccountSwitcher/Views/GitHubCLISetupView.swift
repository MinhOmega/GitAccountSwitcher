import SwiftUI

// MARK: - GitHub CLI Setup View

/// First-time setup guide for GitHub CLI installation and authentication
struct GitHubCLISetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @AppStorage("hasCompletedCLISetup") private var hasCompletedCLISetup = false
    @AppStorage("skipCLISetup") private var skipCLISetup = false

    @State private var currentStep: SetupStep = .welcome
    @State private var isCheckingCLI = false
    @State private var isCLIInstalled = false
    @State private var isLoggedIn = false
    @State private var checkingLogin = false

    private let cliService = GitHubCLIService.shared

    enum SetupStep: Int, CaseIterable {
        case welcome
        case install
        case login
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case .welcome:
                        welcomeContent
                    case .install:
                        installContent
                    case .login:
                        loginContent
                    case .complete:
                        completeContent
                    }
                }
                .padding(30)
            }
            .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .ultraThin, fallbackColor: .clear))

            Divider()

            // Footer actions
            footerActions
                .padding()
                .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .bar, fallbackColor: Color(nsColor: .controlBackgroundColor)))
        }
        .frame(width: 520, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            checkCLIStatus()
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 4) {
                    Circle()
                        .fill(stepColor(for: step))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: stepColor(for: step).opacity(0.5), radius: step == currentStep ? 4 : 0)

                    if step != .complete {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 40, height: 2)
                    }
                }
            }
        }
        .animation(.spring(duration: 0.3), value: currentStep)
    }

    private func stepColor(for step: SetupStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }

    // MARK: - Welcome Content

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.githubGreen.opacity(0.2), .githubBlue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.githubGreen, .githubBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("GitHub CLI Setup")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("For the best experience, we recommend setting up GitHub CLI (gh) for seamless account switching.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Benefits list
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "arrow.triangle.2.circlepath.circle", text: "Seamless account switching with 'gh auth switch'", highlight: true)
                benefitRow(icon: "lock.shield", text: "Secure authentication via GitHub's official CLI")
                benefitRow(icon: "terminal", text: "Works with git operations automatically")
                benefitRow(icon: "checkmark.circle", text: "Better integration with GitHub features")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    private func benefitRow(icon: String, text: String, highlight: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(highlight ? .green : .blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(highlight ? .primary : .secondary)
        }
    }

    // MARK: - Install Content

    private var installContent: some View {
        VStack(spacing: 24) {
            // Status icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [isCLIInstalled ? Color.green.opacity(0.2) : Color.orange.opacity(0.2),
                                    isCLIInstalled ? Color.green.opacity(0.1) : Color.yellow.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                if isCheckingCLI {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: isCLIInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(isCLIInstalled ? .green : .orange)
                }
            }

            VStack(spacing: 12) {
                Text(isCLIInstalled ? "GitHub CLI Installed" : "Install GitHub CLI")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(isCLIInstalled
                     ? "GitHub CLI is already installed on your system."
                     : "GitHub CLI is not installed. Click the button below to install it via Homebrew.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !isCLIInstalled {
                // Install instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Installation Command:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        Text(cliService.installCommand)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button(action: copyInstallCommand) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .help("Copy command")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )

                    Text("This will install GitHub CLI using Homebrew. If you don't have Homebrew, visit brew.sh first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        )
                )

                // Run in Terminal button
                Button(action: {
                    cliService.openTerminalForInstall()
                }) {
                    HStack {
                        Image(systemName: "terminal.fill")
                        Text("Run in Terminal")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            // Refresh button
            Button(action: checkCLIStatus) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Check Again")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isCheckingCLI)
        }
    }

    // MARK: - Login Content

    private var loginContent: some View {
        VStack(spacing: 24) {
            // Status icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [isLoggedIn ? Color.green.opacity(0.2) : Color.blue.opacity(0.2),
                                    isLoggedIn ? Color.green.opacity(0.1) : Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                if checkingLogin {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: isLoggedIn ? "checkmark.circle.fill" : "person.badge.key.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(isLoggedIn ? .green : .blue)
                }
            }

            VStack(spacing: 12) {
                Text(isLoggedIn ? "Logged In" : "Login to GitHub CLI")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(isLoggedIn
                     ? "You're logged in to GitHub CLI."
                     : "Authenticate with GitHub CLI to enable seamless account switching.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !isLoggedIn {
                // Login instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Login Command:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        Text(cliService.loginCommand)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button(action: copyLoginCommand) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.borderless)
                        .help("Copy command")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )

                    Text("Follow the prompts in Terminal to authenticate with your GitHub account.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )

                // Run in Terminal button
                Button(action: {
                    cliService.openTerminalForLogin()
                }) {
                    HStack {
                        Image(systemName: "terminal.fill")
                        Text("Run in Terminal")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            // Refresh button
            Button(action: checkLoginStatus) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Check Again")
                }
            }
            .buttonStyle(.borderless)
            .disabled(checkingLogin)

            // Important notice
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Important")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)

                Text("When you add a new account in this app, make sure to also run 'gh auth login' for that account to enable CLI switching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.05))
            )
        }
    }

    // MARK: - Complete Content

    private var completeContent: some View {
        VStack(spacing: 24) {
            // Success icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 12) {
                Text("Setup Complete!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("GitHub CLI is configured and ready to use. Account switching will now use 'gh auth switch' for seamless transitions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Summary
            VStack(alignment: .leading, spacing: 12) {
                summaryRow(icon: "checkmark.circle.fill", text: "GitHub CLI installed", isComplete: true)
                summaryRow(icon: "checkmark.circle.fill", text: "Authenticated with GitHub", isComplete: true)
                summaryRow(icon: "checkmark.circle.fill", text: "Ready for account switching", isComplete: true)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    private func summaryRow(icon: String, text: String, isComplete: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isComplete ? .green : .gray)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack {
            if currentStep != .complete {
                Button("Skip Setup") {
                    skipSetup()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Spacer()

            switch currentStep {
            case .welcome:
                Button(action: { goToNextStep() }) {
                    Text("Get Started")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)

            case .install:
                if isCLIInstalled {
                    Button(action: { goToNextStep() }) {
                        Text("Continue")
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: { goToNextStep() }) {
                        Text("Skip")
                            .frame(width: 120)
                    }
                    .buttonStyle(.bordered)
                }

            case .login:
                if isLoggedIn {
                    Button(action: { goToNextStep() }) {
                        Text("Continue")
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: { goToNextStep() }) {
                        Text("Skip")
                            .frame(width: 120)
                    }
                    .buttonStyle(.bordered)
                }

            case .complete:
                Button(action: { completeSetup() }) {
                    Text("Done")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    // MARK: - Actions

    private func checkCLIStatus() {
        isCheckingCLI = true
        Task {
            // Small delay for UI feedback
            try? await Task.sleep(nanoseconds: 500_000_000)

            let installed = cliService.isInstalled

            await MainActor.run {
                isCLIInstalled = installed
                isCheckingCLI = false

                // Auto-advance if installed
                if installed && currentStep == .install {
                    checkLoginStatus()
                }
            }
        }
    }

    private func checkLoginStatus() {
        checkingLogin = true
        Task {
            let loggedIn = await cliService.isLoggedIn()

            await MainActor.run {
                isLoggedIn = loggedIn
                checkingLogin = false
            }
        }
    }

    private func goToNextStep() {
        withAnimation(.spring(duration: 0.3)) {
            switch currentStep {
            case .welcome:
                currentStep = .install
                checkCLIStatus()
            case .install:
                currentStep = .login
                checkLoginStatus()
            case .login:
                currentStep = .complete
            case .complete:
                completeSetup()
            }
        }
    }

    private func skipSetup() {
        skipCLISetup = true
        hasCompletedCLISetup = true
        dismiss()
    }

    private func completeSetup() {
        hasCompletedCLISetup = true
        dismiss()
    }

    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cliService.installCommand, forType: .string)
    }

    private func copyLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cliService.loginCommand, forType: .string)
    }
}

// MARK: - CLI Login Reminder Alert

/// A reusable view modifier that shows a reminder to login with GitHub CLI
struct CLILoginReminderModifier: ViewModifier {
    @Binding var isPresented: Bool
    let accountName: String

    func body(content: Content) -> some View {
        content
            .alert("GitHub CLI Login Reminder", isPresented: $isPresented) {
                Button("Run gh auth login") {
                    GitHubCLIService.shared.openTerminalForLogin()
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text("To enable seamless switching for '\(accountName)', please also run 'gh auth login' in Terminal to authenticate this account with GitHub CLI.")
            }
    }
}

extension View {
    func cliLoginReminder(isPresented: Binding<Bool>, accountName: String) -> some View {
        modifier(CLILoginReminderModifier(isPresented: isPresented, accountName: accountName))
    }
}

// MARK: - Preview

#Preview("CLI Setup - Welcome") {
    GitHubCLISetupView()
}
