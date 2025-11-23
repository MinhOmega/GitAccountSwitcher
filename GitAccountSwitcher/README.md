# Git Account Switcher

A native macOS menu bar app that allows you to quickly switch between multiple GitHub accounts. It updates both your Keychain credentials and git configuration (`user.name`, `user.email`) with a single click.

## Features

- **Menu Bar Interface**: Lives in your menu bar for quick access
- **Keychain Integration**: Automatically updates GitHub credentials in macOS Keychain
- **Git Config Management**: Updates `git config --global user.name` and `user.email`
- **Secure Storage**: Personal Access Tokens are stored securely in Keychain
- **No Dock Icon**: Runs as a background utility (menu bar only)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)
- Git installed at `/usr/bin/git`

## Installation

### Building from Source

1. Open the project in Xcode:
   ```bash
   open GitAccountSwitcher.xcodeproj
   ```

2. Select your Development Team in Xcode:
   - Select the project in the navigator
   - Go to "Signing & Capabilities" tab
   - Select your team from the dropdown

3. Build and run (⌘R)

### Manual Installation

After building, you can find the app at:
- `~/Library/Developer/Xcode/DerivedData/GitAccountSwitcher-xxx/Build/Products/Debug/GitAccountSwitcher.app`

Copy it to your Applications folder for permanent use.

## Usage

### Adding an Account

1. Click the menu bar icon
2. Click "Add Account"
3. Fill in the details:
   - **Display Name**: A friendly name (e.g., "Personal", "Work")
   - **GitHub Username**: Your GitHub username
   - **Personal Access Token**: Your GitHub PAT (see below)
   - **Git User Name**: The name for git commits
   - **Git User Email**: The email for git commits
4. Click "Add"

### Switching Accounts

1. Click the menu bar icon
2. Hover over the account you want to switch to
3. Click "Switch" or double-click the account

The app will:
- Update the GitHub credentials in Keychain
- Update your global git config

### Creating a Personal Access Token (PAT)

1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Give it a name and select scopes:
   - `repo` (for private repositories)
   - `read:user`
   - `user:email`
4. Click "Generate token" and copy it

## How It Works

### Keychain Management

The app modifies the internet password entry for `github.com` in your Keychain. This is the same entry that Git uses when you run `git push` with HTTPS.

**Keychain Entry Details:**
- Kind: Internet password
- Server: github.com
- Protocol: HTTPS
- Account: Your GitHub username

### Git Config Management

The app runs the following commands when switching:
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

## Security

- **No Sandbox**: The app is not sandboxed because it needs:
  - Full Keychain access (to modify GitHub credentials)
  - Process execution (to run git commands)
- **Tokens Encrypted**: Account tokens are stored in the app's own Keychain entries, separate from the GitHub credential
- **Not App Store**: Cannot be distributed on Mac App Store due to sandboxing requirements

## Troubleshooting

### "Keychain item not found"

This error occurs if there's no existing GitHub credential in Keychain. The app will create one when you switch accounts.

### "Git command failed"

Ensure git is installed:
```bash
which git
```

Should return `/usr/bin/git`.

### Credentials not working

1. Verify your PAT is valid on GitHub
2. Check if git credential helper is set correctly:
   ```bash
   git config --global credential.helper
   ```
   Should return `osxkeychain`.

## Project Structure

```
GitAccountSwitcher/
├── GitAccountSwitcherApp.swift    # Main app with MenuBarExtra
├── Models/
│   └── GitAccount.swift           # Account data model
├── Services/
│   ├── KeychainService.swift      # Keychain operations
│   ├── GitConfigService.swift     # Git config management
│   └── AccountStore.swift         # Account persistence
├── Views/
│   ├── AccountListView.swift      # Main menu content
│   └── AddEditAccountView.swift   # Account editor
├── Assets.xcassets/               # App icons
├── Info.plist                     # App configuration
└── GitAccountSwitcher.entitlements
```

## License

MIT License - Feel free to modify and distribute.

## Acknowledgments

- Built with SwiftUI and the Security framework
- Uses native macOS Keychain Services API
