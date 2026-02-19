# crystal-audio

Record microphone input, system audio (what your computer is playing), or both streams simultaneously — on macOS, using Crystal.

**Platform:** macOS 14.2+ (recommended) | macOS 13.x (supported, see [Permissions](#permissions))

---

## What is crystal-audio?

crystal-audio is a Crystal library that wraps macOS CoreAudio and AVFoundation so you can capture audio from your microphone, your system output (Zoom calls, music, any app), or both at the same time into separate WAV files. The dual-stream mode is specifically useful for meeting workflows where you want to keep your own voice (dictation/notes) separate from the call audio. The library is designed to be embedded in your own Crystal programs or used directly from the included command-line recorder sample.

---

## Features

- Record from the built-in microphone or any audio input device
- Capture system audio — everything your Mac is playing — without a virtual audio driver
- Record microphone and system audio simultaneously into two separate files
- Output to WAV (lossless) or AAC (.m4a)
- No Screen Recording permission needed on macOS 14.2+ for system audio capture
- Clean API for embedding in your own Crystal programs
- Designed to extend with on-device transcription (whisper.cpp) or LLM post-processing

---

## Requirements

- **macOS 14.2+** (recommended)
  - System audio capture uses `AudioHardwareCreateProcessTap` — no Screen Recording permission required, no menu bar indicator
  - macOS 13.x is supported but requires Screen Recording permission for system audio (see [Permissions](#permissions))
- **Xcode Command Line Tools** — provides `clang` and the macOS SDKs

  ```bash
  xcode-select --install
  ```

- **Crystal 1.15.0 or newer**

  Install from [https://crystal-lang.org/install/](https://crystal-lang.org/install/) or via Homebrew:

  ```bash
  brew install crystal
  ```

---

## Quick Start

These steps get you from a fresh clone to recording audio in under two minutes.

**Step 1 — Clone the repository**

```bash
git clone https://github.com/crimson-knight/crystal-audio.git
cd crystal-audio
```

**Step 2 — Compile the native C/Objective-C extensions**

crystal-audio wraps macOS-native APIs that require compiled object files. This step only needs to be done once (or after `make clean`).

```bash
make ext
```

You should see output like:

```
  Built ext/block_bridge.o
  Built ext/objc_helpers.o
  Built ext/system_audio_tap.o
```

**Step 3 — Build the recorder sample**

```bash
make record
```

This compiles `samples/record/main.cr` and produces the `samples/record/record` binary.

**Step 4 — Record something**

```bash
# Record your microphone for 5 seconds
./samples/record/record

# Record meeting audio (system) + your voice (mic) simultaneously, for 60 seconds
./samples/record/record meeting 60
```

---

## Usage — record sample

The `record` binary accepts an optional mode, an optional duration (in seconds), and an optional output path. Everything has a sensible default.

```
./samples/record/record [mode] [seconds] [output.wav]
```

**Modes:**

| Mode | What it records |
|------|----------------|
| `mic` | Microphone only (default) |
| `meeting` | System audio + microphone simultaneously — two output files |
| `system` | System audio only (everything your Mac is playing) |

### Examples

```bash
# Record microphone for 5 seconds (defaults)
# Output: /tmp/recording_YYYYMMDD_HHMMSS.wav
./samples/record/record

# Record microphone for 30 seconds
./samples/record/record mic 30

# Record microphone for 10 seconds to a specific file
./samples/record/record mic 10 ~/my_notes.wav

# Record BOTH microphone AND system audio for 60 seconds
# Produces two files: /tmp/meeting_TIMESTAMP.wav (system) and /tmp/meeting_TIMESTAMP_dictation.wav (mic)
./samples/record/record meeting 60

# Record system audio only for 60 seconds (Zoom call, music, any app output)
./samples/record/record system 60

# Record system audio to a specific file
./samples/record/record system 60 ~/system_audio.wav
```

When you run any of these, the terminal shows you exactly what is being recorded and where the files will be saved before it starts. You can also press `Ctrl+C` at any time to stop early — the file is finalized cleanly.

**Example output:**

```
  crystal-audio recorder
  ─────────────────────────────────────
  Mode     : meeting
  Duration : 60s
  System   → /tmp/meeting_system_20260219_143022.wav
  Mic      → /tmp/meeting_20260219_143022_dictation.wav
  ─────────────────────────────────────
  Press Ctrl+C to stop early

  ● Recording
  [████████████░░░░░░░░░░░░░░░░░░] 38s remaining
```

After recording completes:

```
  Done.

  System audio → /tmp/meeting_system_20260219_143022.wav
  Mic audio    → /tmp/meeting_20260219_143022_dictation.wav

  Play:  afplay "/tmp/meeting_system_20260219_143022.wav"
```

---

## Permissions

### Microphone

macOS will show a permission prompt the first time you record from the microphone. Click "Allow". If you accidentally denied it, go to **System Settings → Privacy & Security → Microphone** and enable it for your terminal app.

### System Audio (macOS 14.2+)

No special permission is needed. crystal-audio uses `AudioHardwareCreateProcessTap`, a CoreAudio API introduced in macOS 14.2 that captures process audio without requiring Screen Recording access and without showing a menu bar indicator.

### System Audio (macOS 13.x)

On macOS 13.x, system audio capture falls back to `ScreenCaptureKit`. This requires **Screen Recording permission**:

1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable it for your terminal app (Terminal, iTerm2, etc.)
3. Re-run your command

---

## Using as a Library

Add crystal-audio to your project's `shard.yml`:

```yaml
dependencies:
  crystal-audio:
    github: crimson-knight/crystal-audio
```

Run `shards install`, then compile the native extensions from inside the dependency directory:

```bash
cd lib/crystal-audio
make ext
cd ../..
```

When building your project, you must pass the extension object files and frameworks as link flags:

```bash
crystal build src/main.cr \
  --link-flags="$(pwd)/lib/crystal-audio/ext/block_bridge.o \
                $(pwd)/lib/crystal-audio/ext/objc_helpers.o \
                $(pwd)/lib/crystal-audio/ext/system_audio_tap.o \
                -framework AVFoundation -framework AudioToolbox \
                -framework CoreAudio -framework CoreFoundation \
                -framework CoreMedia -framework Foundation \
                -framework ScreenCaptureKit"
```

### Record from microphone

```crystal
require "crystal_audio"

rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Microphone,
  output_path: "/tmp/my_recording.wav"
)

rec.start
sleep 10.seconds
rec.stop

# File is ready at /tmp/my_recording.wav
```

`RecordingSource::Microphone` records from the default system input (built-in mic or whatever is selected in System Settings → Sound → Input).

### Record system audio only

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

This captures everything your Mac is playing — Zoom calls, browser audio, music, any app.

### Record both streams simultaneously (meeting + dictation)

This is the most useful mode for meeting workflows. The system audio (what everyone else is saying) and your microphone (your voice, notes, reactions) are captured into two separate files so you can process or transcribe them independently.

```crystal
require "crystal_audio"

rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Both,
  output_path: "/tmp/meeting_system.wav",      # system audio goes here
  mic_output_path: "/tmp/meeting_mic.wav"      # your microphone goes here
)

rec.start
puts "Recording... press Ctrl+C to stop"

Signal::INT.trap do
  rec.stop
  puts "\nSaved."
  exit 0
end

sleep  # wait indefinitely until Ctrl+C
```

When you call `rec.stop`, both files are finalized and ready to play or process.

### Output format

The output format is determined by the file extension you provide:

- `.wav` — lossless PCM (default, recommended for further processing)
- `.m4a` — AAC compressed

```crystal
# Compressed AAC output
rec = CrystalAudio::Recorder.new(
  source: CrystalAudio::RecordingSource::Microphone,
  output_path: "/tmp/recording.m4a"
)
```

---

## Troubleshooting

**"Permission denied" when recording microphone**

macOS denied microphone access. Go to **System Settings → Privacy & Security → Microphone** and enable access for your terminal app, then try again.

**Build fails with `xcrun: error: unable to find utility "clang"`**

Xcode Command Line Tools are not installed or need to be reinstalled:

```bash
xcode-select --install
```

If that does not work, try:

```bash
sudo xcode-select --reset
```

**System audio is not being captured (silent output file)**

- Check your macOS version: `sw_vers -productVersion`. System audio requires macOS 13.0 or newer.
- On macOS 13.x, grant Screen Recording permission in **System Settings → Privacy & Security → Screen Recording**.
- On macOS 14.2+, no permission is needed — if the file is silent, make sure audio is actually playing from another app during the recording.

**`crystal: command not found`**

Crystal is not installed or is not on your PATH. Install it from [https://crystal-lang.org/install/](https://crystal-lang.org/install/) and follow the PATH instructions for your shell.

**`make ext` fails with missing framework headers**

Your Xcode SDK path may be stale after a macOS or Xcode update:

```bash
sudo xcode-select --reset
make clean
make ext
```

---

## Architecture

crystal-audio uses two separate macOS audio paths depending on the recording source:

**Microphone recording** uses `AudioQueue` from the CoreAudio C API. This is a low-level, callback-driven API that buffers audio on an OS audio thread and writes PCM frames to disk via `ExtAudioFile`. It does not require Objective-C or any blocks-based API.

**System audio on macOS 14.2+** uses `AudioHardwareCreateProcessTap` (CATap). This API can attach to any running process's audio output and receive its audio frames without needing Screen Recording access. It captures at the process level, so it is unaffected by volume settings.

**System audio on macOS 13.x** uses `ScreenCaptureKit`'s `SCStream` in audio-only mode. This is the same framework used for screen recording, which is why Screen Recording permission is required, even though no video is captured.

Both mic and system paths can run in parallel without conflict. When using `RecordingSource::Both`, the two streams write to independent files simultaneously.

```
crystal-audio/
├── ext/
│   ├── block_bridge.c        Objective-C block factory (Crystal callbacks → AVFoundation)
│   ├── objc_helpers.c        Objective-C runtime helpers
│   └── system_audio_tap.m    System audio capture (CATap on 14.2+, SCStream on 13.x)
└── src/crystal_audio/
    ├── audio/
    │   ├── audio_toolbox.cr  AudioQueue + ExtAudioFile bindings (mic recording)
    │   ├── av_foundation.cr  AVAudioEngine wrapper (multi-track playback)
    │   ├── block_bridge.cr   Crystal lib for ext/block_bridge.c
    │   └── system_audio.cr   SystemAudioCapture class
    ├── foundation/
    │   ├── core_foundation.cr  CFString, CFURL helpers
    │   └── objc_bridge.cr      Typed objc_msgSend wrappers
    ├── recorder.cr           High-level Recorder class (mic, system, or both)
    └── player.cr             Multi-track Player (AVAudioEngine-backed)
```

**Do I need the crystal-alpha compiler fork?**

- **macOS:** No. Stock Crystal 1.15.0 or newer is all you need.
- **iOS / Android:** Yes. Cross-compilation for mobile requires the [crystal-alpha](https://github.com/crimson-knight/crystal) compiler fork.

---

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/crimson-knight/crystal-audio).

---

## License

MIT — see [LICENSE](LICENSE).
