---
name: system-audio
description: |
  Capture system audio (what the computer is playing) using crystal-audio.
  Covers ProcessTap (macOS 14.2+), ScreenCaptureKit fallback (macOS 13.0+),
  and the low-level SystemAudioCapture API for real-time audio processing.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
version: "0.1.0"
---

# System Audio Capture with crystal-audio

## Overview

crystal-audio captures system audio — everything playing through the computer's speakers — using two macOS APIs selected automatically based on OS version:

| macOS Version | API | Permission Required |
|---------------|-----|-------------------|
| 14.2+ (Sonoma) | **ProcessTap** | None |
| 13.0-14.1 (Ventura) | **ScreenCaptureKit** | Screen Recording |

## Quick Start

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

Output: stereo WAV, 48 kHz, 16-bit PCM.

## Version Detection

The library detects macOS version at runtime:

```crystal
CrystalAudio::MacOS.version
# => {major: 15, minor: 3, patch: 0}

CrystalAudio::MacOS.process_tap?
# => true on macOS 14.2+

CrystalAudio::MacOS.screen_capture_kit?
# => true on macOS 13.0+
```

## Low-Level API: SystemAudioCapture

For real-time audio processing (visualization, streaming, analysis), use the
`SystemAudioCapture` class directly:

```crystal
require "crystal_audio"

tap = CrystalAudio::SystemAudioCapture.new

tap.start do |frames, frame_count, channels|
  # frames: Slice(Float32) — interleaved PCM (L, R, L, R, ...)
  # frame_count: UInt32 — number of sample frames
  # channels: UInt32 — channel count (typically 2)

  # Calculate RMS volume
  sum = 0.0_f64
  frames.each { |s| sum += s.to_f64 * s.to_f64 }
  rms = Math.sqrt(sum / frames.size)
  puts "Volume: #{(rms * 100).round(1)}%"
end

sleep 10.seconds
tap.stop
```

### Real-Time Safety

The callback runs on a real-time audio thread. Inside the callback:

- **DO NOT** allocate Crystal objects (no `String.new`, no `Array.new`, etc.)
- **DO NOT** acquire mutexes or call `Fiber.yield`
- **DO** write to pre-allocated buffers
- **DO** use atomic operations for signaling
- **DO** keep the callback as short as possible

For processing that requires allocations, copy data to a ring buffer and process on another thread.

## Audio Format Details

| Property | Microphone | System Audio |
|----------|-----------|--------------|
| Sample Rate | 44,100 Hz | 48,000 Hz |
| Channels | 1 (mono) | 2 (stereo) |
| Bit Depth | 16-bit int | 32-bit float (callback) / 16-bit int (WAV) |
| Buffer | ~185ms | ~10ms |

## Recording Both Streams

```crystal
rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Both,
  output_path: "/tmp/meeting_system.wav",
  mic_output_path: "/tmp/meeting_mic.wav"
)

rec.start
# Both streams record simultaneously
# System: 48kHz stereo
# Mic: 44.1kHz mono
rec.stop
```

## Permissions

### macOS 14.2+ (ProcessTap)

No special permissions needed. ProcessTap captures audio directly from the audio
server without screen recording access.

### macOS 13.0-14.1 (ScreenCaptureKit)

Requires Screen Recording permission. The user will be prompted on first use.
Add to your `Info.plist`:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>Capture system audio output</string>
```

### Checking Permission Programmatically

The library handles permission prompts automatically. If the user denies permission,
`rec.start` will raise an exception.

## Native Extension: system_audio_tap

The system audio capture is implemented in ObjC (`ext/system_audio_tap.m`) because it
requires ObjC APIs (ScreenCaptureKit, AudioProcessTap). The C API:

```c
// Create a system audio tap
void *system_audio_tap_create(
    void (*callback)(void *ctx, void *buf, uint32_t frames, uint32_t channels),
    void *ctx
);

// Start audio delivery
int system_audio_tap_start(void *tap);

// Stop audio delivery
int system_audio_tap_stop(void *tap);

// Cleanup
void system_audio_tap_destroy(void *tap);
```

## Limitations

- **iOS**: System audio capture is not available on iOS (Apple's sandbox prevents it)
- **Simulator**: System audio capture only works on macOS; the iOS Simulator runs macOS but the sandboxed app can't access ProcessTap/SCK
- **Headless**: Works in headless environments (no display needed) on macOS 14.2+ with ProcessTap
- **Multiple taps**: Only one system audio tap can be active at a time per process
