import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Main App with 2025 Best Practices

@main
struct GitAccountSwitcherApp: App {
    @StateObject private var accountStore = AccountStore()
    @State private var showingAddAccount = false
    @State private var dockBadgeCount = 0
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Request notification permissions with enhanced options for 2025
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge, .provisional]
            )
        }
    }

    var body: some Scene {
        // Main window with enhanced visual effects
        // NOTE: Dock icon visibility is managed by AppDelegate via window notifications
        Window("Git Account Switcher", id: "main") {
            MainWindowView()
                .environmentObject(accountStore)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)

        // Enhanced Menu bar extra with materials
        MenuBarExtra {
            MenuBarContentView(showingAddAccount: $showingAddAccount)
                .environmentObject(accountStore)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // Settings with enhanced visuals
        Settings {
            SettingsView()
                .environmentObject(accountStore)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            if let activeAccount = accountStore.activeAccount {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green.gradient)

                    // Badge indicator for notifications
                    if dockBadgeCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Text("\(min(dockBadgeCount, 9))")
                                    .font(.system(size: 6))
                                    .foregroundColor(.white)
                            )
                    }
                }

                Text(activeAccount.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)

                Text("Git Account")
                    .font(.caption)
            }
        }
        .frame(maxWidth: 120)
    }
}

// MARK: - Shared Account Switching Helpers

extension View {
    /// Enhanced account switching with animations and notifications
    @MainActor
    func performAccountSwitch(
        to account: GitAccount,
        accountStore: AccountStore,
        isSwitching: Binding<Bool>,
        showNotification: Bool,
        onError: ((Error) -> Void)? = nil
    ) async {
        guard !account.isActive else { return }

        // Animate switching state
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
            isSwitching.wrappedValue = true
        }

