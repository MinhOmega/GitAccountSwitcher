# Changelog

All notable changes to GitAccountSwitcher will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

#### Runtime Stability

- **CRITICAL: Fixed App Crash on Launch** (GitAccountSwitcherApp.swift:13-20)
  - Removed `setupAppearance()` function that was accessing `NSApp` during `App.init()`
  - `NSApp` is not available during SwiftUI App initialization, causing fatal crashes
  - Previous implementation attempted to set `.vibrantDark` appearance (which doesn't exist)
  - **Impact**: App now launches successfully without crashing
  - **Compatibility**: Works on macOS 13.0+ (deployment target)

#### macOS Version Compatibility (Build Fixes)

- **Fixed SwiftUI Symbol Effects Compatibility** (GitAccountSwitcherApp.swift:1187-1188, 269-283)
  - Removed unused `adaptiveSymbolEffect` function that required macOS 15.0+ types (`SymbolEffectOptionsRepeatBehavior`)
  - Changed `.bounce` symbol effect from macOS 14.0+ to macOS 15.0+ availability check
  - Added fallback `.pulse` effect for macOS 14.0-14.9
  - **Impact**: Fixes Release build errors and ensures compatibility with macOS 13.0+ deployment target

- **Fixed Color API Compatibility** (AddEditAccountView.swift:218)
  - Replaced `.accent` color (macOS 14.0+) with `.blue` for token help button hover state
  - **Impact**: Ensures color rendering works on macOS 13.0+

- **Fixed SwiftUI Background API Compatibility** (AddEditAccountView.swift:114-134, 509)
  - Replaced trailing closure `.background { }` syntax (macOS 14.0+) with compatible alternatives
  - Used conditional `Group` with separate `.background()` calls for main form
  - Used `AnyShapeStyle` type erasure for TokenHelpView background
  - **Impact**: Fixes "no exact matches in call to instance method 'background'" errors

### Security

#### Critical Security Fixes (Post-Review)

- **CRITICAL: Fixed URL Construction Vulnerability** (GitConfigService.swift:95-97)
  - Replaced unsafe `URL(string: "file://\(path)")` with `URL(fileURLWithPath:)` to prevent URL injection attacks
  - Previous implementation was vulnerable to special characters (#, ?, spaces) in file paths
  - Attackers could bypass code signature verification by using crafted path names
  - **Impact**: Prevents complete bypass of git binary signature verification

- **HIGH: Fixed Ineffective Secure Memory Zeroing** (ValidationUtilities.swift:156-184)
  - Replaced unsafe String.withUTF8 approach with NSMutableData-based implementation
  - Now uses `memset_s` (secure memset) which compiler cannot optimize away
  - Previous implementation had undefined behavior due to Swift copy-on-write semantics
  - **Impact**: Properly zeros token memory to prevent leakage via memory dumps/swap files

- **HIGH: Fixed Biometric Authentication Bypass** (AccountStore.swift:323-329, AddEditAccountView.swift:293-306)
  - Changed `getAccountWithToken()` to async and require biometric authentication
  - Updated AddEditAccountView to use authenticated token retrieval
  - Previous implementation allowed viewing tokens via edit flow without authentication
  - **Impact**: All token access now requires Touch ID/Face ID or device password

### Added

#### Security Enhancements
- **Git Binary Code Signature Verification** (GitConfigService.swift:85-112)
  - Added `isValidGitBinary()` method to validate code signatures using macOS Security framework
  - Prevents execution of tampered or malicious git binaries
  - Validates both Apple-signed git and valid Developer ID certificates (Homebrew)
  - Git path discovery now throws `GitConfigError.gitNotFound` if binary signature is invalid

- **Biometric Authentication for Token Access** (KeychainService.swift:48-78)
  - Added `authenticateWithBiometrics()` method using LocalAuthentication framework
  - New `retrieveAccountTokenWithAuth()` async method requires Touch ID/Face ID before token retrieval
  - Automatically falls back to device password if biometrics unavailable
  - Integrated with AccountStore.switchToAccount() for secure account switching (AccountStore.swift:139-142)

- **Transaction Rollback for Account Switching** (AccountStore.swift:122-177)
  - Implemented `AccountSwitchSnapshot` struct to capture system state before switches
  - Added `captureCurrentState()` method to save GitHub credentials, git config, and active account state
  - Added `rollbackToState()` method to restore previous state on operation failure
  - Automatic rollback prevents inconsistent system state when account switches fail mid-operation

- **Secure Token Memory Zeroing** (ValidationUtilities.swift:146-172)
  - Added `secureZeroString()` utility function for cryptographic memory clearing
  - Uses `withUTF8` and `memset` to overwrite sensitive data in memory
  - Integrated into AddEditAccountView to securely clear tokens on view dismissal (line 117) and after save (line 307)
  - Prevents token leakage through memory dumps or swap files

### Changed

#### Architecture & Performance
- **Enhanced Git Path Caching** (GitConfigService.swift:37-83)
  - Git path discovery now throwing computed property instead of non-throwing
  - Added code signature validation to git path caching mechanism
  - Updated `isGitAvailable` to handle throwing git path access (line 321-328)
  - Updated `runGitCommand()` to use validated git path (line 258)

#### Error Handling
- Added `KeychainError.biometricAuthFailed(String)` for authentication failures
- Added `GitConfigError.invalidGitBinary(String)` for code signature validation failures
- Enhanced error messages with detailed failure reasons

### Fixed
- **Memory Security**: Token strings now securely zeroed instead of simple assignment
- **Process Security**: Git binary integrity verified before execution
- **Transaction Safety**: Account switching operations now atomic with automatic rollback
- **Authentication**: Token retrieval protected by biometric authentication

### Dependencies
- Added `import Security` to GitConfigService.swift for code signature verification
- Added `import LocalAuthentication` to KeychainService.swift for biometric authentication

## [0.1.0] - 2025-01-24

### Initial Release

#### Core Features
- Multiple GitHub account management with macOS Keychain integration
- One-click account switching with automatic git config updates
- Menu bar application with native macOS UI (SwiftUI)
- Secure token storage using macOS Keychain Services

#### Security Foundation
- Token exclusion from Codable serialization (GitAccount.swift:51-83)
- CustomDebugStringConvertible for token redaction (GitAccount.swift:87-109)
- Centralized input validation (ValidationUtilities.swift)
- Control character filtering for git config values
- Path traversal prevention for git config keys
- Environment variable sanitization for git subprocess execution
- Error message sanitization to prevent information disclosure

#### Architecture
- MVVM architecture with SwiftUI
- Swift 6 concurrency with @MainActor and async/await
- Task-based serialization for account switching operations
- Performance-optimized caching (git path, active account)
- Dual Keychain storage pattern (system + app-specific)

#### Known Limitations
- macOS only (requires macOS Keychain Services)
- Git must be installed and available in PATH
- Requires valid code-signed git binary
- Biometric authentication requires Touch ID/Face ID or device password

---

## Legend

- **Added**: New features or functionality
- **Changed**: Changes to existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements or vulnerability fixes
