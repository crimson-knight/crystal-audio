{% if flag?(:darwin) %}

# ObjC runtime bridge — binds ext/objc_helpers.c typed wrappers.
#
# Crystal cannot alias the same C symbol with different return types in one
# lib block, so ext/objc_helpers.c provides a thin typed wrapper per call
# signature. The C compiler handles ARM64 register placement correctly.

@[Link(framework: "Foundation")]
lib LibObjC
  alias Id  = Void*
  alias Sel = Void*
  alias Cls = Void*

  # Raw runtime — used for class/selector registration only
  fun objc_getClass(name : LibC::Char*) : Cls
  fun sel_registerName(name : LibC::Char*) : Sel
  fun object_getClass(obj : Id) : Cls
  fun objc_alloc(cls : Cls) : Id

  fun objc_allocateClassPair(
    superclass  : Cls,
    name        : LibC::Char*,
    extra_bytes : LibC::SizeT
  ) : Cls
  fun objc_registerClassPair(cls : Cls)
  fun class_addMethod(cls : Cls, name : Sel, imp : Void*, types : LibC::Char*) : Bool
end

# Typed message-send wrappers from ext/objc_helpers.c
lib LibObjCHelpers
  # → Id
  fun ca_msg_id(obj : Void*, sel : Void*) : Void*
  fun ca_msg_id_id(obj : Void*, sel : Void*, a1 : Void*) : Void*
  fun ca_msg_id_id_id(obj : Void*, sel : Void*, a1 : Void*, a2 : Void*) : Void*

  # → Void
  fun ca_msg_void(obj : Void*, sel : Void*)
  fun ca_msg_void_id(obj : Void*, sel : Void*, a1 : Void*)
  fun ca_msg_void_id_id_id(obj : Void*, sel : Void*, a1 : Void*, a2 : Void*, a3 : Void*)
  fun ca_msg_void_id_nil_nil(obj : Void*, sel : Void*, a1 : Void*)  # scheduleFile:atTime:completionHandler:
  fun ca_msg_void_f32(obj : Void*, sel : Void*, value : Float32)

  # → Bool
  fun ca_msg_bool(obj : Void*, sel : Void*) : Bool
  fun ca_msg_bool_err(obj : Void*, sel : Void*, out_err : Void**) : Bool

  # → Float32
  fun ca_msg_f32(obj : Void*, sel : Void*) : Float32

  # → UInt32
  fun ca_msg_u32(obj : Void*, sel : Void*) : UInt32

  # → Float64
  fun ca_msg_f64(obj : Void*, sel : Void*) : Float64

  # → Int64
  fun ca_msg_i64(obj : Void*, sel : Void*) : Int64

  # Void with double arg
  fun ca_msg_void_f64(obj : Void*, sel : Void*, value : Float64)

  # Void with NSUInteger arg (setPlaybackState:)
  fun ca_msg_void_u64(obj : Void*, sel : Void*, value : UInt64)

  # AVAudioFile: [[AVAudioFile alloc] initForReading:url error:&err]
  fun ca_audio_file_open(url : Void*) : Void*

  # AVAudioTime helpers
  fun ca_audio_time_sample(sample_time : Int64, sample_rate : Float64) : Void*
  fun ca_audio_time_get_sample(time : Void*) : Int64
  fun ca_audio_time_get_rate(time : Void*) : Float64
  fun ca_audio_time_valid(time : Void*) : Bool

  # scheduleFile:atTime:completionHandler: with time (handler = nil)
  fun ca_msg_void_id_id_nil(obj : Void*, sel : Void*, a1 : Void*, a2 : Void*)

  # scheduleFile:atTime:completionCallbackType:completionHandler:
  fun ca_schedule_file_with_completion(node : Void*, file : Void*, callback_type : UInt64, block : Void*)

  # NSDictionary / NSNumber helpers
  fun ca_nsdictionary_create(keys : Void**, values : Void**, count : UInt32) : Void*
  fun ca_nsnumber_double(value : Float64) : Void*
  fun ca_nsnumber_long(value : Int64) : Void*

  # [[ClassName alloc] init]
  fun ca_alloc_init(class_name : LibC::Char*) : Void*

  # ── Looping playback (scheduleBuffer:options:.loops) ────────────────────────
  fun ca_pcm_buffer_for_file(file : Void*) : Void*
  fun ca_pcm_buffer_create(format : Void*, frame_capacity : UInt32) : Void*
  fun ca_schedule_buffer_loops(player : Void*, buffer : Void*)

  # ── Offline (manual) rendering — deterministic, no audio device ─────────────
  fun ca_engine_enable_manual_rendering(engine : Void*, format : Void*, max_frames : UInt32) : Bool
  fun ca_engine_manual_rendering_format(engine : Void*) : Void*
  fun ca_engine_render_offline(engine : Void*, frames : UInt32, out_buffer : Void*) : Int64

  # ── PCM buffer inspection (verification) ────────────────────────────────────
  fun ca_pcm_buffer_frame_length(buffer : Void*) : UInt32
  fun ca_pcm_buffer_rms(buffer : Void*, start_frame : UInt32, count : UInt32) : Float64

  # ── Playback position / duration ────────────────────────────────────────────
  fun ca_format_sample_rate(format : Void*) : Float64
  fun ca_player_node_position_samples(node : Void*) : Int64
