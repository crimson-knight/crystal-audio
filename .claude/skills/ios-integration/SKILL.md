---
name: ios-integration
description: |
  Cross-compile Crystal code as a static library for iOS and link it into a Swift app.
  Covers the complete pipeline: cross-compilation, runtime initialization, Xcode project
  setup, and critical linker configuration. Documents hard-won solutions to dead-stripping,
  symbol conflicts, and simulator deployment issues.
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
version: "0.1.0"
---

# iOS Integration Guide

This guide covers how to use crystal-audio (or any Crystal library) as a static library
inside an iOS app. The pattern is: **Swift provides the UI and app lifecycle, Crystal
provides the business logic as a C-callable static library.**

## Prerequisites

- crystal-alpha compiler: `brew install crimsonknight/crystal-alpha`
- Xcode with iOS Simulator SDKs
- xcodegen: `brew install xcodegen` (for project generation from YAML)
- BoehmGC cross-compiled for iOS Simulator (see below)

## Architecture Overview

```
Swift App (SwiftUI)
  |
  | calls C functions via bridging header
  v
Crystal Static Library (libcrystal_audio.a)
  |
  | compiled with: crystal-alpha --cross-compile --target arm64-apple-ios-simulator
  v
Apple Frameworks (AVFoundation, AudioToolbox, etc.)
```

## Step 1: Write the Crystal Bridge

Create a `.cr` file that exposes C-callable functions using Crystal's `fun` keyword:

```crystal
# crystal_bridge.cr

# Guard: only compile on Darwin targets
{% unless flag?(:darwin) %}
  {% raise "Requires a Darwin target (macOS or iOS)" %}
{% end %}

require "your_library"

# CRITICAL: Override Crystal's auto-generated main.
# Crystal's unix/main.cr UNCONDITIONALLY defines `fun main`, regardless of -Dshared.
# Swift provides @main; Crystal's main must be a no-op.
fun main(argc : Int32, argv : UInt8**) : Int32
  0
end

# C API exposed to Swift
fun crystal_audio_init : LibC::Int
  GC.init
  Crystal.init_runtime  # Thread.init + Fiber.init + Crystal::Once.init
  Thread.current         # Force-create main thread + fiber
  0
rescue ex
  -1
end

fun crystal_audio_start_mic(output_path : LibC::Char*) : LibC::Int
  path = String.new(output_path)
  rec = CrystalAudio::Recorder.new(
    source: CrystalAudio::RecordingSource::Microphone,
    output_path: path
  )
  rec.start
  0
rescue ex
  -1
end

fun crystal_audio_stop : LibC::Int
  # ... stop recording logic ...
  0
rescue
  -1
end
```

### Key Rules for the Bridge File

1. **Always override `fun main`** — Crystal's `unix/main.cr` unconditionally generates a `_main` symbol that conflicts with Swift's `@main`
2. **Always call `GC.init`, `Crystal.init_runtime`, and `Thread.current`** in your init function — this initializes the garbage collector, thread/fiber linked lists, and the main thread
3. **Wrap every exported function in `rescue`** — unhandled Crystal exceptions will crash the app
4. **Use `LibC::Int` return types** — return 0 for success, -1 for failure
5. **Accept `LibC::Char*` for strings** — convert to Crystal `String` inside the function

## Step 2: Create the Bridging Header

```c
// crystal_bridge.h
#ifndef CRYSTAL_BRIDGE_H
#define CRYSTAL_BRIDGE_H

#include <stdint.h>

int32_t crystal_audio_init(void);
int32_t crystal_audio_start_mic(const char *output_path);
int32_t crystal_audio_stop(void);
int32_t crystal_audio_is_recording(void);

#endif
```

## Step 3: Cross-Compile

```bash
crystal-alpha build crystal_bridge.cr \
  --cross-compile \
  --target arm64-apple-ios-simulator \
  --define ios \
  --define shared \
  -o build/crystal_bridge
```

This produces `build/crystal_bridge.o` (an object file, NOT a linked binary).

### Strip the duplicate _main symbol

Crystal's `_main` must be made local so it doesn't conflict with Swift's:

```bash
ld -r -unexported_symbol _main \
  -o build/crystal_bridge_stripped.o \
  build/crystal_bridge.o
```

### Pack into a static library

