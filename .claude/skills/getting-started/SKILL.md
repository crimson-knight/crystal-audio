---
name: getting-started
description: |
  Install and use the crystal-audio library for microphone recording, system audio capture,
  and on-device transcription in Crystal. Covers macOS and iOS platform setup, native
  extension compilation, and basic recording patterns.
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
version: "0.1.0"
---

# Getting Started with crystal-audio

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  crystal_audio:
    github: crimson-knight/crystal-audio
```

Then run:

```bash
shards install
```

## Platform Requirements

### macOS (primary platform)

- macOS 13.0+ (Ventura) minimum, macOS 14.2+ recommended
- Xcode Command Line Tools (`xcode-select --install`)
- Crystal >= 1.15.0

### iOS (cross-compilation)

- iOS 16.0+ deployment target
- crystal-alpha compiler: `brew install crimsonknight/crystal-alpha`
- Xcode with iOS Simulator SDKs
- xcodegen: `brew install xcodegen`

See the `/ios-integration` skill for the full iOS guide.

## Building Native Extensions

crystal-audio requires C/ObjC extension objects for ObjC runtime bridging, block construction, and system audio capture. Build them before compiling your project:

```bash
cd lib/crystal_audio && make ext
```

This produces:
- `ext/block_bridge.o` — ObjC block ABI for AVFoundation callbacks
- `ext/objc_helpers.o` — Typed `objc_msgSend` wrappers
- `ext/system_audio_tap.o` — ProcessTap / ScreenCaptureKit audio capture

## Link Flags

Your Crystal build command needs these frameworks linked:

```bash
crystal build your_app.cr --link-flags=" \
  lib/crystal_audio/ext/block_bridge.o \
  lib/crystal_audio/ext/objc_helpers.o \
  lib/crystal_audio/ext/system_audio_tap.o \
  lib/crystal_audio/ext/audio_write_helper.o \
  -framework AVFoundation -framework AudioToolbox \
  -framework CoreAudio -framework CoreFoundation \
  -framework CoreMedia -framework Foundation \
  -framework ScreenCaptureKit"
```

## Quick Start: Record Microphone

```crystal
require "crystal_audio"

rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Microphone,
  output_path: "/tmp/recording.wav"
)

puts "Recording... press Ctrl+C to stop"
rec.start
sleep 10.seconds
rec.stop
puts "Saved to /tmp/recording.wav"
```

## Quick Start: Record System Audio

```crystal
require "crystal_audio"

rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::System,
  output_path: "/tmp/system_audio.wav"
)

rec.start
sleep 30.seconds
rec.stop
```

System audio capture requires:
- macOS 14.2+: No special permissions (uses ProcessTap)
- macOS 13.0-14.1: Screen Recording permission (uses ScreenCaptureKit)

## Quick Start: Record Both Streams

```crystal
require "crystal_audio"

rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Both,
  output_path: "/tmp/meeting.wav",      # System audio
  mic_output_path: "/tmp/dictation.wav"  # Microphone
)

rec.start
sleep 60.seconds
rec.stop
```

## Recording Sources

| Source | Description | macOS Version | Permission |
|--------|------------|---------------|------------|
| `Microphone` | Mic input via AudioQueue | 13.0+ | Microphone |
| `System` | What the computer plays, via ProcessTap or SCStream | 13.0+ | None (14.2+) or Screen Recording (13.x) |
| `Both` | Mic + system simultaneously, two output files | 13.0+ | Both above |

## Info.plist Requirements

For apps that access system audio or microphone, create an `Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSMicrophoneUsageDescription</key>
  <string>Record audio from the microphone</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Capture system audio output</string>
</dict>
</plist>
```

## Audio Format

Recordings are saved as WAV files:
- Sample rate: 44,100 Hz (microphone) / 48,000 Hz (system audio)
- Channels: Mono (microphone) / Stereo (system audio)
- Bit depth: 16-bit PCM
- Format: Linear PCM, little-endian

## Makefile Targets

If working directly with the crystal-audio source:

```bash
make ext          # Compile C/ObjC extensions
make record       # Build CLI recorder sample
make macos-app    # Build macOS desktop GUI app
make ios-app      # Build iOS Simulator app (requires crystal-alpha + xcodegen)
make spec         # Run test suite
make clean        # Remove build artifacts
```

## Architecture

crystal-audio bridges Crystal to Apple's audio frameworks via:

1. **LibObjC** — Direct Objective-C runtime calls (`objc_msgSend`)
2. **C extensions** — Typed wrappers for `objc_msgSend` variants and ObjC block construction
3. **AudioToolbox** — Low-level AudioQueue for mic recording, ExtAudioFile for WAV writing
4. **AVFoundation** — AVAudioEngine for playback, AVAudioSession for iOS
5. **ScreenCaptureKit / ProcessTap** — System audio capture (macOS only)

The library detects macOS version at runtime and selects the optimal audio capture path automatically.
