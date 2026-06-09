{% if flag?(:darwin) %}

# CoreFoundation bindings for macOS/iOS.
# Provides CFString, CFURL, and CFRunLoop — used by audio APIs for file paths
# and run loop management.

@[Link(framework: "CoreFoundation")]
lib LibCoreFoundation
  alias CFAllocatorRef  = Void*
  alias CFStringRef     = Void*
  alias CFURLRef        = Void*
  alias CFRunLoopRef    = Void*
  alias CFTypeRef       = Void*
  alias CFIndex         = Int64
  alias CFOptionFlags   = UInt64

  # String encodings
  CF_STRING_ENCODING_UTF8 = 0x08000100_u32

  # URL path styles
  CF_URL_POSIX_PATH_STYLE = 0_i32

  # ── CFString ────────────────────────────────────────────────────────────────

  fun CFStringCreateWithCString(
    alloc    : CFAllocatorRef,
    c_str    : LibC::Char*,
    encoding : UInt32
  ) : CFStringRef

  fun CFStringGetCStringPtr(
    str      : CFStringRef,
    encoding : UInt32
  ) : LibC::Char*

  fun CFStringGetLength(str : CFStringRef) : CFIndex

  # ── CFURL ───────────────────────────────────────────────────────────────────

  fun CFURLCreateWithFileSystemPath(
    allocator    : CFAllocatorRef,
    file_path    : CFStringRef,
    path_style   : Int32,
    is_directory : Bool
  ) : CFURLRef

  # ── CFRunLoop ───────────────────────────────────────────────────────────────

  fun CFRunLoopGetCurrent : CFRunLoopRef
  fun CFRunLoopGetMain    : CFRunLoopRef
  fun CFRunLoopRun
  fun CFRunLoopStop(rl : CFRunLoopRef)

  # Run the run loop in a given mode for up to `seconds`; returns when a source
  # is handled (if return_after_source_handled) or the timeout elapses. Used to
  # service main-queue dispatch_async work (e.g. audio completion callbacks).
  fun CFRunLoopRunInMode(
    mode                       : CFStringRef,
    seconds                    : Float64,
    return_after_source_handled : Bool
  ) : Int32

  # The default run loop mode (a CFStringRef global exported by CoreFoundation).
  $kCFRunLoopDefaultMode : CFStringRef

  # ── Memory management ───────────────────────────────────────────────────────

  fun CFRelease(cf : CFTypeRef)
  fun CFRetain(cf : CFTypeRef) : CFTypeRef
end

module CrystalAudio
  module CF
    # Convert a Crystal String to a CFStringRef. Caller must CFRelease when done.
    def self.string(s : String) : LibCoreFoundation::CFStringRef
      LibCoreFoundation.CFStringCreateWithCString(
        nil,
        s.to_unsafe,
        LibCoreFoundation::CF_STRING_ENCODING_UTF8
      )
    end

    # Convert a file path String to a CFURLRef. Caller must CFRelease when done.
    def self.file_url(path : String) : LibCoreFoundation::CFURLRef
      cf_str = string(path)
      url = LibCoreFoundation.CFURLCreateWithFileSystemPath(
        nil,
        cf_str,
        LibCoreFoundation::CF_URL_POSIX_PATH_STYLE,
        false
      )
      LibCoreFoundation.CFRelease(cf_str)
      url
    end

    # The default CFRunLoop mode (kCFRunLoopDefaultMode).
    def self.default_run_loop_mode : LibCoreFoundation::CFStringRef
      LibCoreFoundation.kCFRunLoopDefaultMode
    end
  end
end

{% end %}
