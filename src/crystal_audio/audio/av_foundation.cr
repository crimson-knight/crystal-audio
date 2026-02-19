{% if flag?(:darwin) %}

# AVFoundation bindings: AVAudioEngine, AVAudioPlayerNode, AVAudioMixerNode.
#
# Most methods are plain ObjC message sends (no blocks). The one exception is
# installTapOnBus:bufferSize:format:block: which uses the block bridge.
# See audio/block_bridge.cr for that factory.
#
# ARM64 note: each unique objc_msgSend signature needs a typed C cast.
# The ObjC bridge helpers in foundation/objc_bridge.cr cover common patterns.

@[Link(framework: "AVFoundation")]
lib LibAVFoundation
  # Opaque pointers — we interact entirely via objc_msgSend
  alias AVAudioEngineRef      = Void*
  alias AVAudioNodeRef        = Void*
  alias AVAudioInputNodeRef   = Void*
  alias AVAudioPlayerNodeRef  = Void*
  alias AVAudioMixerNodeRef   = Void*
  alias AVAudioFormatRef      = Void*
  alias AVAudioPCMBufferRef   = Void*
  alias AVAudioTimeRef        = Void*
  alias AVAudioFileRef        = Void*
end

module CrystalAudio
  # Thin wrapper around AVAudioEngine. All interaction via ObjC runtime.
  class AudioEngine
    getter ptr : LibObjC::Id

    def initialize
      @ptr = ObjC.alloc_init("AVAudioEngine")
      raise "Failed to create AVAudioEngine" if @ptr.null?
    end

    def input_node : LibObjC::Id
      ObjC.send(@ptr, "inputNode")
    end

    def output_node : LibObjC::Id
      ObjC.send(@ptr, "outputNode")
    end

    def main_mixer_node : LibObjC::Id
      ObjC.send(@ptr, "mainMixerNode")
    end

    def attach(node : LibObjC::Id)
      fun = Proc(LibObjC::Id, LibObjC::Sel, LibObjC::Id, Void).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(@ptr, ObjC.sel("attachNode:"), node)
    end

    # connect node_a output bus 0 → node_b input bus 0 with nil format (auto)
    def connect(from : LibObjC::Id, to : LibObjC::Id, format : LibObjC::Id = Pointer(Void).null)
      fun = Proc(LibObjC::Id, LibObjC::Sel, LibObjC::Id, LibObjC::Id, LibObjC::Id, Void).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(@ptr, ObjC.sel("connect:to:format:"), from, to, format)
    end

    def prepare
      ObjC.send(@ptr, "prepare")
    end

    def start : Bool
      success, _err = ObjC.start_returning_error(@ptr)
      success
    end

    def pause
      ObjC.send(@ptr, "pause")
    end

    def stop
      ObjC.send(@ptr, "stop")
    end

    def running? : Bool
      ObjC.send_bool(@ptr, "isRunning")
    end
  end

  # Wrapper around AVAudioPlayerNode for multi-track playback.
  class AudioPlayerNode
    getter ptr : LibObjC::Id

    def initialize
      @ptr = ObjC.alloc_init("AVAudioPlayerNode")
      raise "Failed to create AVAudioPlayerNode" if @ptr.null?
    end

    def play
      ObjC.send(@ptr, "play")
    end

    def pause
      ObjC.send(@ptr, "pause")
    end

    def stop
      ObjC.send(@ptr, "stop")
    end

    def playing? : Bool
      ObjC.send_bool(@ptr, "isPlaying")
    end

    # Volume: 0.0 (silent) to 1.0 (full). Uses AVAudioMixing protocol.
    def volume=(value : Float32)
      ObjC.set_f32(@ptr, "setVolume:", value)
    end

    def volume : Float32
      fun = Proc(LibObjC::Id, LibObjC::Sel, Float32).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(@ptr, ObjC.sel("volume"))
    end

    # Schedule an audio file for playback (completion handler = nil, plays immediately).
    def schedule_file(file : LibObjC::Id)
      fun = Proc(LibObjC::Id, LibObjC::Sel, LibObjC::Id, LibObjC::Id, LibObjC::Id, Void).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(
        @ptr,
        ObjC.sel("scheduleFile:atTime:completionHandler:"),
        file,
        Pointer(Void).null,  # atTime: nil = immediate
        Pointer(Void).null   # completionHandler: nil
      )
    end
  end

  # Wrapper around AVAudioMixerNode (master volume + routing hub).
  class AudioMixerNode
    getter ptr : LibObjC::Id

    # Use engine.main_mixer_node instead of creating a new one
    def initialize(@ptr : LibObjC::Id)
    end

    # Master output volume: 0.0–1.0
    def output_volume=(value : Float32)
      ObjC.set_f32(@ptr, "setOutputVolume:", value)
    end

    def output_volume : Float32
      fun = Proc(LibObjC::Id, LibObjC::Sel, Float32).new(
        LibObjC.objc_msgSend.pointer, Pointer(Void).null
      )
      fun.call(@ptr, ObjC.sel("outputVolume"))
    end
  end
end

{% end %}
