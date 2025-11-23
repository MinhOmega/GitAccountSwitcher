# AGENTS.md
This file provides guidance to AI coding assistants working in this repository.

**Note:** CLAUDE.md, .clinerules, .cursorrules, .windsurfrules, .replit.md, GEMINI.md, .github/copilot-instructions.md, and .idx/airules.md are symlinks to AGENTS.md in this project.

# Git Account Switcher

A native macOS menu bar application that allows users to quickly switch between multiple GitHub accounts. It updates both macOS Keychain credentials and git configuration (`user.name`, `user.email`) with a single click.

## Project Overview

- **Type**: Native macOS application
- **Language**: Swift 5.9+
- **Framework**: SwiftUI
- **Platform**: macOS 13.0 (Ventura) or later
- **Architecture**: MVVM with Service layer pattern
- **Build Tool**: Xcode 15.0+

### Key Features
- Menu bar interface for quick access
- Keychain integration for secure credential storage
- Git config management (`user.name`, `user.email`)
- Personal Access Token (PAT) secure storage
- Launch at login support
- Native macOS notifications

## Build & Commands

### Xcode Build Commands

```bash
# Open project in Xcode
open GitAccountSwitcher/GitAccountSwitcher.xcodeproj

# Build from command line (Debug)
xcodebuild -project GitAccountSwitcher/GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Debug \
  build

# Build from command line (Release)
xcodebuild -project GitAccountSwitcher/GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Release \
  build

# Clean build folder
xcodebuild -project GitAccountSwitcher/GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  clean

# Build and run (use Xcode: Cmd+R)
```

### Build Output Location
- Debug: `~/Library/Developer/Xcode/DerivedData/GitAccountSwitcher-xxx/Build/Products/Debug/GitAccountSwitcher.app`
- Release: `~/Library/Developer/Xcode/DerivedData/GitAccountSwitcher-xxx/Build/Products/Release/GitAccountSwitcher.app`

### Requirements Verification

```bash
# Check Xcode version
xcodebuild -version

# Check Swift version
swift --version

# Verify git installation
which git
# Should return /usr/bin/git or /opt/homebrew/bin/git

# Check git credential helper
git config --global credential.helper
# Should return osxkeychain
```

## Code Style

### Swift Conventions

**File Organization:**
- Use `// MARK: - Section Name` comments to organize code sections
- Order: Properties, Initializers, Body/Methods, Private methods, Extensions

**Naming Conventions:**
- `camelCase` for variables, functions, and parameters
- `PascalCase` for types (structs, classes, enums, protocols)
- Prefix private properties/methods with `private` keyword
- Use descriptive names that explain intent

**Type Safety:**
- Use strong typing throughout
- Avoid force unwrapping (`!`) - use optional binding or guard statements
- Use `Codable` for serialization
- Implement `Identifiable`, `Equatable`, `Hashable` protocols where appropriate

**SwiftUI Patterns:**
```swift
// State management
@StateObject private var store = Store()        // Owned observable
@EnvironmentObject var store: Store             // Injected observable
@State private var isLoading = false            // Local view state
@Published private(set) var data: [Item] = []   // Observable property

// View composition
@ViewBuilder
private var conditionalView: some View {
    if condition {
        SomeView()
    } else {
        OtherView()
    }
}

// Thread safety
@MainActor
final class Store: ObservableObject { ... }
```

**Error Handling:**
```swift
// Custom error enums with LocalizedError
enum ServiceError: LocalizedError {
    case itemNotFound
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
}

// Async/await with proper error propagation
func performOperation() async throws {
    // Use try/catch for error handling
    do {
        try await someAsyncWork()
    } catch {
        throw ServiceError.operationFailed(error.localizedDescription)
    }
}
```

**Documentation:**
```swift
/// Triple-slash comments for public APIs
/// - Parameter name: Description of parameter
/// - Returns: Description of return value
/// - Throws: Description of possible errors
func publicMethod(name: String) throws -> Result { ... }
```

### Import Order
1. Foundation/SwiftUI (Apple frameworks)
2. System frameworks (Security, ServiceManagement, etc.)
3. Third-party dependencies (if any)

### Formatting Rules
- 4 spaces for indentation (Xcode default)
- Opening braces on same line
- One blank line between methods
- No trailing whitespace
- Maximum line length: 120 characters (soft limit)

## Project Structure

