# Crystal Audio — iOS Simulator Sample App

A SwiftUI app that records microphone audio using the `crystal-audio` Crystal
library compiled as a static library (`libcrystal_audio.a`) for the iOS
Simulator.

## Architecture

```
┌─────────────────────────────────────────────┐
│  SwiftUI App (Xcode)                        │
│  ContentView.swift / CrystalAudioApp.swift  │
│              │                              │
│  crystal_bridge.h  (bridging header)        │
│              │                              │
│  libcrystal_audio.a  (static lib)           │
│    crystal_bridge.o   ← Crystal C API       │
│    block_bridge.o     ← ObjC block ABI      │
│    objc_helpers.o     ← objc_msgSend wrappers│
└─────────────────────────────────────────────┘
         ↓ links against
AudioToolbox + CoreFoundation + Foundation + AVFoundation
```

The Crystal library is cross-compiled with `crystal-alpha` for
`arm64-apple-ios-simulator`. The Swift layer calls three C functions exposed
by `crystal_bridge.cr`:

| Function | Description |
|---|---|
| `crystal_audio_start_mic(path)` | Begin recording mic → WAV at `path` |
| `crystal_audio_stop()` | Stop recording and finalize file |
| `crystal_audio_is_recording()` | Returns 1 if recording, 0 otherwise |

## Prerequisites

| Tool | Install |
|---|---|
| `crystal-alpha` | `brew install crimsonknight/crystal-alpha` |
| Xcode 15+ | Mac App Store |
| iOS SDK 16+ | Bundled with Xcode |

Verify crystal-alpha is available:

```bash
crystal-alpha --version
# Crystal 1.20.0-dev [...] — LLVM: 21.x
```

## Step 1: Build the static library

From the **repo root** (`crystal-audio/`):

```bash
make ios-lib
# or equivalently:
./samples/ios_app/build_crystal_lib.sh
```

Expected output:

```
[build] Compiler : Crystal 1.20.0-dev [...]
[build] Target   : arm64-apple-ios-simulator
[ok]    block_bridge.o
[ok]    objc_helpers.o
[ok]    crystal_bridge.o
[ok]    libcrystal_audio.a (1.8M)
```

Output file: `samples/ios_app/libcrystal_audio.a`

## Step 2: Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Product Name: `CrystalAudioDemo`
4. Interface: **SwiftUI**
5. Language: **Swift**
6. Deployment Target: **iOS 16.0**
7. Save anywhere (e.g. alongside this directory)

## Step 3: Add the Swift source files

In the Xcode project navigator, right-click the target group and choose
**Add Files to "CrystalAudioDemo"**. Add:

- `samples/ios_app/ContentView.swift`
- `samples/ios_app/CrystalAudioApp.swift`

Replace (or delete) the default `ContentView.swift` and `CrystalAudioApp.swift`
that Xcode generated — these files are complete replacements.

## Step 4: Add the bridging header

1. Add `samples/ios_app/crystal_bridge.h` to the project (drag in, uncheck
   "Copy items if needed" if you want to keep it in place, or copy it).
2. In Xcode: **Target → Build Settings → Swift Compiler — General**
3. Set **Objective-C Bridging Header** to:
   ```
   $(PROJECT_DIR)/crystal_bridge.h
   ```
   (or the relative path to wherever you placed the file)

## Step 5: Link the static library

1. Select the target → **Build Phases → Link Binary with Libraries**
2. Click **+** → **Add Other… → Add Files…**
3. Select `samples/ios_app/libcrystal_audio.a`

## Step 6: Link required system frameworks

In **Build Phases → Link Binary with Libraries**, also add:

| Framework | Reason |
|---|---|
| `AudioToolbox.framework` | AudioQueue microphone capture |
| `CoreFoundation.framework` | CFString / CFURL for file paths |
| `Foundation.framework` | ObjC runtime |
| `AVFoundation.framework` | AVAudioSession permission |

These are all available in the iOS SDK — no additional downloads required.

## Step 7: Add microphone permission

In your target's **Info.plist** (or **Info tab → Custom iOS Target Properties**),
add:

| Key | Value |
|---|---|
| `NSMicrophoneUsageDescription` | `Crystal Audio records your voice to WAV files stored in the app's Documents folder.` |

Without this key iOS will crash with a permission error at runtime.

## Step 8: Build and run

Select **iPhone 15 Pro Simulator** (or any arm64 iOS 16+ simulator) and press
**Run** (⌘R).

The app shows a microphone button. Tap it to start recording; tap again to
stop. Recordings are saved as WAV files in the simulator's Documents directory.

## Linker note

When Crystal cross-compiles, it prints the full linker command to stdout.
For reference, the key flags needed when linking the final app binary are:

```
-framework AudioToolbox
-framework CoreFoundation
-framework AVFoundation
-framework Foundation
-L$(CRYSTAL_LIB_PATH) -lgc -lz
```

Xcode handles the frameworks automatically if you add them to Build Phases.
`-lgc` (Boehm GC) and `-lz` come from Crystal's runtime; if the linker
complains about missing `_GC_malloc`, add
`/opt/homebrew/Cellar/bdw-gc/*/lib/libgc.a` to Link Binary with Libraries.

## Files in this directory

| File | Purpose |
|---|---|
| `crystal_bridge.cr` | Crystal source — exposes C API |
| `crystal_bridge.h` | C header for Swift bridging |
| `ContentView.swift` | SwiftUI UI and `AudioRecorderModel` |
| `CrystalAudioApp.swift` | `@main` app entry point |
| `Info.plist` | Required plist keys (merge into project) |
| `build_crystal_lib.sh` | Standalone build script |
| `libcrystal_audio.a` | Compiled static library (after build) |
| `build/` | Intermediate object files |

## Cleaning up

```bash
make clean   # removes libcrystal_audio.a and samples/ios_app/build/
```