        defer {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                isSwitching.wrappedValue = false
            }
        }

        do {
            try await accountStore.switchToAccount(account)

            if showNotification {
                await showEnhancedNotification(for: account)
            }

            // Clear dock badge on success
            NSApp.dockTile.badgeLabel = nil

        } catch {
            onError?(error)

            // Show error in dock
            NSApp.dockTile.badgeLabel = "!"
        }
    }

    /// Shows enhanced notification with rich content
    @MainActor
    private func showEnhancedNotification(for account: GitAccount) async {
        let content = UNMutableNotificationContent()
        content.title = "Git Account Switched"
        content.subtitle = "Now using: \(account.displayName)"
        content.body = "GitHub: @\(account.githubUsername)\nEmail: \(account.gitUserEmail)"
        content.sound = .default
        content.categoryIdentifier = "ACCOUNT_SWITCH"
        content.userInfo = ["accountId": account.id.uuidString]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Enhanced Main Window View

struct MainWindowView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Environment(\.colorScheme) var colorScheme
    @State private var showingAddAccount = false
    @State private var isSwitching = false
    @State private var switchError: Error?
    @State private var showingError = false
    @State private var hoveredAccountId: UUID?
    @State private var showingWelcome = false
    @State private var showingCLISetup = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("hasCompletedCLISetup") private var hasCompletedCLISetup = false
    @AppStorage("skipCLISetup") private var skipCLISetup = false

    var body: some View {
        ZStack {
            // Background with liquid glass effect
            if enableVisualEffects {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0.8),
                        Color.githubDark.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .blur(radius: 20)
            }

            VStack(spacing: 0) {
                // Enhanced header with glass material
                Group {
                    if enableVisualEffects {
                        headerView
                            .background(Material.ultraThin)
                    } else {
                        headerView
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }

                Divider()

                // Account list with enhanced animations
                if accountStore.accounts.isEmpty {
                    emptyStateView
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    accountListView
                        .transition(.slide)
                }

                Divider()

                // Footer with material background
                Group {
                    if enableVisualEffects {
                        footerView
                            .background(Material.bar)
                    } else {
                        footerView
                            .background(Color(nsColor: .controlBackgroundColor))
                    }
                }
            }
        }
        .frame(width: 420, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeView()
                .environmentObject(accountStore)
        }
        .sheet(isPresented: $showingCLISetup) {
            GitHubCLISetupView()
        }
        .alert("Switch Failed", isPresented: $showingError, presenting: switchError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .onAppear {
            // Show welcome screen on first launch
            if !hasCompletedWelcome {
                showingWelcome = true
            }
        }
        .onChange(of: showingWelcome) { newValue in
            // Show CLI setup after welcome is completed
            if !newValue && hasCompletedWelcome && !hasCompletedCLISetup && !skipCLISetup {
                // Small delay to avoid sheet presentation conflict
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCLISetup = true
                }
            }
        }
    }

    // MARK: - Enhanced Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Animated app icon with gradient
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.githubGreen, .githubBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .githubGreen.opacity(0.3), radius: 8, x: 0, y: 4)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Git Account Switcher")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let active = accountStore.activeAccount {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: .green.opacity(0.6), radius: 2)

                        Text(active.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.asymmetric(
                        insertion: .push(from: .leading).combined(with: .opacity),
                        removal: .push(from: .trailing).combined(with: .opacity)
                    ))
                } else {
                    Text("No account active")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Modern add button with gradient
            Button(action: {
                withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                    showingAddAccount = true
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.linearGradient(
                                colors: [.githubBlue, .githubGreen],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Enhanced Account List

    private var accountListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(accountStore.accounts) { account in
                    EnhancedAccountCard(
                        account: account,
                        isHovered: hoveredAccountId == account.id,
                        isSwitching: isSwitching,
                        onSwitch: { await switchToAccount(account) }
                    )
                    .environmentObject(accountStore)
                    .onHover { hovering in
                        withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                            hoveredAccountId = hovering ? account.id : nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .slide.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .padding(20)
        }
        .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .ultraThin))
    }

    // MARK: - Enhanced Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated icon with glow effect
            ZStack {
                Circle()
                    .fill(.linearGradient(
                        colors: [.githubGreen.opacity(0.2), .githubBlue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Image(systemName: "person.2.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.githubGreen, .githubBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("No Accounts Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add your GitHub accounts to quickly\nswitch between them")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                    showingAddAccount = true
                }
            }) {
                Label("Add Your First Account", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.linearGradient(
                                colors: [.githubGreen, .githubBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .ultraThin))
    }

    // MARK: - Enhanced Footer

    private var footerView: some View {
        HStack {
            Button(action: {
                Task {
                    await accountStore.refreshCurrentGitConfig()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh git config")

            Spacer()

            if let email = accountStore.currentGitConfig.email {
                Text(email)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }

            Spacer()

            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func switchToAccount(_ account: GitAccount) async {
        await performAccountSwitch(
            to: account,
            accountStore: accountStore,
            isSwitching: $isSwitching,
            showNotification: showNotificationOnSwitch
        ) { error in
            switchError = error
            showingError = true
        }
    }
}

// MARK: - Enhanced Account Card with Modern Effects

struct EnhancedAccountCard: View {
    @EnvironmentObject var accountStore: AccountStore
    let account: GitAccount
    let isHovered: Bool
    let isSwitching: Bool
    let onSwitch: () async -> Void

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isPressed = false
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true

    private var cardScale: CGFloat {
        if isPressed { return 0.98 }
        if isHovered { return 1.02 }
        return 1.0
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(
                account.isActive ?
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.12),
                        Color.green.opacity(0.08),
                        Color.blue.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) :
                LinearGradient(
                    colors: [
                        Color(hex: "6366f1").opacity(0.08),
                        Color(hex: "8b5cf6").opacity(0.06),
                        Color.gray.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        account.isActive ?
                        LinearGradient(
                            colors: [Color.green.opacity(0.5), Color.green.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [
                                isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.05),
                                isHovered ? Color.white.opacity(0.1) : Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: account.isActive ? 2 : 1
                    )
            )
    }

    var body: some View {
        HStack(spacing: 16) {
            // Enhanced avatar with better design
            ZStack {
                // Avatar background with glow effect
                Circle()
                    .fill(
                        account.isActive ?
                        LinearGradient(colors: [.githubGreen, .githubGreenDark], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color(hex: "6366f1"), Color(hex: "8b5cf6")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 54, height: 54)
                    .shadow(color: account.isActive ? .green.opacity(0.5) : Color(hex: "6366f1").opacity(0.3), radius: 10, x: 0, y: 4)

                // Avatar letter
                Text(String(account.displayName.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Active indicator ring
                if account.isActive {
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        .frame(width: 60, height: 60)
                }
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: isHovered)

            // Info section with improved layout
            VStack(alignment: .leading, spacing: 6) {
                // Display name with active badge
                HStack(spacing: 8) {
                    Text(account.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    if account.isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.green, .green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                        )
                        .shadow(color: .green.opacity(0.4), radius: 4, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                // GitHub username
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("@\(account.githubUsername)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Email with better visibility
                HStack(spacing: 4) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(account.gitUserEmail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(account.gitUserEmail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Enhanced action button
            Menu {
                if !account.isActive {
                    Button(action: { Task { await onSwitch() } }) {
                        Label("Switch to Account", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isSwitching)

                    Divider()
                }

                Button(action: { showingEditSheet = true }) {
                    Label("Edit Account", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete Account", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
            color: account.isActive ? .green.opacity(0.25) : .black.opacity(0.12),
            radius: isHovered ? 16 : 6,
            x: 0,
            y: isHovered ? 8 : 3
        )
        .scaleEffect(cardScale)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: cardScale)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: isHovered)
        .onTapGesture {}
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.spring(duration: 0.2)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .sheet(isPresented: $showingEditSheet) {
            AddEditAccountView(mode: .edit(account))
                .environmentObject(accountStore)
        }
        .confirmationDialog("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                    try? accountStore.removeAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(account.displayName)'?")
        }
    }
}

// MARK: - Enhanced Menu Bar Content

struct MenuBarContentView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Binding var showingAddAccount: Bool
    @State private var isSwitching = false
    @State private var hoveredAccountId: UUID?
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true

    var body: some View {
        VStack(spacing: 0) {
            // Enhanced status header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT ACCOUNT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)

                    if let active = accountStore.activeAccount {
                        Text(active.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    } else {
                        Text("None")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Circle()
                    .fill(accountStore.activeAccount != nil ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .shadow(
                        color: accountStore.activeAccount != nil ? .green.opacity(0.5) : .clear,
                        radius: 4
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding()
            .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .ultraThin, fallbackColor: Color(nsColor: .controlBackgroundColor)))

            Divider()

            // Enhanced quick switch list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(accountStore.accounts) { account in
                        EnhancedQuickSwitchRow(
                            account: account,
                            isHovered: hoveredAccountId == account.id,
                            isSwitching: isSwitching
                        ) {
                            await switchToAccount(account)
                        }
                        .onHover { hovering in
                            withAnimation(.spring(duration: 0.2)) {
                                hoveredAccountId = hovering ? account.id : nil
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
            .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .regular, fallbackColor: Color.clear))

            Divider()

            // Enhanced actions bar
            HStack(spacing: 16) {
                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        showingAddAccount = true
                    }
                }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { openMainWindow() }) {
                    Label("Window", systemImage: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .bar, fallbackColor: Color(nsColor: .controlBackgroundColor)))
        }
        .frame(width: 280)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 10)
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
    }

    private func switchToAccount(_ account: GitAccount) async {
        await performAccountSwitch(
            to: account,
            accountStore: accountStore,
            isSwitching: $isSwitching,
            showNotification: showNotificationOnSwitch,
            onError: nil
        )
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "main" || $0.title == "Git Account Switcher"
        }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSWindowController.showWindow(_:)), to: nil, from: nil)
        }
    }
}

// MARK: - Enhanced Quick Switch Row

struct EnhancedQuickSwitchRow: View {
    let account: GitAccount
    let isHovered: Bool
    let isSwitching: Bool
    let onSwitch: () async -> Void

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                account.isActive ?
                Color.green.opacity(0.1) :
                (isHovered ? Color.white.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        account.isActive ? Color.green.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
    }

    var body: some View {
        Button(action: { Task { await onSwitch() } }) {
            HStack(spacing: 12) {
                // Status indicator with glow effect
                Circle()
                    .fill(account.isActive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: account.isActive ? .green.opacity(0.6) : .clear,
                        radius: account.isActive ? 4 : 0
                    )
                    .scaleEffect(isHovered && !account.isActive ? 1.2 : 1.0)
                    .animation(.spring(duration: 0.2), value: isHovered)

                Text(account.displayName)
                    .font(.system(size: 12, weight: account.isActive ? .semibold : .regular))
                    .foregroundStyle(account.isActive ? .primary : .secondary)

                Spacer()

                if account.isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .disabled(account.isActive || isSwitching)
        .scaleEffect(isHovered && !account.isActive ? 1.02 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovered)
    }
}

// MARK: - Settings View (Enhanced with Materials)

struct SettingsView: View {
    @EnvironmentObject var accountStore: AccountStore
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true

    var body: some View {
        TabView {
            GeneralSettingsView()
                .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .regular, fallbackColor: Color.clear))
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AccountsSettingsView()
                .environmentObject(accountStore)
                .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .regular, fallbackColor: Color.clear))
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }

            AboutView()
                .modifier(ConditionalBackground(enableMaterial: enableVisualEffects, material: .regular, fallbackColor: Color.clear))
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings (Enhanced)

struct GeneralSettingsView: View {
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @AppStorage("hasCompletedCLISetup") private var hasCompletedCLISetup = false
    @AppStorage("skipCLISetup") private var skipCLISetup = false
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var isHoveringNotification = false
    @State private var isHoveringVisualEffects = false
    @State private var isHoveringLaunch = false
    @State private var showingCLISetup = false
    @State private var isCLIInstalled = false
    @State private var isCLILoggedIn = false

    var body: some View {
        Form {
            Section {
                Toggle("Show notification on account switch", isOn: $showNotificationOnSwitch)
                    .scaleEffect(isHoveringNotification ? 1.02 : 1.0)
                    .animation(.spring(duration: 0.2), value: isHoveringNotification)
                    .onHover { hovering in
                        isHoveringNotification = hovering
                    }

                Toggle("Enable visual effects (glass, animations)", isOn: $enableVisualEffects)
                    .help("Disable for better performance on older Macs")
                    .scaleEffect(isHoveringVisualEffects ? 1.02 : 1.0)
                    .animation(.spring(duration: 0.2), value: isHoveringVisualEffects)
                    .onHover { hovering in
                        isHoveringVisualEffects = hovering
                    }

                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .scaleEffect(isHoveringLaunch ? 1.02 : 1.0)
                .animation(.spring(duration: 0.2), value: isHoveringLaunch)
                .onHover { hovering in
                    isHoveringLaunch = hovering
                }

                if let error = launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("GitHub CLI") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: isCLIInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isCLIInstalled ? .green : .red)
                            Text("GitHub CLI (gh)")
                                .font(.body)
                        }

                        if isCLIInstalled {
                            HStack(spacing: 8) {
                                Image(systemName: isCLILoggedIn ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(isCLILoggedIn ? .green : .orange)
                                    .font(.caption)
                                Text(isCLILoggedIn ? "Logged in" : "Not logged in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Not installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Setup") {
                        // Reset the setup flags to allow re-running
                        hasCompletedCLISetup = false
                        skipCLISetup = false
                        showingCLISetup = true
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            checkCLIStatus()
        }
        .sheet(isPresented: $showingCLISetup) {
            GitHubCLISetupView()
        }
    }

    private func checkCLIStatus() {
        Task {
            let status = await GitHubCLIService.shared.checkFullStatus()
            await MainActor.run {
                isCLIInstalled = status.isInstalled
                isCLILoggedIn = status.isLoggedIn
            }
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
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @State private var selectedAccount: GitAccount?
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var deleteError: Error?
    @State private var showingDeleteError = false
    @State private var isHoveringAdd = false
    @State private var isHoveringRemove = false
    @State private var isHoveringEdit = false

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
                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        showingAddSheet = true
                    }
                }) {
                    Image(systemName: "plus")
                        .foregroundStyle(isHoveringAdd ? .primary : .secondary)
                }
                .buttonStyle(.borderless)
                .scaleEffect(isHoveringAdd ? 1.1 : 1.0)
                .animation(.spring(duration: 0.2), value: isHoveringAdd)
                .onHover { hovering in
                    isHoveringAdd = hovering
                }

                Button(action: removeSelectedAccount) {
                    Image(systemName: "minus")
                        .foregroundStyle(isHoveringRemove && selectedAccount != nil ? Color.red : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(selectedAccount == nil)
                .scaleEffect(isHoveringRemove && selectedAccount != nil ? 1.1 : 1.0)
                .animation(.spring(duration: 0.2), value: isHoveringRemove)
                .onHover { hovering in
                    if selectedAccount != nil {
                        isHoveringRemove = hovering
                    }
                }

                Spacer()

                Button("Edit") {
                    withAnimation(.spring(duration: 0.3)) {
                        showingEditSheet = true
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isHoveringEdit && selectedAccount != nil ? .blue : .primary)
                .disabled(selectedAccount == nil)
                .scaleEffect(isHoveringEdit && selectedAccount != nil ? 1.05 : 1.0)
                .animation(.spring(duration: 0.2), value: isHoveringEdit)
                .onHover { hovering in
                    if selectedAccount != nil {
                        isHoveringEdit = hovering
                    }
                }
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

// MARK: - About View (Enhanced)

struct AboutView: View {
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true

    var body: some View {
        VStack(spacing: 16) {
            // Animated logo
            ZStack {
                if enableVisualEffects {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6366f1").opacity(0.2), Color(hex: "8b5cf6").opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .blur(radius: 20)
                }

                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "6366f1"), Color(hex: "8b5cf6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

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

// MARK: - Helper Modifiers for Conditional Backgrounds

struct ConditionalBackground: ViewModifier {
    let enableMaterial: Bool
    let material: Material
    var fallbackColor: Color = Color.clear

    func body(content: Content) -> some View {
        Group {
            if enableMaterial {
                content.background(material)
            } else {
                content.background(fallbackColor)
            }
        }
    }
}

// MARK: - Reusable Hover Effect Modifier

struct HoverEffect: ViewModifier {
    @State private var isHovering = false
    let scale: CGFloat
    let animation: Animation

    init(scale: CGFloat = 1.05, animation: Animation = .spring(duration: 0.2, bounce: 0.3)) {
        self.scale = scale
        self.animation = animation
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1.0)
            .animation(animation, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Hover with Color Change Modifier

struct HoverColorEffect: ViewModifier {
    @State private var isHovering = false
    let activeColor: Color
    let inactiveColor: Color
    let scale: CGFloat

    init(activeColor: Color = .primary, inactiveColor: Color = .secondary, scale: CGFloat = 1.0) {
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.scale = scale
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isHovering ? activeColor : inactiveColor)
            .scaleEffect(isHovering ? scale : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.05) -> some View {
        self.modifier(HoverEffect(scale: scale))
    }

    func buttonHoverEffect() -> some View {
        self.modifier(HoverEffect(scale: 1.1))
    }

    func subtleHoverEffect() -> some View {
        self.modifier(HoverEffect(scale: 1.02))
    }

    func hoverColorEffect(active: Color = .primary, inactive: Color = .secondary, scale: CGFloat = 1.0) -> some View {
        self.modifier(HoverColorEffect(activeColor: active, inactiveColor: inactive, scale: scale))
    }
}

// MARK: - Helper for Adaptive Symbol Effects
// Removed: adaptiveSymbolEffect function (unused and requires macOS 15.0+ types)

struct ConditionalFill<S: ShapeStyle>: ViewModifier {
    let condition: Bool
    let primaryStyle: Material
    let fallbackStyle: S

    func body(content: Content) -> some View {
        Group {
            if condition {
                content.foregroundStyle(primaryStyle)
            } else {
                content.foregroundStyle(fallbackStyle)
            }
        }
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
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Delegate for Dock Icon Control

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let mainWindowTitle = "Git Account Switcher"

    /// Controls dock icon visibility dynamically
    /// - Parameter visible: true to show dock icon, false to hide (menu bar only mode)
    static func setDockIconVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            if visible {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Checks if a window is the main app window (not menu bar extra, sheets, or system windows)
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        // Exclude sheets and modal windows
        guard window.sheetParent == nil else { return false }

        // Exclude menu bar extra windows (they have special levels or empty titles)
        guard window.level == .normal else { return false }

        // Check by exact title match
        if window.title == mainWindowTitle {
            return true
        }

        // Check by exact window identifier (SwiftUI Window id)
        // SwiftUI sets identifier like "AppName-Window-main" or similar patterns
        if let identifier = window.identifier?.rawValue {
            // Match exact "main" ID or SwiftUI's pattern with "-main" suffix
            if identifier == "main" || identifier.hasSuffix("-main") {
                return true
            }
        }

        // Also consider Settings window as a dock-worthy window
        if window.title == "Settings" || window.title.contains("Preferences") {
            return true
        }

        return false
    }

    /// Checks if any main windows are currently visible
    private static func hasVisibleMainWindows() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible && isMainWindow(window)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as menu bar only (accessory mode)
        NSApp.setActivationPolicy(.accessory)

        // Observe window visibility changes - use multiple notifications for reliability
        let windowNotifications: [(Notification.Name, Selector)] = [
            (NSWindow.didBecomeMainNotification, #selector(windowDidBecomeVisible(_:))),
            (NSWindow.didBecomeKeyNotification, #selector(windowDidBecomeVisible(_:))),
            (NSWindow.willCloseNotification, #selector(windowWillClose(_:))),
            (NSWindow.didMiniaturizeNotification, #selector(windowDidMiniaturize(_:)))
        ]

        for (name, selector) in windowNotifications {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    @objc private func windowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              AppDelegate.isMainWindow(window) else { return }

        AppDelegate.setDockIconVisible(true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              AppDelegate.isMainWindow(window) else { return }

        // Delay to allow window to fully close before checking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !AppDelegate.hasVisibleMainWindows() {
                AppDelegate.setDockIconVisible(false)
            }
        }
    }

    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              AppDelegate.isMainWindow(window) else { return }

        // When minimized, check if any other main windows are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !AppDelegate.hasVisibleMainWindows() {
                AppDelegate.setDockIconVisible(false)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running in menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When dock icon is clicked, show main window
        AppDelegate.setDockIconVisible(true)
        if !flag {
            // Try to find and show the main window
            if let window = NSApp.windows.first(where: { AppDelegate.isMainWindow($0) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // When app becomes active (e.g., clicked in dock or Cmd+Tab), show dock icon
        if AppDelegate.hasVisibleMainWindows() {
            AppDelegate.setDockIconVisible(true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

