#!/bin/bash
#
# Sync Xcode Project
# This script regenerates the Xcode project from project.yml
# Run this anytime you add/remove files in VSCode or command line

set -e

echo "🔄 Regenerating Xcode project from project.yml..."
xcodegen generate

echo "✅ Done! All files in GitAccountSwitcher/ are now synced to the Xcode project."
echo ""
echo "You can now:"
echo "  • Open the project: open GitAccountSwitcher.xcodeproj"
echo "  • Build: xcodebuild -project GitAccountSwitcher.xcodeproj -scheme GitAccountSwitcher build"
