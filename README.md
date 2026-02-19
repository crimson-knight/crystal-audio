# crystal-audio

Cross-platform audio library for Crystal. Microphone capture, multi-track
playback, parallel system audio + mic recording, and on-device transcription
via [whisper.cpp](https://github.com/ggml-org/whisper.cpp).

**Platform support:**

| Feature | macOS | iOS | Android |
|---|---|---|---|
| Microphone recording | ✅ stock Crystal | 🔧 crystal-alpha | 🗓 planned |
| System audio capture | ✅ 14.2+ (no SCK perm) / 13.0+ (SCK) | ❌ sandboxed | ❌ |
| Multi-track playback | ✅ | 🔧 crystal-alpha | 🗓 planned |
| whisper.cpp transcription | ✅ | 🔧 crystal-alpha | 🗓 planned |
| iOS lock screen controls | — | 🔧 crystal-alpha | — |

🔧 = requires [crystal-alpha](https://github.com/crimson-knight/crystal) compiler fork

---

## Quick Start

### Prerequisites

```bash
# Xcode Command Line Tools (clang, frameworks)
xcode-select --install

# Stock Crystal (macOS)
brew install crystal

# crystal-alpha (for iOS/Android targets)
brew install crimsonknight/crystal-alpha/crystal-alpha
```

### Installation

Add to your `shard.yml`:

```yaml
dependencies:
  crystal-audio:
    github: crimson-knight/crystal-audio
```

Compile the native extensions (required before building):

```bash
cd lib/crystal-audio
make ext
```

### Record from microphone

```crystal
require "crystal-audio"

recorder = CrystalAudio::Recorder.new(
  source:      CrystalAudio::RecordingSource::Microphone,
  output_path: "/tmp/recording.wav"
)

recorder.start
sleep 10.seconds
recorder.stop

# -> /tmp/recording.wav
```

### Record meeting audio + dictation simultaneously

```crystal
require "crystal-audio"

# System audio (Zoom/Teams call) + microphone (your dictation) — in parallel
recorder = CrystalAudio::Recorder.new(
  source:          CrystalAudio::RecordingSource::Both,
  output_path:     "/tmp/meeting_system.wav",
  mic_output_path: "/tmp/meeting_dictation.wav"
)

recorder.start
puts "Recording... Ctrl+C to stop"
Signal::INT.trap { recorder.stop; exit }
sleep
```

### Transcribe with whisper.cpp

```crystal
require "crystal-audio"

# Load model (download separately — see Transcription Setup below)
ctx = CrystalAudio::Transcription::WhisperContext.new(
  "~/.local/share/crystal-audio/models/ggml-base.en-q5_1.bin"
)

# Load audio (must be float32 16kHz mono)
samples = File.read("/tmp/recording.raw")  # your PCM data
slice = samples.to_slice.unsafe_as(Slice(Float32))

ctx.transcribe(slice) do |segment|
  puts segment
end
```

### Real-time dictation (chunked streaming)

```crystal
require "crystal-audio"

streamer = CrystalAudio::Transcription::Streamer.new(
  "~/.local/share/crystal-audio/models/ggml-base.en-q5_1.bin"
) do |segment|
  print segment.text  # text appears as you speak
  STDOUT.flush
end

recorder = CrystalAudio::Recorder.new(source: CrystalAudio::RecordingSource::Microphone)
# TODO: wire recorder PCM output → streamer.push(samples)
recorder.start
sleep
```

### Transcription + LLM formatting

```crystal
require "crystal-audio"

pipeline = CrystalAudio::Transcription::Pipeline.new(
  mode:    CrystalAudio::Transcription::PipelineMode::Meeting,
  api_key: ENV["ANTHROPIC_API_KEY"]
)

segments = ctx.transcribe(audio_samples)
formatted = pipeline.format(segments)
puts formatted
# -> ## Summary\n...\n## Action Items\n...
```

---

## System Audio Capture

Captures what's playing through your speakers without a virtual audio driver.

**macOS 14.2+** (recommended): Uses `AudioHardwareCreateProcessTap`. Requires
only `NSAudioCaptureUsageDescription` — no Screen Recording permission, no
menu bar indicator.

**macOS 13.x fallback**: Uses `ScreenCaptureKit`. Requires Screen Recording
permission. Shows indicator in menu bar on macOS 14+.

Both paths run in parallel with microphone capture with no conflicts.

For a Swift shell app (recommended for distribution), add to `Info.plist`:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>Records system audio for meeting transcription.</string>
```

---

## Transcription Setup

```bash
# Clone and build whisper.cpp with CoreML (Apple Neural Engine)
git clone https://github.com/ggml-org/whisper.cpp.git ~/src/whisper.cpp
cd ~/src/whisper.cpp

# Install Python dependencies for CoreML model conversion
python3 -m venv .venv && source .venv/bin/activate
pip install ane_transformers openai-whisper coremltools

# Download model and generate CoreML encoder
./models/download-ggml-model.sh base.en
./models/generate-coreml-model.sh base.en

# Build with CoreML + Metal GPU
cmake -B build -DWHISPER_COREML=1 -DWHISPER_METAL=1 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(sysctl -n hw.logicalcpu)

# Copy model to expected location
mkdir -p ~/.local/share/crystal-audio/models
cp models/ggml-base.en.bin models/ggml-base.en-encoder.mlmodelc \
   ~/.local/share/crystal-audio/models/
```

### Recommended models

| Use case | Model | Size | Latency per 3s |
|---|---|---|---|
| Dictation (bundled) | `base.en-q5_1` | 57 MB | ~60ms (CoreML) |
| Dictation (quality) | `small.en-q5_1` | 181 MB | ~180ms |
| Meeting batch | `large-v3-turbo-q5_0` | 547 MB | ~600ms |

---

## Building

```bash
# Compile native extensions (required once)
make ext

# Build mic_recorder sample
make sample
./samples/mic_recorder/mic_recorder 5 /tmp/test.wav

# Run specs
make spec
```

### Linking in your own project

After `make ext`, add to your build command:

```bash
crystal build src/main.cr \
  --link-flags="$(pwd)/lib/crystal-audio/ext/block_bridge.o \
                $(pwd)/lib/crystal-audio/ext/system_audio_tap.o \
                -framework AVFoundation -framework AudioToolbox \
                -framework CoreAudio -framework CoreFoundation \
                -framework ScreenCaptureKit"
```

---

## Architecture

```
crystal-audio/
├── ext/
│   ├── block_bridge.c       ObjC block factory (Crystal → AVFoundation callbacks)
│   └── system_audio_tap.m   macOS system audio capture (CATap + SCStream)
└── src/crystal_audio/
    ├── audio/
    │   ├── audio_toolbox.cr  AudioQueue + ExtAudioFile (mic recording, no blocks)
    │   ├── av_foundation.cr  AVAudioEngine wrapper (multi-track playback)
    │   ├── block_bridge.cr   Crystal lib for ext/block_bridge.c
    │   └── system_audio.cr   SystemAudioCapture class (binds ext/system_audio_tap.m)
    ├── foundation/
    │   ├── core_foundation.cr  CFString, CFURL helpers
    │   └── objc_bridge.cr      Typed objc_msgSend wrappers
    ├── transcription/
    │   ├── whisper.cr    LibWhisper FFI + WhisperContext + Streamer
    │   └── pipeline.cr   Two-stage pipeline: whisper → Claude API formatting
    ├── recorder.cr       High-level Recorder (mic, system, or both)
    └── player.cr         Multi-track Player (AVAudioEngine-backed)
```

**Does this need the crystal-alpha compiler?**

- **macOS**: No. Stock Crystal (≥ 1.15.0) is sufficient.
- **iOS**: Yes. Cross-compilation requires the [crystal-alpha](https://github.com/crimson-knight/crystal) fork.
- **Android**: Yes, and AAudio bindings are planned.

---

## License

MIT — see [LICENSE](LICENSE).