end

module CrystalAudio
  module ObjC
    # ── Selector / class helpers ──────────────────────────────────────────────

    def self.cls(name : String) : LibObjC::Cls
      LibObjC.objc_getClass(name.to_unsafe)
    end

    def self.sel(name : String) : LibObjC::Sel
      LibObjC.sel_registerName(name.to_unsafe)
    end

    # [[ClassName alloc] init]
    def self.alloc_init(class_name : String) : LibObjC::Id
      obj = LibObjCHelpers.ca_alloc_init(class_name.to_unsafe)
      raise "Failed to alloc/init #{class_name}" if obj.null?
      obj
    end

    # ── Typed message senders ─────────────────────────────────────────────────

    # no-arg → Id
    def self.send(receiver : LibObjC::Id, selector : String) : LibObjC::Id
      LibObjCHelpers.ca_msg_id(receiver, sel(selector))
    end

    # one-id-arg → Id
    def self.send(receiver : LibObjC::Id, selector : String, arg : LibObjC::Id) : LibObjC::Id
      LibObjCHelpers.ca_msg_id_id(receiver, sel(selector), arg)
    end

    # no-arg → Void
    def self.send_void(receiver : LibObjC::Id, selector : String)
      LibObjCHelpers.ca_msg_void(receiver, sel(selector))
    end

    # one-id-arg → Void
    def self.send_void(receiver : LibObjC::Id, selector : String, arg : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id(receiver, sel(selector), arg)
    end

    # no-arg → Bool (isRunning, isPlaying, etc.)
    def self.send_bool(receiver : LibObjC::Id, selector : String) : Bool
      LibObjCHelpers.ca_msg_bool(receiver, sel(selector))
    end

    # no-arg → Float32 (volume, outputVolume)
    def self.send_f32(receiver : LibObjC::Id, selector : String) : Float32
      LibObjCHelpers.ca_msg_f32(receiver, sel(selector))
    end

    # float setter (setVolume:, setOutputVolume:)
    def self.set_f32(receiver : LibObjC::Id, selector : String, value : Float32)
      LibObjCHelpers.ca_msg_void_f32(receiver, sel(selector), value)
    end

    # attachNode: / detachNode:
    def self.attach(engine : LibObjC::Id, node : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id(engine, sel("attachNode:"), node)
    end

    # connect:to:format:
    def self.connect(engine : LibObjC::Id, from : LibObjC::Id, to : LibObjC::Id, format : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id_id_id(engine, sel("connect:to:format:"), from, to, format)
    end

    # scheduleFile:atTime:completionHandler: (atTime + handler = nil)
    def self.schedule_file(player : LibObjC::Id, file : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id_nil_nil(player, sel("scheduleFile:atTime:completionHandler:"), file)
    end

    # startAndReturnError: → {Bool, NSError?}
    def self.start_returning_error(receiver : LibObjC::Id) : {Bool, LibObjC::Id?}
      err = Pointer(Void).null
      success = LibObjCHelpers.ca_msg_bool_err(receiver, sel("startAndReturnError:"), pointerof(err).as(Void**))
      {success, err.null? ? nil : err}
    end

    # no-arg → Float64
    def self.send_f64(receiver : LibObjC::Id, selector : String) : Float64
      LibObjCHelpers.ca_msg_f64(receiver, sel(selector))
    end

    # no-arg → Int64
    def self.send_i64(receiver : LibObjC::Id, selector : String) : Int64
      LibObjCHelpers.ca_msg_i64(receiver, sel(selector))
    end

    # double setter
    def self.set_f64(receiver : LibObjC::Id, selector : String, value : Float64)
      LibObjCHelpers.ca_msg_void_f64(receiver, sel(selector), value)
    end

    # NSUInteger setter (setPlaybackState:)
    def self.set_u64(receiver : LibObjC::Id, selector : String, value : UInt64)
      LibObjCHelpers.ca_msg_void_u64(receiver, sel(selector), value)
    end

    # detachNode:
    def self.detach(engine : LibObjC::Id, node : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id(engine, sel("detachNode:"), node)
    end

    # scheduleFile:atTime:completionHandler: (with time, handler = nil)
    def self.schedule_file_at_time(player : LibObjC::Id, file : LibObjC::Id, time : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id_id_nil(player, sel("scheduleFile:atTime:completionHandler:"), file, time)
    end

    # AVAudioPlayerNodeCompletionCallbackType values.
    #   DataConsumed   (0): data handed off to the renderer.
    #   DataRendered   (1): data fully rendered (fires under offline rendering).
    #   DataPlayedBack (2): data actually heard at the output; does NOT fire on
    #                       stop, and does NOT fire under offline manual rendering.
    PLAYER_COMPLETION_DATA_CONSUMED    = 0_u64
    PLAYER_COMPLETION_DATA_RENDERED    = 1_u64
    PLAYER_COMPLETION_DATA_PLAYED_BACK = 2_u64

    # scheduleFile:atTime:completionCallbackType:completionHandler: (atTime = nil).
    # `block` is an ObjC completion block built by LibBlockBridge; it must be
    # retained by the node (it is) and released by the caller after scheduling.
    def self.schedule_file_with_completion(player : LibObjC::Id, file : LibObjC::Id, callback_type : UInt64, block : LibObjC::Id)
      LibObjCHelpers.ca_schedule_file_with_completion(player, file, callback_type, block)
    end

    # ── Looping playback ──────────────────────────────────────────────────────

    # Read an AVAudioFile fully into a new AVAudioPCMBuffer. nil on error.
    def self.pcm_buffer_for_file(file : LibObjC::Id) : LibObjC::Id?
      buf = LibObjCHelpers.ca_pcm_buffer_for_file(file)
      buf.null? ? nil : buf
    end

    # Allocate an empty AVAudioPCMBuffer (offline-render destination). nil on error.
    def self.pcm_buffer_create(format : LibObjC::Id, frame_capacity : UInt32) : LibObjC::Id?
      buf = LibObjCHelpers.ca_pcm_buffer_create(format, frame_capacity)
      buf.null? ? nil : buf
    end

    # scheduleBuffer:atTime:options:completionHandler: with .loops — loops until stop.
    def self.schedule_buffer_loops(player : LibObjC::Id, buffer : LibObjC::Id)
      LibObjCHelpers.ca_schedule_buffer_loops(player, buffer)
    end

    # ── Offline (manual) rendering ────────────────────────────────────────────

    def self.engine_enable_manual_rendering(engine : LibObjC::Id, format : LibObjC::Id, max_frames : UInt32) : Bool
      LibObjCHelpers.ca_engine_enable_manual_rendering(engine, format, max_frames)
    end

    def self.engine_manual_rendering_format(engine : LibObjC::Id) : LibObjC::Id
      LibObjCHelpers.ca_engine_manual_rendering_format(engine)
    end

    # renderOffline:toBuffer:error: → status (0 = Success).
    def self.engine_render_offline(engine : LibObjC::Id, frames : UInt32, out_buffer : LibObjC::Id) : Int64
      LibObjCHelpers.ca_engine_render_offline(engine, frames, out_buffer)
    end

    # ── PCM buffer inspection ─────────────────────────────────────────────────

    def self.pcm_buffer_frame_length(buffer : LibObjC::Id) : UInt32
      LibObjCHelpers.ca_pcm_buffer_frame_length(buffer)
    end

    # RMS amplitude of channel 0 over [start_frame, start_frame+count).
    def self.pcm_buffer_rms(buffer : LibObjC::Id, start_frame : UInt32, count : UInt32) : Float64
      LibObjCHelpers.ca_pcm_buffer_rms(buffer, start_frame, count)
    end

    # ── Playback position / duration ──────────────────────────────────────────

    # AVAudioFormat.sampleRate (Hz). 0.0 on error.
    def self.format_sample_rate(format : LibObjC::Id) : Float64
      LibObjCHelpers.ca_format_sample_rate(format)
    end

    # AVAudioPlayerNode current position in sample frames; -1 before playback starts.
    def self.player_node_position_samples(node : LibObjC::Id) : Int64
      LibObjCHelpers.ca_player_node_position_samples(node)
    end

    # AVAudioFile: open for reading
    def self.audio_file_open(url : LibObjC::Id) : LibObjC::Id
      LibObjCHelpers.ca_audio_file_open(url)
    end

    # AVAudioTime helpers
    def self.audio_time_sample(sample_time : Int64, sample_rate : Float64) : LibObjC::Id
      LibObjCHelpers.ca_audio_time_sample(sample_time, sample_rate)
    end

    def self.audio_time_get_sample(time : LibObjC::Id) : Int64
      LibObjCHelpers.ca_audio_time_get_sample(time)
    end

    def self.audio_time_get_rate(time : LibObjC::Id) : Float64
      LibObjCHelpers.ca_audio_time_get_rate(time)
    end

    def self.audio_time_valid?(time : LibObjC::Id) : Bool
      LibObjCHelpers.ca_audio_time_valid(time)
    end

    # NSDictionary / NSNumber creation
    def self.nsdictionary_create(keys : Pointer(Void*), values : Pointer(Void*), count : UInt32) : LibObjC::Id
      LibObjCHelpers.ca_nsdictionary_create(keys, values, count)
    end

    def self.nsnumber_double(value : Float64) : LibObjC::Id
      LibObjCHelpers.ca_nsnumber_double(value)
    end

    def self.nsnumber_long(value : Int64) : LibObjC::Id
      LibObjCHelpers.ca_nsnumber_long(value)
    end
  end
end

{% end %}
