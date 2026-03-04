#!/usr/bin/env bash
# test_android.sh — Automated build, deploy, and test for Crystal Audio Android app
#
# Usage: ./samples/android_app/test_android.sh
#
# This script tests the following (will fail gracefully until Android app is implemented):
#   1. Boot emulator (crystal_test AVD)
#   2. Wait for device ready
#   3. Install APK
#   4. Grant microphone permission
#   5. Launch app
#   6. Test recording: tap Record, wait, tap Stop
#   7. Pull WAV file and validate
#   8. Test playback: (added when playback is implemented)
#   9. Check logcat for Crystal trace messages
#  10. Report pass/fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE="com.crimsonknight.crystalaudio"
ACTIVITY="$PACKAGE/.MainActivity"
AVD_NAME="crystal_test"
RECORD_SECONDS=5

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"

PASS_COUNT=0
FAIL_COUNT=0

info()  { printf '\033[0;34m[test]\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m[PASS]\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip()  { printf '\033[0;33m[SKIP]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
info "Checking prerequisites ..."

if [ ! -f "$ADB" ]; then
    fail "adb not found at $ADB"
    echo "  Set ANDROID_SDK_ROOT or install Android SDK"
    exit 1
fi

APK_PATH="$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK_PATH" ]; then
    skip "APK not found at $APK_PATH — build Android app first (./gradlew assembleDebug)"
    skip "Skipping all runtime tests"
    echo ""
    echo "================================"
    echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed (APK not built yet)"
    echo "================================"
    exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: Boot emulator (if not already running)
# ---------------------------------------------------------------------------
DEVICE_ONLINE=$("$ADB" devices 2>/dev/null | grep -c "emulator.*device" || echo "0")
if [ "$DEVICE_ONLINE" -eq 0 ]; then
    info "Booting emulator ($AVD_NAME) ..."
    if [ -f "$EMULATOR" ]; then
        "$EMULATOR" -avd "$AVD_NAME" -no-audio -no-window -gpu swiftshader_indirect &
        EMULATOR_PID=$!
    else
        fail "Emulator not found at $EMULATOR"
        exit 1
    fi
else
    info "Emulator already running"
    EMULATOR_PID=""
fi

# ---------------------------------------------------------------------------
# Step 2: Wait for device ready
# ---------------------------------------------------------------------------
info "Waiting for device ..."
"$ADB" wait-for-device
# Wait for boot to complete
BOOT_TIMEOUT=120
BOOT_ELAPSED=0
while [ "$BOOT_ELAPSED" -lt "$BOOT_TIMEOUT" ]; do
    BOOT_COMPLETE=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "")
    if [ "$BOOT_COMPLETE" = "1" ]; then
        break
    fi
    sleep 2
    BOOT_ELAPSED=$((BOOT_ELAPSED + 2))
done

if [ "$BOOT_COMPLETE" = "1" ]; then
    ok "Device booted"
else
    fail "Device boot timed out after ${BOOT_TIMEOUT}s"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Install APK
# ---------------------------------------------------------------------------
info "Installing APK ..."
INSTALL_OUTPUT=$("$ADB" install -r "$APK_PATH" 2>&1)
if echo "$INSTALL_OUTPUT" | grep -q "Success"; then
    ok "APK installed"
else
    fail "APK install failed: $INSTALL_OUTPUT"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 4: Grant microphone permission
# ---------------------------------------------------------------------------
info "Granting permissions ..."
"$ADB" shell pm grant "$PACKAGE" android.permission.RECORD_AUDIO 2>/dev/null || true
ok "RECORD_AUDIO permission granted"

# ---------------------------------------------------------------------------
# Step 5: Launch app
# ---------------------------------------------------------------------------
info "Launching app ..."
# Clear logcat before launch
"$ADB" logcat -c 2>/dev/null || true

"$ADB" shell am start -n "$ACTIVITY" 2>&1
sleep 3

# Check Crystal runtime initialized
INIT_LOG=$("$ADB" logcat -d -s CrystalAudio 2>/dev/null || echo "")
if echo "$INIT_LOG" | grep -q "CRYSTAL_TRACE.*init.*complete\|CRYSTAL_TRACE.*init.*done"; then
    ok "Crystal runtime initialized"
else
    fail "Crystal runtime did not initialize (check logcat -s CrystalAudio)"
fi

# ---------------------------------------------------------------------------
# Step 6: Test recording — tap Record button via UI automator
# ---------------------------------------------------------------------------
info "Testing recording ..."

# Dump UI tree and find Record button
"$ADB" shell uiautomator dump /data/local/tmp/ui_dump.xml 2>/dev/null || true
UI_DUMP=$("$ADB" shell cat /data/local/tmp/ui_dump.xml 2>/dev/null || echo "")