```bash
ar rcs build/libcrystal_audio.a \
  build/crystal_bridge_stripped.o \
  build/block_bridge.o \
  build/objc_helpers.o
```

## Step 4: Cross-Compile BoehmGC

Crystal's garbage collector must be compiled for the iOS Simulator target:

```bash
git clone https://github.com/nicolo-ribaudo/bdwgc.git /tmp/bdwgc
cd /tmp/bdwgc
git clone https://github.com/nicolo-ribaudo/libatomic_ops.git

IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

cmake -B build-ios-sim \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=$IOS_SDK \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_C_FLAGS="-target arm64-apple-ios-simulator" \
  -DBUILD_SHARED_LIBS=OFF \
  -Denable_threads=ON \
  -Denable_cplusplus=OFF

cmake --build build-ios-sim
cp build-ios-sim/libgc.a /path/to/your/build/
```

## Step 5: Xcode Project (xcodegen)

Create `project.yml`:

```yaml
name: CrystalAudioDemo
options:
  bundleIdPrefix: com.yourcompany
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "16.0"

targets:
  CrystalAudioDemo:
    type: application
    platform: iOS
    sources:
      - path: .
        includes:
          - "*.swift"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yourcompany.CrystalAudioDemo
        SWIFT_OBJC_BRIDGING_HEADER: crystal_bridge.h
        LIBRARY_SEARCH_PATHS: ["$(PROJECT_DIR)/build"]
        INFOPLIST_FILE: Info.plist
        OTHER_LDFLAGS:
          # CRITICAL: Use -force_load, NOT -l flags!
          - "-force_load"
          - "$(PROJECT_DIR)/build/libcrystal_audio.a"
          - "-force_load"
          - "$(PROJECT_DIR)/build/libgc.a"
          - "-lz"
          - "-liconv"
          - "-lc++"
          - "-framework"
          - "AudioToolbox"
          - "-framework"
          - "CoreFoundation"
          - "-framework"
          - "AVFoundation"
```

Generate the Xcode project:

```bash
xcodegen generate
```

## CRITICAL: Use -force_load, Not -l

This is the single most important thing in this guide:

**NEVER link Crystal static libraries with `-lcrystal_audio` or `-lgc`.**
**ALWAYS use `-force_load /path/to/lib.a`.**

### Why

Xcode's linker applies `-dead_strip` which removes "unreachable" code. When Crystal
is used as a library (not the main program), the linker's dead-code analysis determines
that Crystal's runtime initialization code is unreachable from Swift's `@main` entry
point and **strips the function bodies** while keeping the symbols.

The result: `crystal_audio_init()` exists as an exported symbol and can be called from
Swift, but its internal calls to `GC_init`, `Crystal.init_runtime`, `Thread.current`,
etc. are silently removed. The function appears to succeed (returns 0) but the runtime
is never initialized. Later calls crash with `EXC_BAD_ACCESS at 0x0000000000000018`
(null pointer + 24 bytes offset — the mutex field inside an uninitialized
`Thread::LinkedList`).

### Symptoms of Dead-Stripping

If you see these, your Crystal code is being dead-stripped:

- `EXC_BAD_ACCESS` at address `0x18` inside `Thread::LinkedList#push`
- `nm` on the final binary shows zero `GC_*` symbols
- `crystal_audio_init` returns 0 but no trace output appears
- Disassembly shows your function has fewer instructions than the `.o` file

### The Fix

`-force_load` forces the linker to include ALL object files from the static library,
bypassing dead-strip analysis entirely for those archives:

```yaml
OTHER_LDFLAGS:
  - "-force_load"
  - "$(PROJECT_DIR)/build/libcrystal_audio.a"
  - "-force_load"
  - "$(PROJECT_DIR)/build/libgc.a"
```

## Step 6: Swift App Code

### Initialize Crystal Runtime

Call `crystal_audio_init()` early in your app's lifecycle:

```swift
@MainActor
final class AudioModel: ObservableObject {
    func initCrystalRuntime() {
        let result = crystal_audio_init()
        if result != 0 {
            print("Crystal runtime init failed: \(result)")
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AudioModel()

    var body: some View {
        VStack { /* your UI */ }
        .onAppear {
            model.initCrystalRuntime()
        }
    }
}
```

### Handle Microphone Permission

