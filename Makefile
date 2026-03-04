# crystal-audio Makefile
# Compiles C/ObjC native extensions and provides build/test targets.
#
# Requirements:
#   - Xcode Command Line Tools (clang, xcrun)
#   - Crystal compiler (stock >= 1.15.0 for macOS; crystal-alpha for iOS/Android)
#
# Usage:
#   make ext          — compile C/ObjC extensions to .o files
#   make sample       — build the mic_recorder sample
#   make spec         — run the test suite
#   make clean        — remove build artifacts
#   make ios-ext      — compile C extensions for iOS Simulator (arm64)
#   make ios-lib      — build Crystal static library for iOS Simulator
#   make ios-app      — build complete iOS app for Simulator (requires xcodegen)

CLANG      := $(shell xcrun --find clang)
SDK        := $(shell xcrun --show-sdk-path)
ARCH       := $(shell uname -m)
CFLAGS     := -arch $(ARCH) -isysroot $(SDK) -mmacosx-version-min=13.0 -O2 -fPIC
OBJCFLAGS  := $(CFLAGS) -fobjc-arc

# Extension object files
EXT_BLOCK_BRIDGE     := ext/block_bridge.o
EXT_OBJC_HELPERS     := ext/objc_helpers.o
EXT_SYSTEM_AUDIO_TAP := ext/system_audio_tap.o
EXT_APPKIT_HELPERS   := ext/appkit_helpers.o
EXT_AUDIO_WRITE      := ext/audio_write_helper.o

.PHONY: all ext sample spec clean macos-app ios-ext ios-lib ios-app playback-test lockscreen-test android-lib android-app

all: ext

## Compile C/ObjC native extensions
ext: $(EXT_BLOCK_BRIDGE) $(EXT_OBJC_HELPERS) $(EXT_SYSTEM_AUDIO_TAP) $(EXT_APPKIT_HELPERS) $(EXT_AUDIO_WRITE)

$(EXT_BLOCK_BRIDGE): ext/block_bridge.c
	$(CLANG) $(CFLAGS) -c $< -o $@
	@echo "  Built $@"

$(EXT_OBJC_HELPERS): ext/objc_helpers.c
	$(CLANG) $(CFLAGS) -c $< -o $@
	@echo "  Built $@"

$(EXT_SYSTEM_AUDIO_TAP): ext/system_audio_tap.m
	$(CLANG) $(OBJCFLAGS) -c $< -o $@
	@echo "  Built $@"

$(EXT_APPKIT_HELPERS): ext/appkit_helpers.c
	$(CLANG) $(CFLAGS) -c $< -o $@
	@echo "  Built $@"

$(EXT_AUDIO_WRITE): ext/audio_write_helper.c
	$(CLANG) $(CFLAGS) -c $< -o $@
	@echo "  Built $@"

LINK_FLAGS := $(CURDIR)/ext/block_bridge.o $(CURDIR)/ext/objc_helpers.o $(CURDIR)/ext/system_audio_tap.o \
  $(CURDIR)/ext/audio_write_helper.o \
  -framework AVFoundation -framework AudioToolbox \
  -framework CoreAudio -framework CoreFoundation \
  -framework CoreMedia -framework Foundation \
  -framework ScreenCaptureKit

APPKIT_LINK_FLAGS := $(CURDIR)/ext/block_bridge.o $(CURDIR)/ext/objc_helpers.o \
  $(CURDIR)/ext/system_audio_tap.o $(CURDIR)/ext/appkit_helpers.o \
  $(CURDIR)/ext/audio_write_helper.o \
  -framework AppKit -framework AVFoundation -framework AudioToolbox \
  -framework CoreAudio -framework CoreFoundation \
  -framework CoreMedia -framework Foundation \
  -framework ScreenCaptureKit

## Build the simple recorder sample (primary entry point)
record: ext
	crystal build samples/record/main.cr \
	  -o samples/record/record \
	  --link-flags="$(LINK_FLAGS)"
	@echo "  Built samples/record/record"
	@echo "  Run: samples/record/record [mic|meeting|system] [seconds] [output.wav]"

