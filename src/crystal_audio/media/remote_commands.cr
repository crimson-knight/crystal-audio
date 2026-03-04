{% if flag?(:android) %}

# Android RemoteCommandCenter — receives media session events via JNI.
#
# On Android, media controls come through the MediaSession → JNI → Crystal path.
# The JNI bridge calls crystal_on_media_play/pause/etc. which dispatch to
# user-registered callbacks here.
#
# Usage is identical to the Darwin version:
#   rc = CrystalAudio::RemoteCommandCenter.new
#   rc.on_play { puts "Play" }
#   rc.on_pause { puts "Pause" }

module CrystalAudio
  class RemoteCommandCenter
    @@on_play : Proc(Nil)?
    @@on_pause : Proc(Nil)?
    @@on_toggle : Proc(Nil)?
    @@on_next : Proc(Nil)?
    @@on_previous : Proc(Nil)?

    def initialize
    end

    def on_play(&block : ->)
      @@on_play = block
    end

    def on_pause(&block : ->)
      @@on_pause = block
    end

    def on_toggle_play_pause(&block : ->)
      @@on_toggle = block
    end

    def on_next(&block : ->)
      @@on_next = block
    end

    def on_previous(&block : ->)
      @@on_previous = block
    end

    def enable
      # On Android, commands are always enabled via the MediaSession.
      # Nothing to do here — callbacks are dispatched from JNI.
    end

    def disable
      @@on_play = nil
      @@on_pause = nil
      @@on_toggle = nil
      @@on_next = nil
      @@on_previous = nil
    end

    # --- Static dispatch (called from JNI bridge C functions) ---

    def self.dispatch_play
      @@on_play.try(&.call)
    end

    def self.dispatch_pause
      @@on_pause.try(&.call)
    end

    def self.dispatch_toggle
      @@on_toggle.try(&.call)
    end

    def self.dispatch_next
      @@on_next.try(&.call)
    end

    def self.dispatch_previous
      @@on_previous.try(&.call)
    end
  end
end

{% elsif flag?(:darwin) %}

# RemoteCommandCenter — handles lock screen transport controls (play/pause/skip).
#
# Wraps MPRemoteCommandCenter and uses block_bridge's MpHandlerFn type to
# register Crystal callbacks for each transport command.
#
# Example:
#   rc = CrystalAudio::RemoteCommandCenter.new
#   rc.on_play { puts "Play pressed" }
#   rc.on_pause { puts "Pause pressed" }
#   rc.on_next { puts "Next pressed" }
#   rc.on_previous { puts "Previous pressed" }
#   rc.enable

module CrystalAudio
  class RemoteCommandCenter
    # MPRemoteCommandHandlerStatus values
    SUCCESS         = 0_i64
    NO_SUCH_CONTENT = 1_i64
    COMMAND_FAILED  = 100_i64

    @center : LibObjC::Id

    # Store boxed callbacks as class-level GC roots to prevent collection
    @@play_box : Pointer(Void)?
    @@pause_box : Pointer(Void)?
    @@toggle_box : Pointer(Void)?
    @@next_box : Pointer(Void)?
    @@previous_box : Pointer(Void)?
    @@seek_box : Pointer(Void)?

    # User-provided callbacks
    @@on_play : Proc(Nil)?
    @@on_pause : Proc(Nil)?
    @@on_toggle : Proc(Nil)?
    @@on_next : Proc(Nil)?
    @@on_previous : Proc(Nil)?
    @@on_seek : Proc(Float64, Nil)?

    def initialize
      @center = ObjC.send(
        LibObjC.objc_getClass("MPRemoteCommandCenter").as(LibObjC::Id),
        "sharedCommandCenter"
      )
      raise "Failed to get MPRemoteCommandCenter" if @center.null?
    end

    def on_play(&block : ->)
      @@on_play = block
      register_command("playCommand", ->RemoteCommandCenter.dispatch_play)
    end

    def on_pause(&block : ->)
      @@on_pause = block
      register_command("pauseCommand", ->RemoteCommandCenter.dispatch_pause)
    end

    def on_toggle_play_pause(&block : ->)
      @@on_toggle = block
      register_command("togglePlayPauseCommand", ->RemoteCommandCenter.dispatch_toggle)
    end

    def on_next(&block : ->)
      @@on_next = block
      register_command("nextTrackCommand", ->RemoteCommandCenter.dispatch_next)
    end

    def on_previous(&block : ->)
      @@on_previous = block
      register_command("previousTrackCommand", ->RemoteCommandCenter.dispatch_previous)
    end

    # Enable all registered commands (disable unregistered ones).
    def enable
      disable_unregistered
    end

    # Disable all commands.
    def disable
      {% for cmd in %w[playCommand pauseCommand togglePlayPauseCommand nextTrackCommand previousTrackCommand] %}
        command = ObjC.send(@center, {{cmd}})
        ObjC.send_void(command, "setEnabled:", Pointer(Void).new(0_u64))
      {% end %}
    end

    # --- Static dispatch trampolines (called from C block bridge) ---

    protected def self.dispatch_play : Int64
      @@on_play.try(&.call)
      SUCCESS
    end

    protected def self.dispatch_pause : Int64
      @@on_pause.try(&.call)
      SUCCESS
    end

    protected def self.dispatch_toggle : Int64
      @@on_toggle.try(&.call)
      SUCCESS
    end

    protected def self.dispatch_next : Int64
      @@on_next.try(&.call)
      SUCCESS
    end

    protected def self.dispatch_previous : Int64
      @@on_previous.try(&.call)
      SUCCESS
    end

    # --- Private ---

    private def register_command(command_name : String, handler : Proc(Int64))
      command = ObjC.send(@center, command_name)

      # Box the handler proc so GC tracks it
      box = Box.box(handler)

      # C trampoline: receives (ctx, event) -> Int64
      trampoline = LibBlockBridge::MpHandlerFn.new do |ctx, _event|
        cb = Box(Proc(Int64)).unbox(ctx)
        cb.call
      end

      # Create ObjC block and register it
      block = LibBlockBridge.crystal_mp_handler_block_create(trampoline, box)
      ObjC.send(command, "addTargetWithHandler:", block)
      LibBlockBridge.crystal_block_release(block)

      # Enable the command
      LibObjCHelpers.ca_msg_void_id(
        command,
        LibObjC.sel_registerName("setEnabled:"),
        Pointer(Void).new(1_u64)
      )
    end

    private def disable_unregistered
      commands = {
        "playCommand"             => @@on_play,
        "pauseCommand"            => @@on_pause,
        "togglePlayPauseCommand"  => @@on_toggle,
        "nextTrackCommand"        => @@on_next,
        "previousTrackCommand"    => @@on_previous,
      }

      commands.each do |name, callback|
        next if callback # already enabled via register_command
        command = ObjC.send(@center, name)
        LibObjCHelpers.ca_msg_void_id(
          command,
          LibObjC.sel_registerName("setEnabled:"),
          Pointer(Void).new(0_u64)
        )
      end
    end
  end
end

{% end %}
