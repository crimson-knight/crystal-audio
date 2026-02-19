#!/usr/bin/env bash
# build_crystal_lib.sh
#
# Build the Crystal audio bridge as a static library for the iOS Simulator.
#
# Output: samples/ios_app/libcrystal_audio.a
#
# Prerequisites
# -------------
#   - crystal-alpha installed:  brew install crimsonknight/crystal-alpha
#   - Xcode with iOS SDK:       xcode-select --install
#   - Run from anywhere — script resolves the repo root automatically.
#
# Usage
# -----
#   ./samples/ios_app/build_crystal_lib.sh
#
# What this script does
# ---------------------
#   1.  Compile C/ObjC native extensions for iOS Simulator arm64.
#       - block_bridge.c  : ObjC block ABI shims (works on iOS)
#       - objc_helpers.c  : objc_msgSend typed wrappers (works on iOS)
#       - system_audio_tap.m and appkit_helpers.c are EXCLUDED (macOS-only).
#   2.  Cross-compile crystal_bridge.cr to an object file using crystal-alpha
#       with --target arm64-apple-ios-simulator and --define ios.
#   3.  Pack all .o files into libcrystal_audio.a with ar.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CRYSTAL=${CRYSTAL:-crystal-alpha}
TARGET="arm64-apple-ios-simulator"
MIN_IOS_VER="16.0"

# Resolve repo root as the directory two levels above this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SAMPLE_DIR="$REPO_ROOT/samples/ios_app"
EXT_DIR="$REPO_ROOT/ext"
BUILD_DIR="$SAMPLE_DIR/build"
OUTPUT_LIB="$SAMPLE_DIR/libcrystal_audio.a"
BRIDGE_SRC="$SAMPLE_DIR/crystal_bridge.cr"
BRIDGE_BASE="$BUILD_DIR/crystal_bridge"   # crystal emits $BRIDGE_BASE.o

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[0;34m[build]\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m[ok]\033[0m    %s\n' "$*"; }
fail()  { printf '\033[0;31m[fail]\033[0m  %s\n' "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

require_cmd "$CRYSTAL"
require_cmd xcrun
require_cmd ar

IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
IOS_CLANG=$(xcrun --sdk iphonesimulator --find clang)

CRYSTAL_VER=$("$CRYSTAL" --version 2>&1 | head -1)
info "Compiler : $CRYSTAL_VER"
info "Target   : $TARGET"
info "iOS SDK  : $IOS_SDK"
info "Repo     : $REPO_ROOT"
info "Output   : $OUTPUT_LIB"
echo

mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Step 1: Compile C/ObjC native extensions for iOS Simulator
#
# NOT compiled for iOS (macOS-only APIs):
#   system_audio_tap.m  — AudioHardwareTapping / ScreenCaptureKit
#   appkit_helpers.c    — AppKit (macOS window/UI toolkit)
#
# Compiled for iOS (cross-platform ObjC runtime APIs):
#   block_bridge.c      — ObjC block ABI; used for AVAudioNode tap
#   objc_helpers.c      — typed objc_msgSend wrappers
# ---------------------------------------------------------------------------

IOS_CFLAGS=(
    -arch arm64
    -isysroot "$IOS_SDK"
    -mios-simulator-version-min="$MIN_IOS_VER"
    -target "$TARGET"
    -O2
    -fPIC
    -fobjc-arc
)

info "Compiling ext/block_bridge.c ..."
"$IOS_CLANG" "${IOS_CFLAGS[@]}" -c "$EXT_DIR/block_bridge.c" -o "$BUILD_DIR/block_bridge.o"
ok "block_bridge.o"

info "Compiling ext/objc_helpers.c ..."
"$IOS_CLANG" "${IOS_CFLAGS[@]}" -c "$EXT_DIR/objc_helpers.c" -o "$BUILD_DIR/objc_helpers.o"
ok "objc_helpers.o"

# ---------------------------------------------------------------------------
# Step 2: Cross-compile the Crystal bridge to an object file
#
# crystal-alpha --cross-compile emits <output-base>.o and prints the linker
# command to stdout (which we discard — we are building a static lib, not
# a binary).
#
# Flags:
#   --cross-compile   emit .o rather than invoking the linker
#   --target          LLVM triple for arm64 iOS Simulator
#   --define ios      compile-time flag; gates out macOS-only code in
#                     crystal-audio (system audio tap, ScreenCaptureKit)
#   --release         optimise; keeps the .a small
#   -o                output base path; crystal appends .o automatically
#
# IMPORTANT: crystal-alpha requires an absolute path for -o when the source
# file is not in the current working directory.
# ---------------------------------------------------------------------------

info "Cross-compiling crystal_bridge.cr ..."
LINKER_FLAGS=$("$CRYSTAL" build \
    "$BRIDGE_SRC" \
    --cross-compile \
    --target "$TARGET" \
    --define ios \
    --define shared \
    --release \
    -o "$BRIDGE_BASE")
ok "crystal_bridge.o"

echo
echo "Linker flags (for reference — needed when linking the final app):"
echo "  $LINKER_FLAGS"
echo

# ---------------------------------------------------------------------------
# Step 3: Pack everything into a static library
# ---------------------------------------------------------------------------

info "Creating static library ..."
rm -f "$OUTPUT_LIB"
ar rcs "$OUTPUT_LIB" \
    "${BRIDGE_BASE}.o" \
    "$BUILD_DIR/block_bridge.o" \
    "$BUILD_DIR/objc_helpers.o"

LIB_SIZE=$(du -sh "$OUTPUT_LIB" | cut -f1)
ok "libcrystal_audio.a  ($LIB_SIZE)  →  $OUTPUT_LIB"
echo
echo "Exported symbols:"
xcrun nm "$OUTPUT_LIB" 2>/dev/null \
    | grep -E "T _crystal_audio_" \
    | awk '{print "  " $3}'
echo
echo "Next steps:"
echo "  1. Open (or create) your Xcode project"
echo "  2. Drag $OUTPUT_LIB into Build Phases → Link Binary with Libraries"
echo "  3. Set Objective-C Bridging Header to: \$(PROJECT_DIR)/crystal_bridge.h"
echo "     (Target → Build Settings → Swift Compiler — General)"
echo "  4. Add to Info.plist: NSMicrophoneUsageDescription"
echo "  5. Build and run on iPhone Simulator (arm64)"
