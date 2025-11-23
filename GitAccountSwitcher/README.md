# Git Account Switcher

<p align="center">
  <img src="docs/icon.png" alt="Git Account Switcher Icon" width="128" height="128">
</p>

<p align="center">
  <strong>A native macOS menu bar app for seamlessly switching between multiple GitHub accounts</strong>
</p>

<p align="center">
  <a href="#features">Features</a> |
  <a href="#installation">Installation</a> |
  <a href="#usage">Usage</a> |
  <a href="#how-it-works">How It Works</a> |
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Features

- **Menu Bar Interface** - Lives in your menu bar for instant access
- **One-Click Switching** - Switch accounts with a single click
- **Keychain Integration** - Automatically updates GitHub credentials in macOS Keychain
- **Git Config Management** - Updates `git config --global user.name` and `user.email`
- **Secure Storage** - Personal Access Tokens stored securely in Keychain (never in plain text)
- **Launch at Login** - Optionally start automatically when you log in
- **Native Notifications** - Get notified when account switches complete
- **No Dock Icon** - Runs as a background utility (menu bar only)
- **Dark Mode Support** - Follows your system appearance

## Requirements

- **macOS 13.0** (Ventura) or later
- **Xcode 15.0** or later (for building from source)
- **Git** installed (typically at `/usr/bin/git` or via Homebrew)
- **GitHub CLI** (optional, for repository setup)

## Installation

### Option 1: Build from Command Line (Recommended)

```bash
# Clone the repository
git clone https://github.com/MinhOmega/GitAccountSwitcher.git
cd GitAccountSwitcher/GitAccountSwitcher

# Build the app (Release configuration)
xcodebuild -project GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Release \
  -derivedDataPath build \
  build

# Copy to Applications folder
cp -R build/Build/Products/Release/GitAccountSwitcher.app /Applications/

# Launch the app
open /Applications/GitAccountSwitcher.app
```

### Option 2: Build with Xcode

```bash
# Clone the repository
git clone https://github.com/MinhOmega/GitAccountSwitcher.git
cd GitAccountSwitcher/GitAccountSwitcher

# Open in Xcode
open GitAccountSwitcher.xcodeproj
```

Then in Xcode:
1. Select your **Development Team** in Project Settings > Signing & Capabilities
2. Select **Product > Archive** for a release build, or press **Cmd+R** to build and run
3. For Archive: **Distribute App > Copy App** to export the `.app` file

### Option 3: One-Line Install Script

```bash
# Clone, build, and install in one command
git clone https://github.com/MinhOmega/GitAccountSwitcher.git && \
cd GitAccountSwitcher/GitAccountSwitcher && \
xcodebuild -project GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Release \
  -derivedDataPath build \
  build && \
cp -R build/Build/Products/Release/GitAccountSwitcher.app /Applications/ && \
open /Applications/GitAccountSwitcher.app
```

### Verify Installation

```bash
# Check if the app is installed
ls -la /Applications/GitAccountSwitcher.app

# Check if it's running
pgrep -l GitAccountSwitcher
```

### Uninstall

```bash
# Remove the app
rm -rf /Applications/GitAccountSwitcher.app

# Remove app data (optional)
rm -rf ~/Library/Application\ Support/GitAccountSwitcher
rm -rf ~/Library/Preferences/com.gitaccountswitcher.plist

# Remove from Login Items (if enabled)
# System Settings > General > Login Items > Remove GitAccountSwitcher
```

## Usage

### Adding an Account

