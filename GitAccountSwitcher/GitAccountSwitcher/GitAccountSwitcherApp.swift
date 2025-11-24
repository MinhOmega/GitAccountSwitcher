import SwiftUI
import UserNotifications
import ServiceManagement

@main
struct GitAccountSwitcherApp: App {
    @StateObject private var accountStore = AccountStore()
    @State private var showingAddAccount = false

    init() {
        // Request notification permissions on launch
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    var body: some Scene {
        // Main window - the primary interface
        Window("Git Account Switcher", id: "main") {
            MainWindowView()
                .environmentObject(accountStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Menu bar extra - quick access
        MenuBarExtra {
            MenuBarContentView(showingAddAccount: $showingAddAccount)
                .environmentObject(accountStore)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(accountStore)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let activeAccount = accountStore.activeAccount {
            Label(activeAccount.displayName, systemImage: "person.crop.circle.badge.checkmark")
        } else {
            Label("Git Account", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

// MARK: - Main Window View

struct MainWindowView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Environment(\.colorScheme) var colorScheme
    @State private var showingAddAccount = false
    @State private var isSwitching = false
    @State private var switchError: Error?
    @State private var showingError = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        VStack(spacing: 0) {
            // Header with current status
            headerView

            Divider()

            // Account list - the main focus
            if accountStore.accounts.isEmpty {
                emptyStateView
            } else {
                accountListView
            }

            Divider()

            // Footer with actions
            footerView
        }
        .frame(width: 380, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
        .alert("Switch Failed", isPresented: $showingError, presenting: switchError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // App icon/logo area
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [.githubDark, .githubDarkAlt],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Git Account Switcher")
                    .font(.system(size: 14, weight: .semibold))

                if let active = accountStore.activeAccount {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(active.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No account active")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { showingAddAccount = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Account List

    private var accountListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(accountStore.accounts) { account in
                    AccountCard(
                        account: account,
                        isSwitching: isSwitching,
                        onSwitch: { await switchToAccount(account) }
                    )
                    .environmentObject(accountStore)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.2.circle")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.githubGreen, .githubBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                Text("No Accounts Yet")
                    .font(.headline)

                Text("Add your GitHub accounts to quickly\nswitch between them")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showingAddAccount = true }) {
                Label("Add Your First Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: {
                Task { await accountStore.refreshCurrentGitConfig() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Refresh git config")

            Spacer()

            if let email = accountStore.currentGitConfig.email {
                Text(email)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func switchToAccount(_ account: GitAccount) async {
        guard !account.isActive else { return }

        isSwitching = true
        defer { isSwitching = false }

        do {
            try await accountStore.switchToAccount(account)
            if showNotificationOnSwitch {
                await showSwitchNotification(account: account)
            }
        } catch {
            switchError = error
            showingError = true
        }
    }

    private func showSwitchNotification(account: GitAccount) async {
        let content = UNMutableNotificationContent()
        content.title = "Git Account Switched"
        content.body = "Now using: \(account.displayName) (\(account.githubUsername))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Account Card (replaces complex sidebar/detail)

struct AccountCard: View {
    @EnvironmentObject var accountStore: AccountStore
    let account: GitAccount
    let isSwitching: Bool
    let onSwitch: () async -> Void

    @State private var isHovering = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    private var avatarGradient: LinearGradient {
        if account.isActive {
            return LinearGradient(colors: [.githubGreen, .githubGreenDark], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [.githubGray, .githubGrayDark], startPoint: .top, endPoint: .bottom)
        }
    }

    private var cardBackground: Color {
        if account.isActive {
            return Color.green.opacity(0.08)
        } else if isHovering {
            return Color.gray.opacity(0.08)
        } else {
            return Color.gray.opacity(0.04)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            avatarView
            infoView
            Spacer()
            actionsView
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(account.isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showingEditSheet) {
            AddEditAccountView(mode: .edit(account))
                .environmentObject(accountStore)
        }
        .confirmationDialog("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                try? accountStore.removeAccount(account)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(account.displayName)'?")
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: 44, height: 44)

            Text(String(account.displayName.prefix(1)).uppercased())
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var infoView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(account.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if account.isActive {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            Text("@\(account.githubUsername)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(account.gitUserEmail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var actionsView: some View {
        HStack(spacing: 12) {
            if !account.isActive {
                Button(action: { Task { await onSwitch() } }) {
                    if isSwitching {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Switch")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSwitching)
            }

            Menu {
                Button(action: { showingEditSheet = true }) {
                    Label("Edit", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("More options")
        }
    }
}

// MARK: - Menu Bar Content View

struct MenuBarContentView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Binding var showingAddAccount: Bool
    @State private var isSwitching = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        VStack(spacing: 0) {
            // Current status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Account")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    if let active = accountStore.activeAccount {
                        Text(active.displayName)
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("None")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Circle()
                    .fill(accountStore.activeAccount != nil ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Quick switch list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(accountStore.accounts) { account in
                        QuickSwitchRow(account: account, isSwitching: isSwitching) {
                            await switchToAccount(account)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 180)

            Divider()

            // Actions
            HStack {
                Button(action: { showingAddAccount = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { openMainWindow() }) {
                    Label("Open Window", systemImage: "macwindow")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Label("Quit", systemImage: "power")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Quit Git Account Switcher")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
    }

    private func switchToAccount(_ account: GitAccount) async {
        guard !account.isActive else { return }
        isSwitching = true
        defer { isSwitching = false }

        do {
            try await accountStore.switchToAccount(account)
            if showNotificationOnSwitch {
                let content = UNMutableNotificationContent()
                content.title = "Git Account Switched"
                content.body = "Now using: \(account.displayName)"
                content.sound = .default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                try? await UNUserNotificationCenter.current().add(request)
            }
        } catch {
            // SECURITY: Don't log errors to console - they may contain sensitive data
            // Error is already handled by UI in MainWindowView via accountStore.lastError
        }
    }

    private func openMainWindow() {
        // For menu bar apps, we need to activate the app first
        NSApp.activate(ignoringOtherApps: true)

        // Find the main window by identifier or title
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "main" || $0.title == "Git Account Switcher"
        }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            // Fall back to any window that can become main
            window.makeKeyAndOrderFront(nil)
        } else {
            // As a last resort, try to trigger window creation
            // This works because we have a Window scene defined in the app
            NSApp.sendAction(#selector(NSWindowController.showWindow(_:)), to: nil, from: nil)
        }
    }
}

struct QuickSwitchRow: View {
    let account: GitAccount
    let isSwitching: Bool
    let onSwitch: () async -> Void

    var body: some View {
        Button(action: { Task { await onSwitch() } }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(account.isActive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)

                Text(account.displayName)
                    .font(.system(size: 12, weight: account.isActive ? .semibold : .regular))

                Spacer()

                if account.isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(account.isActive || isSwitching)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var accountStore: AccountStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AccountsSettingsView()
                .environmentObject(accountStore)
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show notification on account switch", isOn: $showNotificationOnSwitch)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let error = launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Accounts Settings

struct AccountsSettingsView: View {
    @EnvironmentObject var accountStore: AccountStore
    @State private var selectedAccount: GitAccount?
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var deleteError: Error?
    @State private var showingDeleteError = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedAccount) {
                ForEach(accountStore.accounts) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.displayName)
                                .font(.headline)
                            Text(account.githubUsername)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if account.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .tag(account)
                }
            }

            Divider()

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }

                Button(action: removeSelectedAccount) {
                    Image(systemName: "minus")
                }
                .disabled(selectedAccount == nil)

                Spacer()

                Button("Edit") {
                    showingEditSheet = true
                }
                .disabled(selectedAccount == nil)
            }
            .padding(8)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let account = selectedAccount {
                AddEditAccountView(mode: .edit(account))
                    .environmentObject(accountStore)
            }
        }
        .alert("Delete Failed", isPresented: $showingDeleteError, presenting: deleteError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func removeSelectedAccount() {
        guard let account = selectedAccount else { return }
        do {
            try accountStore.removeAccount(account)
            selectedAccount = nil
        } catch {
            deleteError = error
            showingDeleteError = true
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "6366f1"), Color(hex: "8b5cf6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Git Account Switcher")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Text("Quickly switch between GitHub accounts with\nKeychain and git config management.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            Link("View on GitHub", destination: URL(string: "https://github.com/MinhOmega/GitAccountSwitcher")!)
                .buttonStyle(.link)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color Extension

extension Color {
    // GitHub Brand Colors
    static let githubGreen = Color(hex: "2ea043")
    static let githubGreenDark = Color(hex: "238636")
    static let githubBlue = Color(hex: "2f81f7")
    static let githubDark = Color(hex: "24292f")
    static let githubDarkAlt = Color(hex: "1a1e22")
    static let githubGray = Color(hex: "6e7681")
    static let githubGrayDark = Color(hex: "484f58")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
