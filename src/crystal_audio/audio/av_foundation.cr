{% if flag?(:darwin) %}

# AVFoundation bindings: AVAudioEngine, AVAudioPlayerNode, AVAudioMixerNode.
#
# All interaction via the typed objc_msgSend aliases in foundation/objc_bridge.cr.
# No Proc gymnastics — just direct variadic C calls.

@[Link(framework: "AVFoundation")]
lib LibAVFoundation
  # Opaque pointers — we interact entirely via objc_msgSend
  alias AVAudioEngineRef     = Void*
  alias AVAudioNodeRef       = Void*
  alias AVAudioPlayerNodeRef = Void*
  alias AVAudioMixerNodeRef  = Void*
  alias AVAudioFormatRef     = Void*
  alias AVAudioPCMBufferRef  = Void*
  alias AVAudioTimeRef       = Void*
  alias AVAudioFileRef       = Void*
end

module CrystalAudio
  # Thin wrapper around AVAudioEngine.
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
      ObjC.attach(@ptr, node)
    end

    def connect(from : LibObjC::Id, to : LibObjC::Id, format : LibObjC::Id = Pointer(Void).null)
      ObjC.connect(@ptr, from, to, format)
    end

    def prepare
      ObjC.send_void(@ptr, "prepare")
    end

    def start : Bool
      success, _err = ObjC.start_returning_error(@ptr)
      success
    end

    def pause
      ObjC.send_void(@ptr, "pause")
    end

    def stop
      ObjC.send_void(@ptr, "stop")
    end

    def running? : Bool
      ObjC.send_bool(@ptr, "isRunning")
    end

    # ── Offline (manual) rendering ────────────────────────────────────────────
    # Switch the engine to deterministic offline rendering (no audio device).
    # Call while the engine is stopped, BEFORE start. Returns true on success.
    def enable_manual_rendering(format : LibObjC::Id, max_frames : UInt32) : Bool
      ObjC.engine_enable_manual_rendering(@ptr, format, max_frames)
    end

    # The PCM format the engine renders in manual mode (set by enable_manual_rendering).
    def manual_rendering_format : LibObjC::Id
      ObjC.engine_manual_rendering_format(@ptr)
    end

    # Render up to `frames` frames into out_buffer. Returns the status (0 = Success);
    # out_buffer.frameLength is set to the number of frames actually produced.
    def render_offline(frames : UInt32, out_buffer : LibObjC::Id) : Int64
      ObjC.engine_render_offline(@ptr, frames, out_buffer)
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
      ObjC.send_void(@ptr, "play")
    end

    def pause
      ObjC.send_void(@ptr, "pause")
    end

    def stop
      ObjC.send_void(@ptr, "stop")
    end

    def playing? : Bool
      ObjC.send_bool(@ptr, "isPlaying")
    end

    # Volume: 0.0 (silent) to 1.0 (full). Uses AVAudioMixing protocol.
    def volume=(value : Float32)
      ObjC.set_f32(@ptr, "setVolume:", value)
    end

    def volume : Float32
      ObjC.send_f32(@ptr, "volume")
    end

    # Schedule a file for playback (plays immediately, no completion callback).
    def schedule_file(file : LibObjC::Id)
      ObjC.schedule_file(@ptr, file)
    end

    # Schedule a file at a specific AVAudioTime (no completion callback).
    def schedule_file_at_time(file : LibObjC::Id, time : LibObjC::Id)
      ObjC.schedule_file_at_time(@ptr, file, time)
    end

    # Schedule a PCM buffer that loops indefinitely until the node is stopped
    # (scheduleBuffer:options:AVAudioPlayerNodeBufferLoops).
    def schedule_buffer_looping(buffer : LibObjC::Id)
      ObjC.schedule_buffer_loops(@ptr, buffer)
    end

    # Play starting at a specific AVAudioTime (for synchronized multi-track start).
    def play_at_time(time : LibObjC::Id)
      LibObjCHelpers.ca_msg_void_id(@ptr, LibObjC.sel_registerName("playAtTime:"), time)
    end

    # Get last render time (AVAudioTime). May be nil if node hasn't rendered yet.
    def last_render_time : LibObjC::Id?
      time = ObjC.send(@ptr, "lastRenderTime")
      time.null? ? nil : time
    end

    # Current playback position in sample frames; -1 before rendering starts.
    def position_samples : Int64
      ObjC.player_node_position_samples(@ptr)
    end
  end

  # Wrapper around AVAudioFile for reading audio files.
  class AVAudioFile
    getter ptr : LibObjC::Id

    # Open an audio file for reading. Raises on error.
    def initialize(path : String)
      url = CF.file_url(path)
      @ptr = ObjC.audio_file_open(url)
      LibCoreFoundation.CFRelease(url)
      raise "Failed to open AVAudioFile: #{path}" if @ptr.null?
    end

    # Returns the file's processing format (AVAudioFormat).
    def processing_format : LibObjC::Id
      ObjC.send(@ptr, "processingFormat")
    end

    # File length in sample frames.
    def length : Int64
      ObjC.send_i64(@ptr, "length")
    end

    # Read the whole file into a new AVAudioPCMBuffer (for looping playback). nil on error.
    def pcm_buffer : LibObjC::Id?
      ObjC.pcm_buffer_for_file(@ptr)
    end

    # Sample rate of the file's processing format (Hz).
    def sample_rate : Float64
      ObjC.format_sample_rate(processing_format)
    end

    # Duration in seconds (frames / sample rate). 0.0 if the rate is unknown.
    def duration_seconds : Float64
      rate = sample_rate
      rate > 0.0 ? length.to_f / rate : 0.0
    end
  end

  # Wrapper around AVAudioMixerNode (master volume + routing hub).
  class AudioMixerNode
    getter ptr : LibObjC::Id

    # Typically obtained from engine.main_mixer_node rather than allocated fresh.
    def initialize(@ptr : LibObjC::Id)
    end

    def output_volume=(value : Float32)
      ObjC.set_f32(@ptr, "setOutputVolume:", value)
    end

    def output_volume : Float32
      ObjC.send_f32(@ptr, "outputVolume")
    end
  end
end

{% end %}