1. Click the menu bar icon (shows current account or question mark if none)
2. Click **"Add Account"** or the **+** button
3. Fill in the details:
   - **Display Name**: A friendly name (e.g., "Personal", "Work", "Client-X")
   - **GitHub Username**: Your GitHub username
   - **Personal Access Token**: Your GitHub PAT ([create one here](#creating-a-personal-access-token))
   - **Git User Name**: The name for git commits (can differ from GitHub username)
   - **Git User Email**: The email for git commits
4. Click **"Add"**

### Switching Accounts

**From Menu Bar:**
1. Click the menu bar icon
2. Click on the account you want to switch to

**From Main Window:**
1. Click menu bar icon > **"Open Window"**
2. Click **"Switch"** button on any account card

When you switch accounts, the app will:
- Update GitHub credentials in macOS Keychain
- Run `git config --global user.name "Your Name"`
- Run `git config --global user.email "your@email.com"`
- Show a notification (if enabled)

### Managing Accounts

- **Edit**: Click the **...** menu on any account card > **Edit**
- **Delete**: Click the **...** menu > **Delete**
- **Reorder**: Open Settings > Accounts tab (drag to reorder coming soon)

### Settings

Access Settings via:
- Menu bar > gear icon, or
- Main window > gear icon in footer, or
- **Cmd+,** when the app is focused

**General Settings:**
- Show notification on account switch
- Launch at login

### Creating a Personal Access Token

1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Click **"Generate new token (classic)"** or **"Fine-grained tokens"**

**For Classic Tokens:**
Select these scopes:
- `repo` - Full control of private repositories
- `read:user` - Read user profile data
- `user:email` - Access user email addresses

**For Fine-grained Tokens:**
- Repository access: All repositories (or select specific ones)
- Permissions: Contents (Read and write), Metadata (Read)

3. Click **"Generate token"** and **copy it immediately** (you won't see it again!)

## How It Works

### Keychain Management

The app manages GitHub credentials using the macOS Keychain Services API:

```
Keychain Entry:
├── Kind: Internet password
├── Server: github.com
├── Protocol: HTTPS
├── Account: <your-github-username>
└── Password: <your-personal-access-token>
```

This is the same entry that Git's credential helper (`osxkeychain`) uses when you run `git push` with HTTPS.

**App's Own Storage:**
Account metadata (display name, emails) is stored in the app's private Keychain entries, separate from the GitHub credential.

### Git Config Management

When switching accounts, the app executes:

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

This updates `~/.gitconfig`:

```ini
[user]
    name = Your Name
    email = your@email.com
```

### Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Git Account Switcher                  │
├─────────────────────────────────────────────────────────┤
│  AccountStore (ObservableObject)                        │
│  - Coordinates all operations                           │
│  - Persists account metadata to UserDefaults            │
│  - DOES NOT store tokens in UserDefaults                │
├─────────────────────────────────────────────────────────┤
│  KeychainService (Singleton)                            │
│  - Stores/retrieves tokens from macOS Keychain          │
│  - Uses Security.framework APIs                         │
│  - Tokens encrypted at rest by macOS                    │
├─────────────────────────────────────────────────────────┤
│  GitConfigService (Singleton)                           │
│  - Executes git commands via Process API                │
│  - Manages global git configuration                     │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
GitAccountSwitcher/
├── GitAccountSwitcher.xcodeproj/     # Xcode project file
├── GitAccountSwitcher/
│   ├── GitAccountSwitcherApp.swift   # App entry point, MenuBarExtra, Windows
│   ├── Models/
│   │   └── GitAccount.swift          # Account data model (Codable)
│   ├── Services/
│   │   ├── KeychainService.swift     # macOS Keychain operations
│   │   ├── GitConfigService.swift    # Git command execution
│   │   └── AccountStore.swift        # State management (@MainActor)
│   ├── Views/
│   │   └── AddEditAccountView.swift  # Account form UI
│   ├── Assets.xcassets/              # App icons and colors
│   ├── Info.plist                    # Bundle configuration
│   └── GitAccountSwitcher.entitlements
├── docs/                             # Documentation assets
├── build/                            # Build output (gitignored)
└── README.md                         # This file
```

## Troubleshooting

### "Keychain item not found"

**Cause:** No existing GitHub credential in Keychain.

**Solution:** This is normal for first-time use. The app will create the credential when you switch to an account.

### "Git command failed"

**Cause:** Git is not installed or not in expected location.

**Solution:**
```bash
# Check git installation
which git
# Expected: /usr/bin/git or /opt/homebrew/bin/git

# If not installed, install via Homebrew
brew install git

# Or install Xcode Command Line Tools
xcode-select --install
```

### Credentials not working after switch

**Cause:** Git credential helper not configured.

**Solution:**
```bash
# Check current credential helper
git config --global credential.helper
# Expected: osxkeychain

# If not set, configure it
git config --global credential.helper osxkeychain
```

### "The operation couldn't be completed" (Keychain error)

**Cause:** Keychain access denied or locked.

**Solution:**
1. Open **Keychain Access** app
2. Make sure your login keychain is unlocked
3. Try removing any existing `github.com` entries and let the app recreate them

### App doesn't appear in menu bar

**Cause:** App crashed or system UI issue.

**Solution:**
```bash
# Force quit and restart
pkill GitAccountSwitcher
open /Applications/GitAccountSwitcher.app

# Check Console.app for crash logs
open /Applications/Utilities/Console.app
```

### Build Errors

**"Signing requires a development team"**
- Open project in Xcode
- Select your team in Signing & Capabilities
- Or build with `CODE_SIGNING_ALLOWED=NO` for local testing:
  ```bash
  xcodebuild -project GitAccountSwitcher.xcodeproj \
    -scheme GitAccountSwitcher \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
  ```

**"No provisioning profile"**
- Sign in with Apple ID in Xcode > Settings > Accounts
- Select "Personal Team" for local development

## Security Considerations

### Why Not Sandboxed?

The app requires these capabilities that are incompatible with App Store sandboxing:

1. **Full Keychain Access** - Modify GitHub internet password entries
2. **Process Execution** - Run `git` commands via shell
3. **File System Access** - Read/write `~/.gitconfig`

### Token Security

- Tokens are stored in macOS Keychain (encrypted at rest)
- Tokens are never logged or stored in plain text
- Tokens are never stored in UserDefaults or plist files
- Each account's token is stored in a separate Keychain entry

### Best Practices

1. **Use fine-grained tokens** with minimal required permissions
2. **Set token expiration** dates (GitHub recommends 90 days or less)
3. **Rotate tokens regularly** - Update tokens in the app when you regenerate them
4. **Review Keychain Access** - Periodically check what apps have Keychain access

## Development

### Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

### Building for Development

```bash
# Debug build
xcodebuild -project GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Debug \
  build

# Run tests (when available)
xcodebuild -project GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  test
```

### Code Style

- SwiftUI with MVVM architecture
- `@MainActor` for UI-related code
- `async/await` for asynchronous operations
- `// MARK: -` comments for code organization
- Triple-slash (`///`) documentation for public APIs

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## License

MIT License - Feel free to modify and distribute.

## Acknowledgments

- Built with SwiftUI and the Security framework
- Uses native macOS Keychain Services API
- Icons from SF Symbols

---

<p align="center">
  Made with ❤️ for developers who work with multiple GitHub accounts
</p>