## Build mic_recorder sample (requires ext)
sample: ext
	crystal build samples/mic_recorder/main.cr \
	  -o samples/mic_recorder/mic_recorder \
	  --link-flags="$(LINK_FLAGS)"
	@echo "  Built samples/mic_recorder/mic_recorder"

## Run specs
spec: ext
	crystal spec --link-flags="$(LINK_FLAGS)"

## Build and run playback test (multi-track player verification)
playback-test: ext
	crystal build samples/playback_test/main.cr \
	  -o samples/playback_test/playback_test \
	  --link-flags="$(LINK_FLAGS)"
	@echo "  Built samples/playback_test/playback_test"
	@echo "  Running playback test ..."
	samples/playback_test/playback_test

## Build and run lock screen controls test
lockscreen-test: ext
	crystal build samples/lockscreen_test/main.cr \
	  -o samples/lockscreen_test/lockscreen_test \
	  --link-flags="$(LINK_FLAGS) -framework MediaPlayer"
	@echo "  Built samples/lockscreen_test/lockscreen_test"
	@echo "  Running lock screen test ..."
	samples/lockscreen_test/lockscreen_test

## Build macOS desktop app with graphical UI
macos-app: ext
	crystal build samples/macos_app/main.cr \
	  -o samples/macos_app/crystal_audio_demo \
	  --link-flags="$(APPKIT_LINK_FLAGS)"
	@echo "  Built samples/macos_app/crystal_audio_demo"
	@echo "  Run: samples/macos_app/crystal_audio_demo"

## Compile C/ObjC native extensions for iOS Simulator (arm64)
#
# Excluded from iOS:
#   system_audio_tap.m  — uses macOS-only ScreenCaptureKit / AudioHardwareTapping
#   appkit_helpers.c    — AppKit is macOS-only
#
# Included in iOS:
#   block_bridge.c      — ObjC block ABI works identically on iOS
#   objc_helpers.c      — objc_msgSend wrappers work on iOS

IOS_SDK        := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
IOS_TARGET     := arm64-apple-ios-simulator
IOS_CLANG      := $(shell xcrun --sdk iphonesimulator --find clang)
IOS_MIN_VER    := 16.0
IOS_CFLAGS     := -arch arm64 -isysroot $(IOS_SDK) \
                  -mios-simulator-version-min=$(IOS_MIN_VER) \
                  -target $(IOS_TARGET) \
                  -O2 -fPIC -fobjc-arc
IOS_BUILD_DIR  := samples/ios_app/build

IOS_EXT_BLOCK_BRIDGE := $(IOS_BUILD_DIR)/block_bridge.o
IOS_EXT_OBJC_HELPERS := $(IOS_BUILD_DIR)/objc_helpers.o

ios-ext: $(IOS_EXT_BLOCK_BRIDGE) $(IOS_EXT_OBJC_HELPERS)

$(IOS_EXT_BLOCK_BRIDGE): ext/block_bridge.c | $(IOS_BUILD_DIR)
	$(IOS_CLANG) $(IOS_CFLAGS) -c $< -o $@
	@echo "  Built $@ (iOS Simulator)"

$(IOS_EXT_OBJC_HELPERS): ext/objc_helpers.c | $(IOS_BUILD_DIR)
	$(IOS_CLANG) $(IOS_CFLAGS) -c $< -o $@
	@echo "  Built $@ (iOS Simulator)"

$(IOS_BUILD_DIR):
	mkdir -p $@

