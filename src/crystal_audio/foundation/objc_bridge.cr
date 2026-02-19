{% if flag?(:darwin) %}

# ObjC runtime bridge for macOS/iOS.
# Provides typed wrappers around objc_msgSend for the argument patterns
# used in audio APIs. Each variant corresponds to a unique ARM64 register layout.
#
# Background: On ARM64, objc_msgSend is an assembly trampoline. Calling it
# with incorrect argument types routes values to wrong registers and causes
# crashes or silent corruption. Every unique signature needs its own cast.

@[Link(framework: "Foundation")]
lib LibObjC
  alias Id  = Void*
  alias Sel = Void*
  alias Cls = Void*

  # ── Core runtime ────────────────────────────────────────────────────────────

  fun objc_msgSend(receiver : Id, sel : Sel, ...) : Id
  fun objc_getClass(name : LibC::Char*) : Cls
  fun sel_registerName(name : LibC::Char*) : Sel
  fun object_getClass(obj : Id) : Cls

  # Alloc/init helper (common pattern: class alloc → init)
  fun objc_alloc = objc_alloc(cls : Cls) : Id

  # ── Class/object creation helpers ───────────────────────────────────────────

  fun objc_allocateClassPair(
    superclass : Cls,
    name       : LibC::Char*,
    extra_bytes : LibC::SizeT
  ) : Cls

  fun objc_registerClassPair(cls : Cls)

  fun class_addMethod(
    cls   : Cls,
    name  : Sel,
    imp   : Void*,
    types : LibC::Char*
  ) : Bool
end

module CrystalAudio
  module ObjC
    # Convenience: get a class by name
    def self.cls(name : String) : LibObjC::Cls
      LibObjC.objc_getClass(name.to_unsafe)
    end

    # Convenience: register a selector
    def self.sel(name : String) : LibObjC::Sel
      LibObjC.sel_registerName(name.to_unsafe)
    end

    # Allocate and initialize an ObjC object: [[ClassName alloc] init]
    def self.alloc_init(class_name : String) : LibObjC::Id
      klass = cls(class_name)
      obj = LibObjC.objc_alloc(klass)
      LibObjC.objc_msgSend(obj, sel("init"))
    end

    # Send a message with no arguments, returning an Id
    def self.send(receiver : LibObjC::Id, selector : String) : LibObjC::Id
      LibObjC.objc_msgSend(receiver, sel(selector))
    end

    # Send a message with one Id argument
    def self.send(receiver : LibObjC::Id, selector : String, arg : LibObjC::Id) : LibObjC::Id
      fun = Proc(LibObjC::Id, LibObjC::Sel, LibObjC::Id, LibObjC::Id).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(receiver, sel(selector), arg)
    end

    # Send a message returning a Bool (BOOL in ObjC)
    def self.send_bool(receiver : LibObjC::Id, selector : String) : Bool
      fun = Proc(LibObjC::Id, LibObjC::Sel, Bool).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(receiver, sel(selector))
    end

    # Send a message returning a Float64 (for sample rate, duration, etc.)
    def self.send_f64(receiver : LibObjC::Id, selector : String) : Float64
      fun = Proc(LibObjC::Id, LibObjC::Sel, Float64).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(receiver, sel(selector))
    end

    # Set a Float32 property (e.g., volume, pan)
    def self.set_f32(receiver : LibObjC::Id, selector : String, value : Float32)
      fun = Proc(LibObjC::Id, LibObjC::Sel, Float32, Void).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(receiver, sel(selector), value)
    end

    # Send startAndReturnError: — returns Bool, takes NSError** out-parameter
    def self.start_returning_error(receiver : LibObjC::Id) : {Bool, LibObjC::Id?}
      err_ptr = Pointer(LibObjC::Id).malloc(1)
      err_ptr.value = Pointer(Void).null
      fun = Proc(LibObjC::Id, LibObjC::Sel, Pointer(LibObjC::Id), Bool).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      success = fun.call(receiver, sel("startAndReturnError:"), err_ptr)
      err = err_ptr.value.null? ? nil : err_ptr.value
      err_ptr.free
      {success, err}
    end
  end
end

{% end %}