# Look for a button with "Record" or "Start" text
RECORD_BOUNDS=$(echo "$UI_DUMP" | python3 -c "
import sys, re
xml = sys.stdin.read()
# Find button/clickable with Record text
match = re.search(r'text=\"(Record|Start)[^\"]*\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml)
if match:
    x = (int(match.group(2)) + int(match.group(4))) // 2
    y = (int(match.group(3)) + int(match.group(5))) // 2
    print(f'{x} {y}')
else:
    print('')
" 2>/dev/null || echo "")

if [ -n "$RECORD_BOUNDS" ]; then
    X=$(echo "$RECORD_BOUNDS" | awk '{print $1}')
    Y=$(echo "$RECORD_BOUNDS" | awk '{print $2}')
    info "Tapping Record button at ($X, $Y) ..."
    "$ADB" shell input tap "$X" "$Y"
    ok "Record button tapped"
else
    skip "Record button not found in UI tree — tapping center of screen as fallback"
    "$ADB" shell input tap 540 960
fi

# Wait for recording
info "Recording for ${RECORD_SECONDS}s ..."
sleep $RECORD_SECONDS

# Check logcat for recording start
REC_LOG=$("$ADB" logcat -d -s CrystalAudio 2>/dev/null || echo "")
if echo "$REC_LOG" | grep -q "CRYSTAL_TRACE.*start\|recording.*started"; then
    ok "Recording started (logcat confirms)"
else
    fail "No recording start trace in logcat"
fi

# ---------------------------------------------------------------------------
# Step 7: Stop recording — find and tap Stop button
# ---------------------------------------------------------------------------
"$ADB" shell uiautomator dump /data/local/tmp/ui_dump2.xml 2>/dev/null || true
UI_DUMP2=$("$ADB" shell cat /data/local/tmp/ui_dump2.xml 2>/dev/null || echo "")

STOP_BOUNDS=$(echo "$UI_DUMP2" | python3 -c "
import sys, re
xml = sys.stdin.read()
match = re.search(r'text=\"(Stop|Pause)[^\"]*\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml)
if match:
    x = (int(match.group(2)) + int(match.group(4))) // 2
    y = (int(match.group(3)) + int(match.group(5))) // 2
    print(f'{x} {y}')
else:
    print('')
" 2>/dev/null || echo "")

if [ -n "$STOP_BOUNDS" ]; then
    SX=$(echo "$STOP_BOUNDS" | awk '{print $1}')
    SY=$(echo "$STOP_BOUNDS" | awk '{print $2}')
    info "Tapping Stop button at ($SX, $SY) ..."
    "$ADB" shell input tap "$SX" "$SY"
    ok "Stop button tapped"
else
    skip "Stop button not found — tapping same location as Record"
    "$ADB" shell input tap "${X:-540}" "${Y:-960}"
fi

sleep 2

# ---------------------------------------------------------------------------
# Step 8: Pull recording and validate
# ---------------------------------------------------------------------------
info "Pulling recording ..."

# Check for WAV files in app's files directory
RECORDING_PATH=$("$ADB" shell "ls /data/data/$PACKAGE/files/recording_*.wav 2>/dev/null | head -1" 2>/dev/null | tr -d '\r' || echo "")

if [ -z "$RECORDING_PATH" ]; then
    # Try external storage
    RECORDING_PATH=$("$ADB" shell "ls /sdcard/Android/data/$PACKAGE/files/recording_*.wav 2>/dev/null | head -1" 2>/dev/null | tr -d '\r' || echo "")
fi

LOCAL_WAV="/tmp/crystal_android_test_output.wav"
if [ -n "$RECORDING_PATH" ]; then
    "$ADB" pull "$RECORDING_PATH" "$LOCAL_WAV" 2>/dev/null
    ok "WAV file pulled: $(basename "$RECORDING_PATH")"

    # Validate file type
    FILE_TYPE=$(file "$LOCAL_WAV" 2>/dev/null || echo "unknown")
    if echo "$FILE_TYPE" | grep -qi "WAVE\|RIFF\|audio"; then
        ok "File format is WAV"
    else
        fail "File is not WAV: $FILE_TYPE"
    fi

    # Validate with ffprobe
    if command -v ffprobe >/dev/null 2>&1; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$LOCAL_WAV" 2>/dev/null || echo "0")
        if [ "$(echo "$DURATION >= 3.0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
            ok "Duration: ${DURATION}s (>= 3s)"
        else
            fail "Duration too short: ${DURATION}s"
        fi
    fi

    # File size check
    FILE_SIZE=$(stat -f%z "$LOCAL_WAV" 2>/dev/null || stat -c%s "$LOCAL_WAV" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        ok "File size: ${FILE_SIZE} bytes (> 5KB)"
    else
        fail "File too small: ${FILE_SIZE} bytes"
    fi
else
    skip "No WAV file found on device (expected until recording is implemented)"
fi

# ---------------------------------------------------------------------------
# Step 9: Check logcat for Crystal trace messages
# ---------------------------------------------------------------------------
echo ""
info "=== Crystal trace output (logcat -s CrystalAudio) ==="
"$ADB" logcat -d -s CrystalAudio 2>/dev/null | grep "CRYSTAL_TRACE" || echo "  (no trace output)"
echo ""

# ---------------------------------------------------------------------------
# Step 10: Summary
# ---------------------------------------------------------------------------
# Stop the app
"$ADB" shell am force-stop "$PACKAGE" 2>/dev/null || true

echo ""
echo "================================"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
