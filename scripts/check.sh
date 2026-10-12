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

swift build --disable-sandbox
"$PROJECT_DIR/.build/debug/ContextEnglishAssistant" --learning-center-layout-self-test
"$PROJECT_DIR/.build/debug/ContextEnglishAssistant" \
    --dictionary-self-test "$PROJECT_DIR/Resources/App/ecdict.sqlite3"
USER_DATA_TEST_DIR="$(mktemp -d -t context-english-user-data-test.XXXXXX)"
trap 'rm -rf "$USER_DATA_TEST_DIR"' EXIT
"$PROJECT_DIR/.build/debug/ContextEnglishAssistant" \
    --user-data-self-test "$USER_DATA_TEST_DIR/user.sqlite3"
sqlite3 "$USER_DATA_TEST_DIR/legacy.sqlite3" \
    "CREATE TABLE favorites (id TEXT PRIMARY KEY, kind TEXT NOT NULL, source_text TEXT NOT NULL, normalized_text TEXT NOT NULL, pronunciation TEXT, meaning TEXT NOT NULL, note TEXT, spoken_text TEXT NOT NULL, source_language TEXT NOT NULL, minimal_context_text TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL, UNIQUE(kind, normalized_text)); INSERT INTO favorites VALUES ('legacy-sentence', 'sentence', 'An existing saved sentence.', 'an existing saved sentence.', NULL, '一条已经收藏的句子。', NULL, 'An existing saved sentence.', 'en', NULL, 1, 1); PRAGMA user_version = 1;"
"$PROJECT_DIR/.build/debug/ContextEnglishAssistant" \
    --user-data-migration-self-test "$USER_DATA_TEST_DIR/legacy.sqlite3"
swift run --disable-sandbox ContextEnglishCoreChecks
python3 "$PROJECT_DIR/services/contextual-translation/server.py" --self-test

if xcrun --find xctest >/dev/null 2>&1; then
  swift test --disable-sandbox
else
  echo "XCTest is unavailable in Command Line Tools; skipped framework-based tests."
fi
