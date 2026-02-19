{% if flag?(:darwin) %}

# System audio capture — binds ext/system_audio_tap.m
#
# Captures all system audio output (what you'd hear through the speakers)
# without requiring a virtual audio driver.
#
# macOS 14.2+: Uses AudioHardwareCreateProcessTap + aggregate device.
#   Permission: NSAudioCaptureUsageDescription (no Screen Recording needed)
#
# macOS 13.x fallback: Uses ScreenCaptureKit SCStream.
#   Permission: Screen & System Audio Recording
#
# Both paths are wrapped by system_audio_tap.m; this file binds its C API.

lib LibSystemAudioTap
  alias Handle   = Void*
  alias OSStatus = Int32

  # Callback: called on the audio IOProc thread (real-time, no allocations!)
  # frames: interleaved float32 PCM at 48000 Hz (stereo)
  alias Callback = (Float32*, UInt32, UInt32, Void*) -> Void

  fun system_audio_tap_create(
    callback  : Callback,
    context   : Void*,
    out_error : OSStatus*
  ) : Handle

  fun system_audio_tap_start(handle : Handle) : OSStatus
  fun system_audio_tap_stop(handle : Handle) : OSStatus
  fun system_audio_tap_destroy(handle : Handle)
end

module CrystalAudio
  # Captures system audio (what's playing through the speakers).
  # Runs the callback on a real-time audio thread — keep it allocation-free.
  #
  # Example:
  #   tap = SystemAudioCapture.new
  #   tap.start do |frames, frame_count, channels|
  #     # frames is a Slice(Float32) of interleaved PCM
  #   end
  #   sleep 10.seconds
  #   tap.stop
  class SystemAudioCapture
    SAMPLE_RATE   = 48_000.0
    CHANNEL_COUNT =       2_u32

    @handle : LibSystemAudioTap::Handle
    @box : Void*

    # Kept as a class-level collection so GC doesn't collect live captures
    @@active = [] of SystemAudioCapture

    def initialize
      @handle = Pointer(Void).null
      @box = Pointer(Void).null
    end

    # Start capturing system audio. The block receives a Slice(Float32) of
    # interleaved stereo samples at 48 kHz.
    # IMPORTANT: The block runs on a real-time thread. No Crystal allocations.
    def start(&callback : Slice(Float32), UInt32, UInt32 -> Nil)
      raise "Already started" unless @handle.null?

      boxed = Box.box(callback)
      @box = boxed
      @@active << self

      c_callback = LibSystemAudioTap::Callback.new do |frames_ptr, frame_count, channel_count, ctx|
        blk = Box(typeof(callback)).unbox(ctx)
        slice = Slice(Float32).new(frames_ptr, (frame_count * channel_count).to_i32, read_only: true)
        blk.call(slice, frame_count, channel_count)
      end

      err = 0_i32
      @handle = LibSystemAudioTap.system_audio_tap_create(c_callback, boxed, pointerof(err))
      raise "system_audio_tap_create failed: OSStatus #{err}" if @handle.null?

      status = LibSystemAudioTap.system_audio_tap_start(@handle)
      raise "system_audio_tap_start failed: OSStatus #{status}" unless status == 0
    end

    def stop
      return if @handle.null?
      LibSystemAudioTap.system_audio_tap_stop(@handle)
      LibSystemAudioTap.system_audio_tap_destroy(@handle)
      @handle = Pointer(Void).null
      @@active.delete(self)
      @box = Pointer(Void).null
    end

    def active? : Bool
      !@handle.null?
    end
  end
end

{% end %}
