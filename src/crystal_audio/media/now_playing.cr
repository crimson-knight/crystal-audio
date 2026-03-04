{% if flag?(:android) %}

# Android NowPlayingInfo — stub that logs metadata.
#
# On Android, now playing info is managed by the Kotlin MediaPlaybackService
# via the MediaSession API. This Crystal class stores the metadata and could
# call back to Java via JNI to update the session, but for now the Kotlin
# service manages its own state.

module CrystalAudio
  class NowPlayingInfo
    def initialize
    end

    def update(
      title : String? = nil,
      artist : String? = nil,
      album : String? = nil,
      duration : Float64 = 0.0,
      elapsed : Float64 = 0.0,
      rate : Float64 = 1.0
    )
      # On Android, metadata is pushed from the Kotlin MediaPlaybackService.
      # This could call JNI to update, but the service handles it directly.
    end

    def clear
    end
  end
end

{% elsif flag?(:darwin) %}

# NowPlayingInfo — wraps MPNowPlayingInfoCenter for lock screen metadata.
#
# Updates the system Now Playing info (Control Center, lock screen, AirPlay).
# Requires linking with -framework MediaPlayer.
#
# Example:
#   info = CrystalAudio::NowPlayingInfo.new
#   info.update(title: "My Song", artist: "Artist", duration: 180.0, elapsed: 45.0, rate: 1.0)
#   info.clear

@[Link(framework: "MediaPlayer")]
lib LibMediaPlayer
  # We access MPNowPlayingInfoCenter and MPMediaItemProperty* constants
  # via the ObjC runtime, not direct symbol references, since they're
  # NSString* constants loaded at runtime.
end

module CrystalAudio
  class NowPlayingInfo
    # MPNowPlayingInfoCenter singleton
    @center : LibObjC::Id

    def initialize
      @center = ObjC.send(
        LibObjC.objc_getClass("MPNowPlayingInfoCenter").as(LibObjC::Id),
        "defaultCenter"
      )
      raise "Failed to get MPNowPlayingInfoCenter" if @center.null?
    end

    # Update the Now Playing info displayed on lock screen / Control Center.
    def update(
      title : String? = nil,
      artist : String? = nil,
      album : String? = nil,
      duration : Float64 = 0.0,
      elapsed : Float64 = 0.0,
      rate : Float64 = 1.0
    )
      keys = Array(Void*).new(6)
      values = Array(Void*).new(6)

      if t = title
        keys << property_key("MPMediaItemPropertyTitle")
        values << CF.string(t).as(Void*)
      end

      if a = artist
        keys << property_key("MPMediaItemPropertyArtist")
        values << CF.string(a).as(Void*)
      end

      if al = album
        keys << property_key("MPMediaItemPropertyAlbumTitle")
        values << CF.string(al).as(Void*)
      end

      if duration > 0.0
        keys << property_key("MPMediaItemPropertyPlaybackDuration")
        values << ObjC.nsnumber_double(duration)
      end

      keys << property_key("MPNowPlayingInfoPropertyElapsedPlaybackTime")
      values << ObjC.nsnumber_double(elapsed)

      keys << property_key("MPNowPlayingInfoPropertyPlaybackRate")
      values << ObjC.nsnumber_double(rate)

      return if keys.empty?

      dict = ObjC.nsdictionary_create(
        keys.to_unsafe.as(Void**),
        values.to_unsafe.as(Void**),
        keys.size.to_u32
      )
      ObjC.send_void(@center, "setNowPlayingInfo:", dict)
    end

    # Clear the Now Playing info.
    def clear
      # setNowPlayingInfo:nil
      LibObjCHelpers.ca_msg_void_id(
        @center,
        LibObjC.sel_registerName("setNowPlayingInfo:"),
        Pointer(Void).null
      )
    end

    # Look up an NSString* property key constant by name.
    # MediaPlayer framework exports these as global NSString* variables.
    private def property_key(name : String) : Void*
      # These are extern NSString* symbols exported by MediaPlayer.framework
      # Access them via dlsym at runtime.
      handle = LibC.dlopen(nil, 0)
      ptr = LibC.dlsym(handle, name.to_unsafe)
      if ptr.null?
        # Fallback: create an NSString from the constant name itself
        CF.string(name).as(Void*)
      else
        # ptr is a pointer to the NSString* global — dereference it
        ptr.as(Void**).value
      end
    end
  end
end

lib LibC
  fun dlopen(path : LibC::Char*, mode : Int32) : Void*
  fun dlsym(handle : Void*, symbol : LibC::Char*) : Void*
end

{% end %}
