{% if flag?(:darwin) %}

# Multi-track audio player.
#
# Layers multiple audio tracks for simultaneous playback with:
#   - Per-track volume control
#   - Master volume control
#   - Synchronized play/pause/stop across all tracks
#   - Forward/backward track navigation per layer
#
# Status: STUB — structure defined, implementation in progress.
#         Depends on block_bridge for AVAudioPlayerNode.scheduleFile completion.
#
# Example:
#   player = CrystalAudio::Player.new
#   player.add_track("/music/drums.wav")
#   player.add_track("/music/bass.wav")
#   player.volume(track: 1, level: 0.8)
#   player.master_volume = 0.9
#   player.play
#   sleep 30.seconds
#   player.stop

module CrystalAudio
  class Player
    MAX_TRACKS = 16

    getter master_volume : Float32
    getter? playing : Bool

    @engine  : AudioEngine
    @mixer   : AudioMixerNode
    @tracks  : Array(Track)

    struct Track
      getter path    : String
      getter node    : AudioPlayerNode
      getter volume  : Float32

      def initialize(@path, @node, @volume = 1.0_f32)
      end
    end

    def initialize
      @engine = AudioEngine.new
      @mixer = AudioMixerNode.new(@engine.main_mixer_node)
      @tracks = Array(Track).new(MAX_TRACKS)
      @master_volume = 1.0_f32
      @playing = false
    end

    # Add a track. Returns the track index.
    def add_track(path : String, volume : Float32 = 1.0_f32) : Int32
      raise "Maximum #{MAX_TRACKS} tracks" if @tracks.size >= MAX_TRACKS
      raise "File not found: #{path}" unless File.exists?(path)

      node = AudioPlayerNode.new
      node.volume = volume
      @engine.attach(node.ptr)
      @engine.connect(node.ptr, @engine.main_mixer_node)

      @tracks << Track.new(path, node, volume)
      @tracks.size - 1
    end

    def remove_track(index : Int32)
      raise IndexError.new("Invalid track index: #{index}") unless @tracks[index]?
      track = @tracks.delete_at(index)
      track.node.stop
      # TODO: detachNode: via ObjC bridge
    end

    def volume(track index : Int32, level : Float32)
      raise IndexError.new("Invalid track index: #{index}") unless @tracks[index]?
      @tracks[index].node.volume = level.clamp(0.0_f32, 1.0_f32)
    end

    def master_volume=(level : Float32)
      @master_volume = level.clamp(0.0_f32, 1.0_f32)
      @mixer.output_volume = @master_volume
    end

    def play
      return if @playing
      @engine.prepare unless @engine.running?
      # TODO: schedule files on each player node, then start engine
      # Requires AVAudioFile alloc+init via ObjC bridge
      @engine.start
      @tracks.each(&.node.play)
      @playing = true
    end

    def pause
      return unless @playing
      @tracks.each(&.node.pause)
      @engine.pause
      @playing = false
    end

    def stop
      @tracks.each(&.node.stop)
      @engine.stop
      @playing = false
    end

    def track_count : Int32
      @tracks.size
    end
  end
end

{% end %}
