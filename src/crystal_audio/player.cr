{% if flag?(:android) %}

# Android Player — delegates to AAudioPlayer for multi-track playback.

module CrystalAudio
  class Player
    MAX_TRACKS = 16

    getter master_volume : Float32
    getter? playing : Bool

    @backend : AAudioPlayer

    def initialize
      @backend = AAudioPlayer.new
      @master_volume = 1.0_f32
      @playing = false
    end

    def add_track(path : String, volume : Float32 = 1.0_f32) : Int32
      @backend.add_track(path, volume)
    end

    def volume(track index : Int32, level : Float32)
      @backend.volume(track: index, level: level)
    end

    def master_volume=(level : Float32)
      @master_volume = level.clamp(0.0_f32, 1.0_f32)
      @backend.master_volume = @master_volume
    end

    def play
      return if @playing
      @backend.play
      @playing = true
    end

    def pause
      return unless @playing
      @backend.pause
      @playing = false
    end

    def resume
      return if @playing
      @backend.resume
      @playing = true
    end

    def stop
      @backend.stop
      @playing = false
    end

    def track_count : Int32
      @backend.track_count
    end
  end
end

{% elsif flag?(:darwin) %}

# Multi-track audio player (macOS / iOS).
#
# Layers multiple audio tracks for simultaneous playback with:
#   - Per-track volume control
#   - Master volume control
#   - Synchronized play/pause/stop across all tracks
#   - AVAudioFile scheduling for each track
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

    # Offset in seconds for synchronized start (gives all nodes time to prepare).
    SYNC_OFFSET = 0.1

    getter master_volume : Float32
    getter? playing : Bool

    @engine  : AudioEngine
    @mixer   : AudioMixerNode
    @tracks  : Array(Track)

    struct Track
      getter path    : String
      getter node    : AudioPlayerNode
      getter file    : AVAudioFile
      getter volume  : Float32

      def initialize(@path, @node, @file, @volume = 1.0_f32)
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
      file = AVAudioFile.new(path)
      format = file.processing_format

      @engine.attach(node.ptr)
      @engine.connect(node.ptr, @engine.main_mixer_node, format)

      @tracks << Track.new(path, node, file, volume)
      @tracks.size - 1
    end

    def remove_track(index : Int32)
      raise IndexError.new("Invalid track index: #{index}") unless @tracks[index]?
      track = @tracks.delete_at(index)
      track.node.stop
      ObjC.detach(@engine.ptr, track.node.ptr)
    end

    def volume(track index : Int32, level : Float32)
      raise IndexError.new("Invalid track index: #{index}") unless @tracks[index]?
      @tracks[index].node.volume = level.clamp(0.0_f32, 1.0_f32)
    end

    def master_volume=(level : Float32)
      @master_volume = level.clamp(0.0_f32, 1.0_f32)
      @mixer.output_volume = @master_volume
    end

    # Start playback. Schedules files on all player nodes, starts the engine,
    # then issues a synchronized play_at_time on all nodes.
    def play
      return if @playing
      raise "No tracks added" if @tracks.empty?

      # Schedule each file on its player node
      @tracks.each do |track|
        track.node.schedule_file(track.file.ptr)
      end

      # Start the engine
      @engine.prepare unless @engine.running?
      @engine.start

      if @tracks.size == 1
        # Single track: just play immediately
        @tracks[0].node.play
      else
        # Multi-track: synchronize via play_at_time
        # Get a reference time from the first node's last render time
        # then offset slightly into the future so all nodes start together
        first_time = @tracks[0].node.last_render_time
        if first_time
          sample_rate = ObjC.audio_time_get_rate(first_time)
          sample_time = ObjC.audio_time_get_sample(first_time)
          offset_samples = (SYNC_OFFSET * sample_rate).to_i64
          future_time = ObjC.audio_time_sample(sample_time + offset_samples, sample_rate)

          @tracks.each do |track|
            track.node.play_at_time(future_time)
          end
        else
          # Fallback: play immediately if no render time available yet
          @tracks.each(&.node.play)
        end
      end

      @playing = true
    end

    # Pause all nodes (keeps engine running for quick resume).
    def pause
      return unless @playing
      @tracks.each(&.node.pause)
      @playing = false
    end

    # Resume from paused state. Re-schedules files and plays.
    def resume
      return if @playing
      return if @tracks.empty?

      # Re-schedule and play (AVAudioPlayerNode requires re-scheduling after stop/pause)
      @tracks.each do |track|
        track.node.schedule_file(track.file.ptr)
        track.node.play
      end
      @playing = true
    end

    def stop
      @tracks.each(&.node.stop)
      @engine.stop
      @playing = false
    end

    def track_count : Int32
      @tracks.size
    end

    # --- Lock Screen / Now Playing Integration ---

    # Set the master track whose metadata appears on lock screen.
    # Provide title/artist/duration to display. Call after play to update elapsed time.
    def set_now_playing(title : String, artist : String = "", duration : Float64 = 0.0)
      @now_playing ||= NowPlayingInfo.new
      @now_playing_title = title
      @now_playing_artist = artist
      @now_playing_duration = duration
      update_now_playing_state
    end

    # Clear lock screen now playing info.
    def clear_now_playing
      @now_playing.try(&.clear)
    end

    # Register remote command handlers (play/pause/skip from lock screen).
    # Returns the RemoteCommandCenter for further customization.
    def enable_remote_commands : RemoteCommandCenter
      rc = RemoteCommandCenter.new
      rc.on_play { play unless playing? }
      rc.on_pause { pause if playing? }
      rc.on_toggle_play_pause { playing? ? pause : (playing? ? nil : play) }
      rc.enable
      @remote_commands = rc
      rc
    end

    private def update_now_playing_state
      np = @now_playing
      return unless np
      rate = @playing ? 1.0 : 0.0
      np.update(
        title: @now_playing_title,
        artist: @now_playing_artist,
        duration: @now_playing_duration || 0.0,
        elapsed: 0.0,
        rate: rate
      )
    end

    @now_playing : NowPlayingInfo?
    @now_playing_title : String?
    @now_playing_artist : String?
    @now_playing_duration : Float64?
    @remote_commands : RemoteCommandCenter?
  end
end

{% end %}