## Build Crystal static library for iOS Simulator
#
# Requires crystal-alpha:  brew install crimsonknight/crystal-alpha
# Output: samples/ios_app/libcrystal_audio.a
#
# NOTE: crystal-alpha --cross-compile requires absolute paths for -o when the
#       source file lives outside the current working directory.
ios-lib: ios-ext
	@if command -v crystal-alpha >/dev/null 2>&1; then \
	  echo "  Cross-compiling crystal_bridge.cr for $(IOS_TARGET) ..."; \
	  crystal-alpha build $(CURDIR)/samples/ios_app/crystal_bridge.cr \
	    --cross-compile \
	    --target "$(IOS_TARGET)" \
	    --define ios \
	    --release \
	    -o "$(CURDIR)/$(IOS_BUILD_DIR)/crystal_bridge" > /dev/null; \
	  echo "  Packing static library ..."; \
	  rm -f samples/ios_app/libcrystal_audio.a; \
	  ar rcs samples/ios_app/libcrystal_audio.a \
	    "$(CURDIR)/$(IOS_BUILD_DIR)/crystal_bridge.o" \
	    "$(CURDIR)/$(IOS_BUILD_DIR)/block_bridge.o" \
	    "$(CURDIR)/$(IOS_BUILD_DIR)/objc_helpers.o"; \
	  echo "  Built samples/ios_app/libcrystal_audio.a"; \
	else \
	  echo "  ERROR: crystal-alpha not found."; \
	  echo "  Install with: brew install crimsonknight/crystal-alpha"; \
	  exit 1; \
	fi

## Build iOS Simulator app (requires xcodegen + crystal-alpha)
#
# Full pipeline: cross-compile Crystal, compile stubs, build Xcode project, xcodebuild.
# Output: samples/ios_app/build/DerivedData/Build/Products/Debug-iphonesimulator/CrystalAudioDemo.app
IOS_STUB_SRC   := samples/ios_app/system_audio_tap_stub.c
IOS_STUB_OBJ   := $(IOS_BUILD_DIR)/system_audio_tap_stub.o

ios-app: ios-lib
	@echo "  Compiling system_audio_tap stub for iOS Simulator ..."
	$(IOS_CLANG) $(IOS_CFLAGS) -c $(IOS_STUB_SRC) -o $(IOS_STUB_OBJ)
	@if [ ! -f "$(IOS_BUILD_DIR)/libgc.a" ]; then \
	  echo "  ERROR: $(IOS_BUILD_DIR)/libgc.a not found."; \
	  echo "  Cross-compile BoehmGC for iOS Simulator first (see README)."; \
	  exit 1; \
	fi
	@if ! command -v xcodegen >/dev/null 2>&1; then \
	  echo "  ERROR: xcodegen not found. Install with: brew install xcodegen"; \
	  exit 1; \
	fi
	cd samples/ios_app && xcodegen generate --quiet
	xcodebuild \
	  -project samples/ios_app/CrystalAudioDemo.xcodeproj \
	  -scheme CrystalAudioDemo \
	  -sdk iphonesimulator \
	  -arch arm64 \
	  -configuration Debug \
	  -derivedDataPath samples/ios_app/build/DerivedData \
	  build 2>&1 | tail -5
	@echo "  Built CrystalAudioDemo.app for iOS Simulator"
	@echo "  Install: xcrun simctl install booted samples/ios_app/build/DerivedData/Build/Products/Debug-iphonesimulator/CrystalAudioDemo.app"
	@echo "  Launch:  xcrun simctl launch booted com.crimsonknight.CrystalAudioDemo"

## Cross-compile Crystal shared library for Android (aarch64)
android-lib:
	@echo "  Building Crystal shared library for Android ..."
	samples/android_app/build_crystal_lib.sh

## Build Android app APK (requires Android SDK + Gradle)
android-app: android-lib
	@echo "  Building Android APK ..."
	cd samples/android_app && ./gradlew assembleDebug
	@echo "  Built APK: samples/android_app/app/build/outputs/apk/debug/app-debug.apk"

clean:
	rm -f ext/*.o samples/mic_recorder/mic_recorder samples/macos_app/crystal_audio_demo
	rm -f samples/playback_test/playback_test samples/lockscreen_test/lockscreen_test
	rm -rf samples/ios_app/build samples/ios_app/libcrystal_audio.a
	rm -rf samples/ios_app/CrystalAudioDemo.xcodeproj
	rm -rf samples/android_app/build samples/android_app/app/build
	rm -rf samples/android_app/app/src/main/jniLibs
	@echo "  Cleaned"
