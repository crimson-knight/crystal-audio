{% if flag?(:android) %}

# Android NowPlayingInfo — stub that logs metadata.
#
# On Android, now playing info is managed by the Kotlin MediaPlaybackService
# via the MediaSession API. This Crystal class stores the metadata and could
# call back to Java via JNI to update the session, but for now the Kotlin
# service manages its own state.

module CrystalAudio
  class NowPlayingInfo
    # Mirrors MPNowPlayingPlaybackState so callers share one vocabulary across
    # platforms (Android maps these onto its MediaSession state in Kotlin).
    enum PlaybackState : UInt64
      Unknown     = 0
      Playing     = 1
      Paused      = 2
      Stopped     = 3
      Interrupted = 4
    end

    def initialize
    end

    def update(
      title : String? = nil,
      artist : String? = nil,
      album : String? = nil,
      duration : Float64 = 0.0,
      elapsed : Float64 = 0.0,
      rate : Float64 = 1.0,
      artwork_path : String? = nil
    )
      # On Android, metadata is pushed from the Kotlin MediaPlaybackService.
      # This could call JNI to update, but the service handles it directly.
      # artwork_path is a no-op here (the MediaSession carries its own artwork).
    end

    # No-op on Android (the MediaSession owns playback state in Kotlin).
    def playback_state=(state : PlaybackState)
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
    # MPNowPlayingPlaybackState values. On iOS, when this app is the now-playing
    # app, the lock-screen play/pause GLYPH is driven by
    # MPNowPlayingInfoCenter.playbackState — NOT by the info dict's playbackRate
    # (the rate drives the scrubber). Without setting this, iOS can keep showing
    # the "playing" glyph after a pause (the B2.3 stale-state bug).
    enum PlaybackState : UInt64
      Unknown     = 0
      Playing     = 1
      Paused      = 2
      Stopped     = 3
      Interrupted = 4
    end

    # MPNowPlayingInfoCenter singleton
    @center : LibObjC::Id

    # Cached MPMediaItemArtwork* and the path it was built from. Lock-screen
    # updates fire every second while playing, so we rebuild the (relatively
    # expensive) artwork ONLY when the path changes — otherwise we reuse the
    # cached object. nil path ⇒ no artwork cached.
    @artwork : Void*
    @artwork_path : String?

    def initialize
      @center = ObjC.send(
        LibObjC.objc_getClass("MPNowPlayingInfoCenter").as(LibObjC::Id),
        "defaultCenter"
      )
      raise "Failed to get MPNowPlayingInfoCenter" if @center.null?
      @artwork = Pointer(Void).null
      @artwork_path = nil
    end

    # Update the Now Playing info displayed on lock screen / Control Center.
    #
    # artwork_path: absolute path to an image file (e.g. the app logo). The
    # built MPMediaItemArtwork is cached and only rebuilt when the path changes,
    # so per-second elapsed-time updates do NOT reload the image.
    def update(
      title : String? = nil,
      artist : String? = nil,
      album : String? = nil,
      duration : Float64 = 0.0,
      elapsed : Float64 = 0.0,
      rate : Float64 = 1.0,
      artwork_path : String? = nil
    )
      artwork = resolve_artwork(artwork_path)

      keys = Array(Void*).new(7)
      values = Array(Void*).new(7)

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

      unless artwork.null?
        keys << property_key("MPMediaItemPropertyArtwork")
        values << artwork
      end

      return if keys.empty?

      dict = ObjC.nsdictionary_create(
        keys.to_unsafe.as(Void**),
        values.to_unsafe.as(Void**),
        keys.size.to_u32
      )
      ObjC.send_void(@center, "setNowPlayingInfo:", dict)
    end

    # Return the cached MPMediaItemArtwork* for `path`, rebuilding only when the
    # path changed since the last call. Returns a null pointer when no path is
    # given (or the image fails to load) so the caller simply omits the artwork
    # key. The previous artwork is released when the path changes so its image is
    # freed (per-second updates with an unchanged path do no allocation).
    private def resolve_artwork(path : String?) : Void*
      return @artwork if path == @artwork_path

      # Path changed (including to nil): drop the old artwork + its image.
      unless @artwork.null?
        LibBlockBridge.ca_artwork_release(@artwork)
        @artwork = Pointer(Void).null
      end
      @artwork_path = path

      if p = path
        built = LibBlockBridge.ca_make_artwork(p.to_unsafe)
        @artwork = built unless built.null?
      end
      @artwork
    end

    # Set MPNowPlayingInfoCenter.playbackState so iOS picks the correct
    # lock-screen glyph (play vs pause). Call alongside update(rate:) — rate
    # drives the scrubber; playbackState drives the glyph on iOS.
    def playback_state=(state : PlaybackState)
      ObjC.set_u64(@center, "setPlaybackState:", state.value)
    end

    # Clear the Now Playing info.
    def clear
      self.playback_state = PlaybackState::Stopped
      # setNowPlayingInfo:nil
      LibObjCHelpers.ca_msg_void_id(
        @center,
        LibObjC.sel_registerName("setNowPlayingInfo:"),
        Pointer(Void).null
      )
      # Release the cached artwork (and its image) so a new session rebuilds it.
      unless @artwork.null?
        LibBlockBridge.ca_artwork_release(@artwork)
        @artwork = Pointer(Void).null
      end
      @artwork_path = nil
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
