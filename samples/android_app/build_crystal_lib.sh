#!/usr/bin/env bash
# build_crystal_lib.sh — Cross-compile Crystal + JNI bridge for Android (aarch64)
#
# Usage: ./samples/android_app/build_crystal_lib.sh
#
# Produces: app/src/main/jniLibs/arm64-v8a/libcrystal_audio.so
#
# Requirements:
#   - crystal-alpha compiler
#   - Android NDK (ANDROID_SDK_ROOT or NDK_ROOT env var)
#   - Pre-built libgc.a for aarch64-linux-android26

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
JNILIBS_DIR="$SCRIPT_DIR/app/src/main/jniLibs/arm64-v8a"

TARGET="aarch64-linux-android26"
API_LEVEL=26

# Locate NDK
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
NDK_ROOT="${NDK_ROOT:-$(ls -d "$ANDROID_SDK_ROOT"/ndk/*/  2>/dev/null | sort -V | tail -1)}"
if [ -z "$NDK_ROOT" ] || [ ! -d "$NDK_ROOT" ]; then
    echo "ERROR: NDK not found. Set NDK_ROOT or ANDROID_SDK_ROOT"
    exit 1
fi

# NDK clang (for host prebuilt)
HOST_TAG="darwin-x86_64"
NDK_CLANG="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin/${TARGET}-clang"
if [ ! -f "$NDK_CLANG" ]; then
    # Try alternative: clang with --target flag
    NDK_CLANG="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin/clang"
    CLANG_FLAGS="--target=$TARGET"
else
    CLANG_FLAGS=""
fi

echo "NDK root:  $NDK_ROOT"
echo "NDK clang: $NDK_CLANG"
echo "Target:    $TARGET"

mkdir -p "$BUILD_DIR" "$JNILIBS_DIR"

info() { printf '\033[0;34m[build]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Step 1: Cross-compile Crystal → object file
# ---------------------------------------------------------------------------
info "Cross-compiling crystal_bridge.cr for $TARGET ..."
cd "$REPO_ROOT"
crystal-alpha build samples/android_app/crystal_bridge.cr \
    --cross-compile \
    --target "$TARGET" \
    --define android \
    --release \
    -o "$BUILD_DIR/crystal_bridge" 2>&1 | head -5

# ---------------------------------------------------------------------------
# Step 2: Compile JNI bridge with NDK clang
# ---------------------------------------------------------------------------
info "Compiling jni_bridge.c ..."
$NDK_CLANG $CLANG_FLAGS \
    -c "$SCRIPT_DIR/jni_bridge.c" \
    -o "$BUILD_DIR/jni_bridge.o" \
    -O2 -fPIC

# ---------------------------------------------------------------------------
# Step 3: Check for pre-built libgc.a
# ---------------------------------------------------------------------------
LIBGC="$BUILD_DIR/libgc.a"
if [ ! -f "$LIBGC" ]; then
    info "WARNING: $LIBGC not found"
    info "Cross-compile BoehmGC for $TARGET and place libgc.a in $BUILD_DIR/"
    info "Example:"
    info "  cd /tmp && git clone https://github.com/ivmai/bdwgc.git && cd bdwgc"
    info "  cmake -DCMAKE_SYSTEM_NAME=Android -DCMAKE_ANDROID_NDK=$NDK_ROOT \\"
    info "    -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \\"
    info "    -DCMAKE_BUILD_TYPE=Release -Denable_threads=ON -Denable_cplusplus=OFF \\"
    info "    -DBUILD_SHARED_LIBS=OFF -B build && cmake --build build"
    info "  cp build/libgc.a $BUILD_DIR/"
    LIBGC_FLAG=""
else
    LIBGC_FLAG="$LIBGC"
fi

# ---------------------------------------------------------------------------
# Step 4: Link shared library
# ---------------------------------------------------------------------------
SYSROOT="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"

info "Linking libcrystal_audio.so ..."
$NDK_CLANG $CLANG_FLAGS \
    -shared \
    -o "$JNILIBS_DIR/libcrystal_audio.so" \
    "$BUILD_DIR/crystal_bridge.o" \
    "$BUILD_DIR/jni_bridge.o" \
    $LIBGC_FLAG \
    -llog -landroid -lm -ldl \
    -Wl,-z,max-page-size=16384 \
    -Wl,--gc-sections \
    --sysroot="$SYSROOT"

info "Output: $JNILIBS_DIR/libcrystal_audio.so"
ls -la "$JNILIBS_DIR/libcrystal_audio.so"

info "Done! Run: cd samples/android_app && ./gradlew assembleDebug"
