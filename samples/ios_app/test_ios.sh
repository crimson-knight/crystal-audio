#!/usr/bin/env bash
# test_ios.sh — Automated build + test for Crystal Audio iOS app
#
# Usage: ./samples/ios_app/test_ios.sh
#
# This script:
#   1. Cross-compiles crystal_bridge.cr with tracing
#   2. Strips _main symbol to avoid linker conflict
#   3. Packs static library
#   4. Builds Xcode project
#   5. Installs on booted simulator
#   6. Launches with CRYSTAL_AUTO_TEST=1 (auto-starts recording)
#   7. Captures console output for 8 seconds
#   8. Reports pass/fail based on crash logs and trace output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
BUNDLE_ID="com.crimsonknight.CrystalAudioDemo"

info()  { printf '\033[0;34m[test]\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m[PASS]\033[0m %s\n' "$*"; }
fail()  { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Step 1: Cross-compile
# ---------------------------------------------------------------------------
info "Cross-compiling crystal_bridge.cr ..."
cd "$REPO_ROOT"
crystal-alpha build samples/ios_app/crystal_bridge.cr \
    --cross-compile \
    --target "arm64-apple-ios-simulator" \
    --define ios \
    --define shared \
    --release \
    -o "$BUILD_DIR/crystal_bridge" 2>&1 | head -5

# ---------------------------------------------------------------------------
# Step 2: Strip _main to local symbol
# ---------------------------------------------------------------------------
info "Making _main local symbol ..."
cd "$BUILD_DIR"
ld -r -arch arm64 crystal_bridge.o -o crystal_bridge_nomain.o -unexported_symbol _main 2>&1
mv crystal_bridge_nomain.o crystal_bridge.o

# Verify _main is local
MAIN_TYPE=$(nm crystal_bridge.o 2>/dev/null | grep "_main$" | awk '{print $2}')
if [ "$MAIN_TYPE" = "t" ]; then
    ok "_main is local (t)"
else
    fail "_main is still global: $MAIN_TYPE"
fi

# ---------------------------------------------------------------------------
# Step 3: Pack static library
# ---------------------------------------------------------------------------
info "Packing libcrystal_audio.a ..."
ar rcs "$BUILD_DIR/libcrystal_audio.a" \
    "$BUILD_DIR/crystal_bridge.o" \
    "$BUILD_DIR/block_bridge.o" \
    "$BUILD_DIR/objc_helpers.o" \
    "$BUILD_DIR/audio_write_helper.o"

# ---------------------------------------------------------------------------
# Step 4: Build Xcode project
# ---------------------------------------------------------------------------
info "Building Xcode project ..."
cd "$SCRIPT_DIR"
xcodegen generate 2>&1 | tail -1
BUILD_OUTPUT=$(xcodebuild \
    -project CrystalAudioDemo.xcodeproj \
    -scheme CrystalAudioDemo \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.4' \
    -configuration Debug \
    -derivedDataPath build/DerivedData \
    build 2>&1)

if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
    ok "Xcode build succeeded"
else
    fail "Xcode build failed"
    echo "$BUILD_OUTPUT" | grep -E "(error:|BUILD)" | tail -10
    exit 1
fi

# Check for duplicate _main warning
if echo "$BUILD_OUTPUT" | grep -q "duplicate symbol.*_main"; then
    fail "Duplicate _main symbol detected!"
else
    ok "No duplicate _main"
fi

# ---------------------------------------------------------------------------
# Step 5: Install on simulator
# ---------------------------------------------------------------------------
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "CrystalAudioDemo.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    fail "Could not find built .app"
    exit 1
fi

info "Installing on simulator ..."
xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
sleep 1
xcrun simctl install booted "$APP_PATH"
ok "Installed"

# ---------------------------------------------------------------------------
# Step 6: Launch with auto-test and capture console
# ---------------------------------------------------------------------------
info "Launching with CRYSTAL_AUTO_TEST=1 ..."
CRASH_COUNT_BEFORE=$(ls ~/Library/Logs/DiagnosticReports/CrystalAudioDemo-*.ips 2>/dev/null | wc -l | tr -d ' ')

# Start log stream in background to capture CRYSTAL_TRACE messages
LOG_FILE="/tmp/crystal_ios_test_$(date +%s).log"
xcrun simctl spawn booted log stream --predicate 'process == "CrystalAudioDemo"' --level debug > "$LOG_FILE" 2>&1 &
LOG_PID=$!

sleep 1

# Launch the app with auto-test env var
LAUNCH_OUTPUT=$(xcrun simctl launch --console-pty booted "$BUNDLE_ID" 2>&1 &)
APP_PID=$(xcrun simctl launch booted "$BUNDLE_ID" 2>&1 | grep -oE '[0-9]+$' || echo "unknown")
info "App PID: $APP_PID"

# Wait for auto-test to trigger (2s delay + some buffer)
info "Waiting 8 seconds for auto-test ..."
sleep 8

# ---------------------------------------------------------------------------
# Step 7: Check results
# ---------------------------------------------------------------------------
kill $LOG_PID 2>/dev/null || true

# Check if process is still alive
if ps -p "$APP_PID" > /dev/null 2>&1; then
    ok "App is still running (PID $APP_PID)"
else
    fail "App crashed or exited (PID $APP_PID gone)"
fi

# Check for new crash logs
CRASH_COUNT_AFTER=$(ls ~/Library/Logs/DiagnosticReports/CrystalAudioDemo-*.ips 2>/dev/null | wc -l | tr -d ' ')
NEW_CRASHES=$((CRASH_COUNT_AFTER - CRASH_COUNT_BEFORE))

if [ "$NEW_CRASHES" -gt 0 ]; then
    fail "$NEW_CRASHES new crash report(s)!"
    LATEST_CRASH=$(ls -t ~/Library/Logs/DiagnosticReports/CrystalAudioDemo-*.ips 2>/dev/null | head -1)
    echo "  Latest: $LATEST_CRASH"
    # Extract crash reason
    grep -oP '"subtype"\s*:\s*"\K[^"]+' "$LATEST_CRASH" 2>/dev/null || true
else
    ok "No new crash reports"
fi

# Show trace output
echo ""
info "=== CRYSTAL_TRACE output ==="
grep "CRYSTAL_TRACE" "$LOG_FILE" 2>/dev/null || echo "  (no trace output captured)"
echo ""
info "Full log: $LOG_FILE"

# Cleanup
xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
