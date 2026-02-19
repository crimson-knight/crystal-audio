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

CLANG      := $(shell xcrun --find clang)
SDK        := $(shell xcrun --show-sdk-path)
ARCH       := $(shell uname -m)
CFLAGS     := -arch $(ARCH) -isysroot $(SDK) -mmacosx-version-min=13.0 -O2 -fPIC
OBJCFLAGS  := $(CFLAGS) -fobjc-arc

# Extension object files
EXT_BLOCK_BRIDGE     := ext/block_bridge.o
EXT_OBJC_HELPERS     := ext/objc_helpers.o
EXT_SYSTEM_AUDIO_TAP := ext/system_audio_tap.o

.PHONY: all ext sample spec clean

all: ext

## Compile C/ObjC native extensions
ext: $(EXT_BLOCK_BRIDGE) $(EXT_OBJC_HELPERS) $(EXT_SYSTEM_AUDIO_TAP)

$(EXT_BLOCK_BRIDGE): ext/block_bridge.c
	$(CLANG) $(CFLAGS) -c $< -o $@
	@echo "  Built $@"

$(EXT_OBJC_HELPERS): ext/objc_helpers.c
	$(CLANG) $(CFLAGS) -c $< -o $@
	@echo "  Built $@"

$(EXT_SYSTEM_AUDIO_TAP): ext/system_audio_tap.m
	$(CLANG) $(OBJCFLAGS) -c $< -o $@
	@echo "  Built $@"

LINK_FLAGS := $(CURDIR)/ext/block_bridge.o $(CURDIR)/ext/objc_helpers.o $(CURDIR)/ext/system_audio_tap.o \
  -framework AVFoundation -framework AudioToolbox \
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

clean:
	rm -f ext/*.o samples/mic_recorder/mic_recorder
	@echo "  Cleaned"
