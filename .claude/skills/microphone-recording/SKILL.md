---
name: microphone-recording
description: |
  Record audio from the microphone using crystal-audio's Recorder class. Covers AudioQueue
  configuration, WAV output, buffer management, and real-time audio callback patterns.
  Use this when implementing mic recording features in Crystal.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
version: "0.1.0"
---

# Microphone Recording with crystal-audio

## Recorder API

```crystal
require "crystal_audio"

rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Microphone,
  output_path: "/tmp/recording.wav"
)

rec.start      # Begin recording
rec.recording? # => true
rec.stop       # Stop and finalize WAV file
```

### Constructor Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `source` | `RecordingSource` | required | `:microphone`, `:system`, or `:both` |
| `output_path` | `String` | `"/tmp/recording.wav"` | WAV file output path |
| `mic_output_path` | `String?` | `nil` | Separate mic file when `source: :both` |

### Audio Configuration (constants)

| Constant | Value | Description |
|----------|-------|-------------|
| `SAMPLE_RATE` | `44_100.0` | Hz, CD quality |
| `CHANNELS` | `1` | Mono |
| `BITS_PER_SAMPLE` | `16` | 16-bit PCM |
| `BUFFER_SIZE` | `0x4000` (16 KB) | ~185ms per buffer |
| `NUM_BUFFERS` | `3` | Triple buffering |

## How It Works

The recorder uses Apple's AudioQueue Services:

1. **Setup**: Creates an `AudioStreamBasicDescription` for Linear PCM (mono, 16-bit, 44.1 kHz)
2. **Queue**: Allocates an AudioQueue input with triple-buffered callbacks
3. **Callback**: Each filled buffer is written to an `ExtAudioFile` via a C helper (`ca_ext_audio_file_write_pcm`) that safely constructs the `AudioBufferList` on the C stack
4. **Finalize**: `stop` disposes the queue and closes the ExtAudioFile, finalizing the WAV header

### The AudioBufferList C Helper

Direct construction of `AudioBufferList` from Crystal hits a known issue: the struct contains a flexible array member that Crystal's struct layout cannot represent. The library uses a C helper:

```c
// ext/audio_write_helper.c
OSStatus ca_ext_audio_file_write_pcm(
    ExtAudioFileRef file,
    UInt32 num_frames,
    void *data,
    UInt32 data_byte_size,
    UInt32 num_channels
);
```

This constructs the `AudioBufferList` on the C stack and calls `ExtAudioFileWrite`. Always use this helper instead of constructing AudioBufferList in Crystal.

## Patterns

### Timed Recording

```crystal
rec = CrystalAudio::Recorder.new(
  source: :microphone,
  output_path: "/tmp/timed.wav"
)
rec.start
sleep 30.seconds
rec.stop
```

### Record Until User Input

```crystal
rec = CrystalAudio::Recorder.new(
  source: :microphone,
  output_path: "/tmp/interactive.wav"
)

puts "Press Enter to start..."
gets
rec.start
puts "Recording. Press Enter to stop..."
gets
rec.stop
puts "Saved to #{rec.output_path}"
```

### Record with Timer Display

```crystal
rec = CrystalAudio::Recorder.new(
  source: :microphone,
  output_path: "/tmp/with_timer.wav"
)

rec.start
start = Time.monotonic
loop do
  elapsed = (Time.monotonic - start).total_seconds.to_i
  print "\rRecording: #{elapsed / 60}:#{(elapsed % 60).to_s.rjust(2, '0')}"
  sleep 1.second
  break if elapsed >= 60  # Stop after 1 minute
end
rec.stop
puts "\nSaved."
```

### Simultaneous Mic + System Audio

```crystal
rec = CrystalAudio::Recorder.new(
  source: :both,
  output_path: "/tmp/system.wav",
  mic_output_path: "/tmp/mic.wav"
)

rec.start
sleep 30.seconds
rec.stop
# Two files: system.wav (stereo 48kHz) and mic.wav (mono 44.1kHz)
```

## Error Handling

The Recorder raises on AudioQueue or ExtAudioFile failures. Wrap in begin/rescue:

```crystal
begin
  rec = CrystalAudio::Recorder.new(source: :microphone, output_path: path)
  rec.start
rescue ex
  STDERR.puts "Recording failed: #{ex.message}"
end
```

Common errors:
- **Permission denied**: macOS requires microphone permission. Add `NSMicrophoneUsageDescription` to Info.plist
- **Invalid output path**: Ensure the directory exists and is writable
- **AudioQueue error**: Usually means no audio input device is available

## Platform Notes

### macOS
- Works with stock Crystal compiler
- No special permissions needed for mic-only recording (system prompts user)
- Info.plist with `NSMicrophoneUsageDescription` required for bundled apps

### iOS
- Requires crystal-alpha compiler for cross-compilation
- Must call `crystal_audio_init()` before any recording (initializes Crystal runtime)
- Must use `-force_load` linker flag for the Crystal static library (prevents dead-stripping)
- AVAudioSession must be configured for `.record` category before starting
- See `/ios-integration` skill for the complete guide