```
GitAccountSwitcher/
├── GitAccountSwitcher/
│   ├── GitAccountSwitcherApp.swift    # Main app entry point with MenuBarExtra
│   ├── Models/
│   │   └── GitAccount.swift           # Account data model (Codable)
│   ├── Services/
│   │   ├── KeychainService.swift      # macOS Keychain operations
│   │   ├── GitConfigService.swift     # Git command execution
│   │   └── AccountStore.swift         # Account state management
│   ├── Views/
│   │   ├── AccountListView.swift      # Main menu content
│   │   └── AddEditAccountView.swift   # Account editor form
│   ├── Assets.xcassets/               # App icons and resources
│   ├── Info.plist                     # App configuration
│   └── GitAccountSwitcher.entitlements
├── GitAccountSwitcher.xcodeproj/      # Xcode project file
├── README.md                          # Project documentation
└── docs/                              # Additional documentation
```

### Service Layer Pattern

**KeychainService** (Singleton):
- Manages macOS Keychain operations
- Stores/retrieves GitHub credentials
- Stores app-specific account tokens separately

**GitConfigService** (Singleton):
- Executes git commands via Process API
- Manages global git configuration
- Reads/writes `user.name` and `user.email`

**AccountStore** (ObservableObject):
- Main state container for UI
- Persists account data to UserDefaults
- Coordinates between Keychain and Git services

## Testing

### Manual Testing Checklist

Since this is a native macOS app without automated tests currently:

1. **Account Management:**
   - Add new account with valid PAT
   - Edit existing account
   - Delete account
   - Verify Keychain entries updated

2. **Account Switching:**
   - Switch between accounts
   - Verify git config updated (`git config --global user.name`)
   - Verify Keychain credential updated
   - Check notification appears (if enabled)

3. **UI Testing:**
   - Menu bar icon displays correctly
   - Main window opens and closes
   - Settings window functions properly
   - Launch at login toggle works

4. **Edge Cases:**
   - No accounts configured
   - Invalid PAT token
   - Missing git installation
   - Keychain access denied

### Verification Commands

```bash
# Verify git config after switch
git config --global user.name
git config --global user.email

# Check Keychain entries (via Keychain Access app)
# Look for github.com internet passwords

# Verify credential helper
git credential-osxkeychain get <<EOF
protocol=https
host=github.com
EOF
```

### Testing Philosophy
**When tests fail, fix the code, not the test.**

Key principles:
- Tests should be meaningful - Avoid tests that always pass regardless of behavior
- Test actual functionality - Call the functions being tested
- Failing tests are valuable - They reveal bugs or missing features
- Fix the root cause - When a test fails, fix the underlying issue

## Security

### Keychain Security
- PAT tokens are stored encrypted in macOS Keychain
- App uses `kSecClassInternetPassword` for GitHub credentials
- App uses `kSecClassGenericPassword` for internal account storage
- Tokens never stored in plain text or UserDefaults

### App Entitlements
- **Not sandboxed** - Required for:
  - Full Keychain access (modify GitHub credentials)
  - Process execution (run git commands)
- **Cannot be distributed on Mac App Store** due to sandboxing requirements

### Security Best Practices
- Never log or print PAT tokens
- Use secure string comparison for token validation
- Clear sensitive data from memory when no longer needed
- Validate all user input before Keychain operations

### Personal Access Token Requirements
Required GitHub PAT scopes:
- `repo` (for private repositories)
- `read:user`
- `user:email`

## Configuration

### Development Environment Setup

1. **Install Xcode 15.0+** from Mac App Store or Apple Developer site
2. **Open the project:**
   ```bash
   open GitAccountSwitcher/GitAccountSwitcher.xcodeproj
   ```
3. **Configure signing:**
   - Select project in navigator
   - Go to "Signing & Capabilities"
   - Select your Development Team

4. **Build and run:** Press Cmd+R

### App Configuration Files
- `Info.plist` - Bundle configuration, background mode settings
- `GitAccountSwitcher.entitlements` - App capabilities and permissions

### Git Configuration
The app modifies these git config values:
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

Requires git credential helper:
```bash
git config --global credential.helper osxkeychain
```

## Directory Structure & File Organization

### Reports Directory
ALL project reports and documentation should be saved to the `reports/` directory:

```
git-app/
├── reports/              # All project reports and documentation
│   └── *.md             # Various report types
├── temp/                # Temporary files and debugging
├── GitAccountSwitcher/  # Main application source
└── .claude/             # Claude Code configuration
```

### Report Generation Guidelines
**Important**: ALL reports should be saved to the `reports/` directory with descriptive names:

