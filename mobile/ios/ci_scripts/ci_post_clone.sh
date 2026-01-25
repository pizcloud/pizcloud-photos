#!/usr/bin/env sh

set -euo pipefail

mkdir -p "$HOME/.appstoreconnect/private_keys"
echo "$APP_STORE_CONNECT_API_KEY_P8_BASE64" | base64 --decode > \
  "$HOME/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
chmod 600 "$HOME/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"

defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# The default execution directory of this script is the ci_scripts directory.
# Derive the repository root if CI_WORKSPACE is not populated in Xcode Cloud.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
WORKSPACE_ROOT="${CI_WORKSPACE:-${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$SCRIPT_DIR/../../.." && pwd -P)}}"
cd "$WORKSPACE_ROOT/mobile" || {
  echo "Unable to cd into mobile directory from workspace root: $WORKSPACE_ROOT" >&2
  exit 1
}

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME"/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Install CocoaPods using Homebrew.
export HOMEBREW_NO_AUTO_UPDATE=1 # disable homebrew's automatic updates.
brew install cocoapods

# Install CocoaPods dependencies.
cd ios && pod install # run `pod install` in the `ios` directory.

exit 0
