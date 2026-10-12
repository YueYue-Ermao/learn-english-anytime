#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] \
    && [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swift-module-cache"

swift build --disable-sandbox -c release --product ContextEnglishAssistant

BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Context English Assistant.app"
CONTENTS_DIR="$APP_DIR/Contents"
ZIP_PATH="$PROJECT_DIR/dist/Context-English-Assistant-v0.6.0-arm64.zip"

rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"
install -d "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
install -m 755 "$BIN_DIR/ContextEnglishAssistant" "$CONTENTS_DIR/MacOS/ContextEnglishAssistant"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$PROJECT_DIR/Resources/App" "$CONTENTS_DIR/Resources"

codesign --force --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "$APP_DIR"
