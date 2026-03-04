# crystal_bridge.cr — C API exposed to Android JNI via jni_bridge.c
#
# Cross-compiled for Android:
#   crystal-alpha build crystal_bridge.cr \
#     --cross-compile --target aarch64-linux-android26 \
#     --define android --shared \
#     -o build/crystal_bridge

{% unless flag?(:android) || flag?(:darwin) %}
  {% raise "crystal_bridge.cr requires Android or Darwin target" %}
{% end %}

require "../../src/crystal_audio"

# C trace helper — on Android, writes to __android_log_print via jni_bridge.c
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
  @@player : CrystalAudio::Player? = nil

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

  def self.player : CrystalAudio::Player?
    @@player
  end

  def self.player=(p : CrystalAudio::Player?)
    @@player = p
  end

  def self.initialized? : Bool
    @@initialized
  end

  def self.initialized=(v : Bool)
    @@initialized = v
  end
end

# ---------------------------------------------------------------------------
# Public C API — called by jni_bridge.c
# ---------------------------------------------------------------------------

fun crystal_audio_init : LibC::Int
  LibTrace.crystal_trace("init: entered".to_unsafe)

  GC.init
  LibTrace.crystal_trace("init: GC.init done".to_unsafe)

  Crystal.init_runtime
  LibTrace.crystal_trace("init: Crystal.init_runtime done".to_unsafe)

  Thread.current
  LibTrace.crystal_trace("init: complete, returning 0".to_unsafe)
  Bridge.initialized = true
  0
rescue ex
  LibTrace.crystal_trace("init: EXCEPTION caught!".to_unsafe)
  -1
end

fun crystal_audio_start_recording(output_path : LibC::Char*) : LibC::Int
  LibTrace.crystal_trace("start_recording: entered".to_unsafe)
  return -1 if Bridge.recording?

  path = String.new(output_path)
  LibTrace.crystal_trace("start_recording: creating Recorder".to_unsafe)

  rec = CrystalAudio::Recorder.new(
    source:      CrystalAudio::RecordingSource::Microphone,
    output_path: path
  )
  rec.start

  Bridge.recorder = rec
  Bridge.recording = true
  LibTrace.crystal_trace("start_recording: returning 0".to_unsafe)
  0
rescue ex
  LibTrace.crystal_trace("start_recording: EXCEPTION".to_unsafe)
  Bridge.recording = false
  Bridge.recorder = nil
  -1
end

fun crystal_audio_stop_recording : LibC::Int
  LibTrace.crystal_trace("stop_recording: entered".to_unsafe)
  return -1 unless Bridge.recording?

  Bridge.recorder.try(&.stop)
  Bridge.recorder = nil
  Bridge.recording = false
  LibTrace.crystal_trace("stop_recording: done".to_unsafe)
  0
rescue
  -1
end

fun crystal_audio_is_recording : LibC::Int
  Bridge.recording? ? 1 : 0
end

fun crystal_audio_start_playback(paths : LibC::Char**, count : LibC::Int) : LibC::Int
  LibTrace.crystal_trace("start_playback: entered".to_unsafe)
  return -1 if count <= 0

  track_paths = Array(String).new(count)
  count.times do |i|
    track_paths << String.new(paths[i])
  end

  player = CrystalAudio::Player.new
  track_paths.each { |p| player.add_track(p) }
  player.play

  Bridge.player = player
  LibTrace.crystal_trace("start_playback: playing #{count} tracks".to_unsafe)
  0
rescue
  LibTrace.crystal_trace("start_playback: EXCEPTION".to_unsafe)
  -1
end

fun crystal_audio_stop_playback : LibC::Int
  LibTrace.crystal_trace("stop_playback: entered".to_unsafe)
  Bridge.player.try(&.stop)
  Bridge.player = nil
  LibTrace.crystal_trace("stop_playback: done".to_unsafe)
  0
rescue
  -1
end

# ---------------------------------------------------------------------------
# Media session callbacks — called from JNI when lock screen controls are used
# ---------------------------------------------------------------------------

fun crystal_on_media_play : Void
  LibTrace.crystal_trace("on_media_play".to_unsafe)
  Bridge.player.try(&.play)
end

fun crystal_on_media_pause : Void
  LibTrace.crystal_trace("on_media_pause".to_unsafe)
  Bridge.player.try(&.pause)
end

fun crystal_on_media_next : Void
  LibTrace.crystal_trace("on_media_next".to_unsafe)
  # User can override this behavior by setting a callback
end

fun crystal_on_media_previous : Void
  LibTrace.crystal_trace("on_media_previous".to_unsafe)
  # User can override this behavior by setting a callback
end

fun crystal_on_media_seek(position_ms : Int64) : Void
  LibTrace.crystal_trace("on_media_seek".to_unsafe)
  # Seek not yet implemented for AAudio player
end

fun crystal_on_media_stop : Void
  LibTrace.crystal_trace("on_media_stop".to_unsafe)
  Bridge.player.try(&.stop)
  Bridge.player = nil
end
