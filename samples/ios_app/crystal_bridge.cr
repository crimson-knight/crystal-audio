# crystal_bridge.cr — C API exposed to Swift via crystal_bridge.h
#
# Compiled as a static library for iOS simulator:
#
#   crystal-alpha build samples/ios_app/crystal_bridge.cr \
#     --target arm64-apple-ios-simulator \
#     --cross-compile \
#     --define ios \
#     --define shared \
#     -o samples/ios_app/build/crystal_bridge

{% unless flag?(:darwin) %}
  {% raise "crystal_bridge.cr requires a Darwin target (macOS or iOS)" %}
{% end %}

require "../../src/crystal_audio"

# Override Crystal's auto-generated main (unix/main.cr defines one unconditionally).
# Swift provides @main; Crystal's main must be a no-op.
# The _main symbol is also made local via ld -r after cross-compilation.
fun main(argc : Int32, argv : UInt8**) : Int32
  0
end

# C trace helper — writes to stderr with zero Crystal runtime dependency
lib LibTrace
  fun crystal_trace(msg : UInt8*)
end

# ---------------------------------------------------------------------------
# Module-level state
# ---------------------------------------------------------------------------

private module Bridge
  @@initialized : Bool = false
  @@recorder : CrystalAudio::Recorder? = nil
  @@recording : Bool = false

  def self.recorder : CrystalAudio::Recorder?
    @@recorder
  end

  def self.recorder=(r : CrystalAudio::Recorder?)
    @@recorder = r
  end

  def self.recording? : Bool
    @@recording
  end

  def self.recording=(v : Bool)
    @@recording = v
  end

  def self.initialized? : Bool
    @@initialized
  end

  def self.initialized=(v : Bool)
    @@initialized = v
  end
end

# ---------------------------------------------------------------------------
# Public C API — callable from Swift via the bridging header
# ---------------------------------------------------------------------------

fun crystal_audio_init : LibC::Int
  LibTrace.crystal_trace("init: entered".to_unsafe)

  LibTrace.crystal_trace("init: calling GC.init".to_unsafe)
  GC.init
  LibTrace.crystal_trace("init: GC.init done".to_unsafe)

  LibTrace.crystal_trace("init: calling Crystal.init_runtime".to_unsafe)
  Crystal.init_runtime
  LibTrace.crystal_trace("init: Crystal.init_runtime done".to_unsafe)

  LibTrace.crystal_trace("init: calling Thread.current".to_unsafe)
  Thread.current
  LibTrace.crystal_trace("init: Thread.current done".to_unsafe)

  LibTrace.crystal_trace("init: complete, returning 0".to_unsafe)
  0
rescue ex
  LibTrace.crystal_trace("init: EXCEPTION caught!".to_unsafe)
  -1
end

fun crystal_audio_start_mic(output_path : LibC::Char*) : LibC::Int
  LibTrace.crystal_trace("start_mic: entered".to_unsafe)

  LibTrace.crystal_trace("start_mic: checking Bridge.recording?".to_unsafe)
  if Bridge.recording?
    LibTrace.crystal_trace("start_mic: already recording".to_unsafe)
    return -1
  end

  LibTrace.crystal_trace("start_mic: creating String".to_unsafe)
  path = String.new(output_path)
  LibTrace.crystal_trace("start_mic: String done".to_unsafe)

  LibTrace.crystal_trace("start_mic: creating Recorder".to_unsafe)
  rec = CrystalAudio::Recorder.new(
    source:      CrystalAudio::RecordingSource::Microphone,
    output_path: path
  )
  LibTrace.crystal_trace("start_mic: Recorder created".to_unsafe)

  LibTrace.crystal_trace("start_mic: calling rec.start".to_unsafe)
  rec.start
  LibTrace.crystal_trace("start_mic: rec.start done".to_unsafe)

  Bridge.recorder = rec
  Bridge.recording = true
  LibTrace.crystal_trace("start_mic: returning 0".to_unsafe)
  0
rescue ex
  LibTrace.crystal_trace("start_mic: EXCEPTION caught!".to_unsafe)
  Bridge.recording = false
  Bridge.recorder = nil
  -1
end

fun crystal_audio_stop : LibC::Int
  LibTrace.crystal_trace("stop: entered".to_unsafe)
  return -1 unless Bridge.recording?

  Bridge.recorder.try(&.stop)
  Bridge.recorder = nil
  Bridge.recording = false
  LibTrace.crystal_trace("stop: done".to_unsafe)
  0
rescue
  -1
end

fun crystal_audio_is_recording : LibC::Int
  Bridge.recording? ? 1 : 0
end
