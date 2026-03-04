# crystal-audio Testing Guide

This guide covers testing strategies for crystal-audio, including the existing spec suite, patterns for testing audio state machines without hardware, and cross-platform test organization.

## Table of Contents

- [Running Tests](#running-tests)
- [Current Test Coverage](#current-test-coverage)
- [Mock Strategies for Audio Apps](#mock-strategies-for-audio-apps)
  - [Init and State Testing Without Hardware](#init-and-state-testing-without-hardware)
  - [Return Code Testing](#return-code-testing)
  - [Platform-Conditional Compilation](#platform-conditional-compilation)
- [State Machine Testing Patterns](#state-machine-testing-patterns)
  - [Recorder Lifecycle](#recorder-lifecycle)
  - [Player Lifecycle](#player-lifecycle)
  - [AudioEngine Lifecycle](#audioengine-lifecycle)
  - [Transcription Pipeline Lifecycle](#transcription-pipeline-lifecycle)
- [Bridge Spec Replication Pattern](#bridge-spec-replication-pattern)
- [Cross-Platform Test Organization](#cross-platform-test-organization)
- [Adding New Tests](#adding-new-tests)

---

## Running Tests

crystal-audio uses Crystal's built-in `spec` framework. macOS is the default (and most complete) target platform.

```bash
# Run all specs
crystal spec

# Run all specs with the macOS flag (explicit)
crystal spec -Dmacos

# Run with verbose output
crystal spec --verbose

# Run a specific spec file
crystal spec spec/crystal_audio_spec.cr
```

If you are using the `crystal-alpha` compiler (required for iOS/Android cross-compilation):

```bash
crystal-alpha spec
crystal-alpha spec -Dmacos
```

---

## Current Test Coverage

The existing specs in `spec/crystal_audio_spec.cr` cover initialization and state queries for each major class. These tests verify that objects can be constructed and report correct default state without requiring microphone access or audio playback.

| Class | What Is Tested |
|-------|---------------|
| `CrystalAudio` | VERSION string is not empty |
| `CrystalAudio::MacOS` | macOS version detection, process tap availability |
| `CrystalAudio::Recorder` | Default source is Microphone, `recording?` is false, custom output paths |
| `CrystalAudio::AudioEngine` | AVAudioEngine pointer is non-nil, `running?` is false, input/output/mixer nodes |
| `CrystalAudio::AudioPlayerNode` | Pointer is non-nil, `playing?` is false, volume get/set |
| `CrystalAudio::Player` | Zero tracks, `playing?` is false, master volume default |
| `Transcription::TranscribeConfig` | Default language, translate flag, no_speech_thold |
| `Transcription::Segment` | Timestamp formatting, duration calculation |
| `Transcription::Pipeline` | Default mode is Dictation |

The macOS-specific tests (`MacOS`, `Recorder`, `AudioEngine`, `AudioPlayerNode`, `Player`) are guarded with `{% if flag?(:darwin) %}` so the spec file compiles on non-macOS platforms without error.

---

## Mock Strategies for Audio Apps

Audio hardware is not available in CI environments and should not be required for most spec runs. The following strategies let you test audio logic without recording or playing sound.

### Init and State Testing Without Hardware

Verify that constructors produce valid objects and that default state is correct. This catches regressions in initialization logic, option parsing, and property defaults.

```crystal
describe CrystalAudio::Recorder do
  it "defaults to Microphone source" do
    rec = CrystalAudio::Recorder.new
    rec.source.should eq(CrystalAudio::RecordingSource::Microphone)
  end

  it "is not recording after construction" do
    rec = CrystalAudio::Recorder.new
    rec.recording?.should be_false
  end

  it "accepts custom output paths" do
    rec = CrystalAudio::Recorder.new(
      source: CrystalAudio::RecordingSource::Both,
      output_path: "/tmp/sys.wav",
      mic_output_path: "/tmp/mic.wav"
    )
    rec.output_path.should eq("/tmp/sys.wav")
    rec.mic_output_path.should eq("/tmp/mic.wav")
  end
end
```

### Return Code Testing

Many CoreAudio functions return `OSStatus` integer codes. Test that your wrappers interpret these correctly.

```crystal
# Common CoreAudio status codes
SUCCESS       =  0
PARAM_ERROR   = -50
FORMAT_ERROR  = 1718449215  # kAudioFormatUnsupportedDataFormatError

it "treats zero as success" do
  (SUCCESS == 0).should be_true
end
```

When wrapping a C function that returns a status code, write specs that assert your Crystal wrapper raises or returns the expected result for both success and known error codes.

### Platform-Conditional Compilation

crystal-audio uses Crystal compile-time flags to gate platform-specific code. Specs should follow the same pattern.

```crystal
{% if flag?(:darwin) %}
  describe CrystalAudio::AudioEngine do
    it "wraps AVAudioEngine" do
      engine = CrystalAudio::AudioEngine.new
      engine.ptr.should_not be_nil
    end
  end
{% end %}

{% if flag?(:android) %}
  describe CrystalAudio::AAudioRecorder do
    it "initializes without error" do
      rec = CrystalAudio::AAudioRecorder.new
      rec.state.should eq(:idle)
    end
  end
{% end %}
```

This ensures that `crystal spec` compiles cleanly on every platform, even when the underlying native APIs are not available.

---

## State Machine Testing Patterns

Audio classes follow predictable state machine lifecycles. Test each transition and verify that invalid transitions are handled.

### Recorder Lifecycle

```
idle --> recording --> stopped
```

```crystal
describe "Recorder state machine" do
  it "starts in idle state" do
    rec = CrystalAudio::Recorder.new
    rec.recording?.should be_false
  end

  # This test requires hardware -- run manually, not in CI
  pending "transitions to recording after start" do
    rec = CrystalAudio::Recorder.new(output_path: "/tmp/test.wav")
    rec.start
    rec.recording?.should be_true
    rec.stop
  end

  # This test requires hardware -- run manually, not in CI
  pending "transitions to stopped after stop" do
    rec = CrystalAudio::Recorder.new(output_path: "/tmp/test.wav")
    rec.start
    rec.stop
    rec.recording?.should be_false
  end
end
```

Use `pending` for tests that need a live microphone. These serve as documentation and can be run during manual test sessions.

### Player Lifecycle

```
idle --> playing --> paused --> playing --> stopped
```

```crystal
describe "Player state machine" do
  it "starts with no tracks and not playing" do
    player = CrystalAudio::Player.new
    player.track_count.should eq(0)
    player.playing?.should be_false
  end

  it "reports master volume default" do
    player = CrystalAudio::Player.new
    player.master_volume.should eq(1.0_f32)
  end
end
```

### AudioEngine Lifecycle

```
uninitialized --> ready --> running --> shutdown
```

```crystal
{% if flag?(:darwin) %}
  describe "AudioEngine state machine" do
    it "initializes into ready state (not running)" do
      engine = CrystalAudio::AudioEngine.new
      engine.running?.should be_false
    end

    it "exposes audio nodes after initialization" do
      engine = CrystalAudio::AudioEngine.new
      engine.input_node.should_not be_nil
      engine.output_node.should_not be_nil
      engine.main_mixer_node.should_not be_nil
    end
  end
{% end %}
```

### Transcription Pipeline Lifecycle

```
configured --> processing --> complete
```

```crystal
describe "Transcription pipeline" do
  it "defaults to Dictation mode" do
    pipeline = CrystalAudio::Transcription::Pipeline.new
    pipeline.mode.should eq(CrystalAudio::Transcription::PipelineMode::Dictation)
  end

  it "builds config with sensible defaults" do
    config = CrystalAudio::Transcription::TranscribeConfig.new
    config.language.should eq("en")
    config.translate.should be_false
  end

  it "computes segment duration" do
    seg = CrystalAudio::Transcription::Segment.new("Hello", 1000_i64, 3500_i64)
    seg.duration_ms.should eq(2500)
  end
end
```

---

## Bridge Spec Replication Pattern

When crystal-audio is compiled into a host application (for example, Scribe compiles it as a static library linked into the final binary), you cannot link the crystal-audio `.o` files independently for testing. The `fun main` symbol in Crystal's runtime conflicts with the host app's entry point.

The solution is to replicate the state machine interface in your spec without linking the native code.

**How it works:**

1. Define a standalone module in your spec that mirrors the public state machine API (states, transitions, query methods).
2. Write specs against this replica.
3. The replica must stay in sync with the real implementation. When you change a state transition in the real code, update the replica.

```crystal
# spec/bridge_replica/recorder_state_spec.cr

# Replica of the recorder state machine -- no native code, no hardware
module RecorderStateReplica
  enum State
    Idle
    Recording
    Stopped
  end

  class StateMachine
    getter state : State = State::Idle

    def start
      raise "Cannot start from #{@state}" unless @state == State::Idle
      @state = State::Recording
    end

    def stop
      raise "Cannot stop from #{@state}" unless @state == State::Recording
      @state = State::Stopped
    end

    def recording? : Bool
      @state == State::Recording
    end
  end
end

describe RecorderStateReplica::StateMachine do
  it "starts idle" do
    sm = RecorderStateReplica::StateMachine.new
    sm.state.should eq(RecorderStateReplica::State::Idle)
    sm.recording?.should be_false
  end

  it "transitions idle -> recording -> stopped" do
    sm = RecorderStateReplica::StateMachine.new
    sm.start
    sm.recording?.should be_true
    sm.stop
    sm.recording?.should be_false
    sm.state.should eq(RecorderStateReplica::State::Stopped)
  end

  it "rejects invalid transitions" do
    sm = RecorderStateReplica::StateMachine.new
    expect_raises(RuntimeError) { sm.stop }
  end
end
```

This pattern was validated in Scribe's Epic 7 test suite (Option B approach), where 25 bridge state machine specs run without hardware dependencies.

---

## Cross-Platform Test Organization

macOS is the primary development platform. iOS and Android specs use conditional compilation flags.

```
spec/
  crystal_audio_spec.cr           # Main spec file (macOS-gated tests inside)
  bridge_replica/
    recorder_state_spec.cr        # State machine replica (no native deps)
  platform/
    macos_spec.cr                 # macOS-only tests ({% if flag?(:darwin) %})
    ios_spec.cr                   # iOS-only tests ({% if flag?(:ios) %})
    android_spec.cr               # Android-only tests ({% if flag?(:android) %})
```

Run platform-specific specs by passing the appropriate flag:

```bash
# macOS (default)
crystal-alpha spec

# iOS (cross-compilation context)
crystal-alpha spec -Dios

# Android (cross-compilation context)
crystal-alpha spec -Dandroid
```

---

## Adding New Tests

When adding a new feature to crystal-audio:

1. **Determine the platform scope.** If the feature is macOS-only, wrap the spec in `{% if flag?(:darwin) %}`. If it is cross-platform, write a platform-agnostic spec and add platform-gated sections as needed.

2. **Test init and defaults first.** Verify that the new class or method constructs without error and returns expected defaults. These tests run everywhere, including CI.

3. **Use `pending` for hardware-dependent tests.** Mark tests that require a microphone, speakers, or system audio with `pending`. Document what hardware is needed in the test description.

4. **Follow the state machine pattern.** If your feature has lifecycle states, test each valid transition and at least one invalid transition.

5. **Place specs in the correct file.**
   - General and cross-platform specs go in `spec/crystal_audio_spec.cr`.
   - State machine replicas go in `spec/bridge_replica/`.
   - Platform-specific specs go in `spec/platform/`.

6. **Name describe blocks after the full class path.**

```crystal
describe CrystalAudio::NewFeature do
  it "initializes with defaults" do
    # ...
  end
end
```
