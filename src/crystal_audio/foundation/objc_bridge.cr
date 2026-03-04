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

  # AVAudioFile: [[AVAudioFile alloc] initForReading:url error:&err]
  fun ca_audio_file_open(url : Void*) : Void*

  # AVAudioTime helpers
  fun ca_audio_time_sample(sample_time : Int64, sample_rate : Float64) : Void*
  fun ca_audio_time_get_sample(time : Void*) : Int64
  fun ca_audio_time_get_rate(time : Void*) : Float64
  fun ca_audio_time_valid(time : Void*) : Bool

  # scheduleFile:atTime:completionHandler: with time (handler = nil)
  fun ca_msg_void_id_id_nil(obj : Void*, sel : Void*, a1 : Void*, a2 : Void*)

  # NSDictionary / NSNumber helpers
  fun ca_nsdictionary_create(keys : Void**, values : Void**, count : UInt32) : Void*
  fun ca_nsnumber_double(value : Float64) : Void*
  fun ca_nsnumber_long(value : Int64) : Void*

  # [[ClassName alloc] init]
  fun ca_alloc_init(class_name : LibC::Char*) : Void*
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

    # detachNode:
    def self.detach(engine : LibObjC::Id, node : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id(engine, sel("detachNode:"), node)
    end

    # scheduleFile:atTime:completionHandler: (with time, handler = nil)
    def self.schedule_file_at_time(player : LibObjC::Id, file : LibObjC::Id, time : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id_id_nil(player, sel("scheduleFile:atTime:completionHandler:"), file, time)
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