**Implementation Reports:**
- Phase validation: `PHASE_X_VALIDATION_REPORT.md`
- Implementation summaries: `IMPLEMENTATION_SUMMARY_[FEATURE].md`
- Feature completion: `FEATURE_[NAME]_REPORT.md`

**Testing & Analysis Reports:**
- Test results: `TEST_RESULTS_[DATE].md`
- Coverage reports: `COVERAGE_REPORT_[DATE].md`
- Performance analysis: `PERFORMANCE_ANALYSIS_[SCENARIO].md`
- Security scans: `SECURITY_SCAN_[DATE].md`

**Quality & Validation:**
- Code quality: `CODE_QUALITY_REPORT.md`
- Build reports: `BUILD_REPORT_[DATE].md`

**Report Naming Conventions:**
- Use descriptive names: `[TYPE]_[SCOPE]_[DATE].md`
- Include dates: `YYYY-MM-DD` format
- Group with prefixes: `TEST_`, `PERFORMANCE_`, `SECURITY_`
- Markdown format: All reports end in `.md`

### Temporary Files & Debugging
All temporary files, debugging scripts, and test artifacts should be organized in a `/temp` folder:

**Temporary File Organization:**
- **Debug scripts**: `temp/debug-*.swift`, `temp/analyze-*.py`
- **Test artifacts**: `temp/test-results/`, `temp/build-logs/`
- **Generated files**: `temp/generated/`
- **Logs**: `temp/logs/`

**Guidelines:**
- Never commit files from `/temp` directory
- Use `/temp` for all debugging and analysis scripts created during development
- Clean up `/temp` directory regularly
- Include `/temp/` in `.gitignore` to prevent accidental commits

### Claude Code Settings (.claude Directory)

The `.claude` directory contains Claude Code configuration files with specific version control rules:

#### Version Controlled Files (commit these):
- `.claude/settings.json` - Shared team settings for hooks, tools, and environment
- `.claude/commands/*.md` - Custom slash commands available to all team members
- `.claude/agents/*.md` - Specialized AI agent definitions
- `.claude/skills/*.md` - AI skills documentation

#### Ignored Files (do NOT commit):
- `.claude/settings.local.json` - Personal preferences and local overrides
- Any `*.local.json` files - Personal configuration not meant for sharing

**Note:** This project has `.claude/` in `.gitignore` for security reasons (PAT tokens, etc.).

## Agent Delegation & Tool Execution

### Available AI Subagents

This project has 39 specialized AI agents available in `.claude/agents/`:

**Core Development:**
- `typescript-expert.md` - TypeScript/JavaScript specialist
- `react-expert.md` - React frontend development
- `nodejs-expert.md` - Node.js backend

**Testing & Quality:**
- `testing-expert.md` - General testing guidance
- `code-review-expert.md` - Code review and quality
- `code-review-guardian.md` - Automated code review

**Infrastructure:**
- `git-expert.md` - Git operations and workflows
- `devops-expert.md` - DevOps and deployment
- `infrastructure-docker-expert.md` - Docker containerization

**Documentation:**
- `documentation-expert.md` - Documentation structure and quality

### MANDATORY: Always Delegate to Specialists

**When specialized agents are available, you MUST use them instead of attempting tasks yourself.**

#### Why Agent Delegation Matters:
- Specialists have deeper, more focused knowledge
- They're aware of edge cases and subtle bugs
- They follow established patterns and best practices
- They can provide more comprehensive solutions

### Always Use Parallel Tool Calls

**IMPORTANT: Send all tool calls in a single message to execute them in parallel.**

**These cases MUST use parallel tool calls:**
- Searching for different patterns (imports, usage, definitions)
- Multiple grep searches with different regex patterns
- Reading multiple files or searching different directories
- Agent delegations with multiple Task calls to different specialists

**Sequential calls ONLY when:**
You genuinely REQUIRE the output of one tool to determine the usage of the next tool.

**Performance Impact:** Parallel tool execution is 3-5x faster than sequential calls.

## Troubleshooting

### Common Issues

**"Keychain item not found"**
- The app will create the GitHub credential when you switch accounts
- No action needed - this is expected on first use

**"Git command failed"**
- Verify git is installed: `which git`
- Should return `/usr/bin/git` or `/opt/homebrew/bin/git`

**Credentials not working**
1. Verify PAT is valid on GitHub
2. Check credential helper: `git config --global credential.helper`
   - Should return `osxkeychain`

**Build failures**
- Ensure Xcode 15.0+ is installed
- Check that signing team is configured
- Clean build folder and rebuild

## License

MIT License - Feel free to modify and distribute.