```swift
func requestPermission(completion: (() -> Void)? = nil) {
    let session = AVAudioSession.sharedInstance()

    // Check synchronously first — on iOS Simulator, the async callback
    // may not fire if permission was pre-granted via simctl.
    if session.recordPermission == .granted {
        self.permissionGranted = true
        completion?()
        return
    }

    session.requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
            self?.permissionGranted = granted
            completion?()
        }
    }
}
```

### Start Recording

```swift
func startRecording() {
    guard permissionGranted else { return }

    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)
    } catch {
        print("Audio session error: \(error)")
        return
    }

    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).wav")

    let result = crystal_audio_start_mic(url.path)
    if result != 0 {
        print("Failed to start recording: \(result)")
    }
}
```

## Step 7: Build and Deploy to Simulator

```bash
# Build
xcodebuild \
  -project CrystalAudioDemo.xcodeproj \
  -scheme CrystalAudioDemo \
  -sdk iphonesimulator \
  -destination 'id=YOUR_SIMULATOR_UDID' \
  -configuration Debug build

# Boot simulator
xcrun simctl boot "iPhone 15 Pro"

# Grant mic permission (avoids permission dialog)
xcrun simctl privacy booted grant microphone com.yourcompany.CrystalAudioDemo

# Install
xcrun simctl install booted path/to/CrystalAudioDemo.app

# Launch
xcrun simctl launch booted com.yourcompany.CrystalAudioDemo
```

## Debugging

### Add C-Level Tracing

Crystal's runtime may not be initialized when crashes happen, so use C-level tracing:

```c
// trace_helper.c
#include <os/log.h>

static os_log_t crystal_log = NULL;

void crystal_trace(const char *msg) {
    if (!crystal_log) {
        crystal_log = os_log_create("com.yourcompany.crystal", "trace");
    }
    os_log_error(crystal_log, "CRYSTAL_TRACE: %{public}s", msg);
}
```

Use from Crystal:

```crystal
lib LibTrace
  fun crystal_trace(msg : UInt8*)
end

fun crystal_audio_init : LibC::Int
  LibTrace.crystal_trace("init: entered".to_unsafe)
  GC.init
  LibTrace.crystal_trace("init: GC.init done".to_unsafe)
  # ...
end
```

View logs:

```bash
xcrun simctl spawn booted log show \
  --predicate 'subsystem == "com.yourcompany.crystal"' \
  --last 30s --style compact
```

### Verify Symbols Survived Linking

```bash
# Check that GC and Crystal symbols exist in the final binary
nm -gU path/to/CrystalAudioDemo.debug.dylib | grep -E "GC_init|crystal_audio_init|crystal_trace"
```

If `GC_init` is missing, the dead-strip removed it. Switch to `-force_load`.

### Simulator Environment Variables

Pass env vars to simulator apps using the `SIMCTL_CHILD_` prefix:

```bash
# This does NOT work (passes as argv, not env):
xcrun simctl launch booted com.app MY_VAR=1

# This works (passes as environment variable):
SIMCTL_CHILD_MY_VAR=1 xcrun simctl launch booted com.app
```

## Known Issues and Solutions

### Crystal's unix/main.cr ignores -Dshared

Crystal's `src/crystal/system/unix/main.cr` unconditionally defines `fun main`.
The `-Dshared` flag only guards the main in `src/crystal/main.cr`, not the unix-specific one.
**Workaround**: Override `fun main` in your bridge file AND strip with `ld -r -unexported_symbol _main`.

### Thread::LinkedList crash at offset 0x18

This crash means `Fiber.@@fibers` was never initialized (BSS zero).
**Cause**: `crystal_audio_init` body was dead-stripped by the linker.
**Fix**: Use `-force_load` for all Crystal static libraries.

### requestRecordPermission callback never fires on Simulator

When mic permission is pre-granted via `simctl privacy grant`, the async
`requestRecordPermission` callback may never execute.
**Fix**: Check `AVAudioSession.recordPermission == .granted` synchronously first.

### Linker warning: no platform load command

```
ld: warning: no platform load command found in 'libcrystal_audio.a', assuming: iOS-simulator
```

This is cosmetic. The Crystal cross-compiler doesn't embed iOS platform metadata in the
object file. It doesn't affect functionality.
