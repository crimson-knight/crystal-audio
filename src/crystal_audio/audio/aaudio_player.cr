{% if flag?(:android) %}

# AAudioPlayer — Android multi-track playback using AAudio output streams.
#
# Pre-decodes WAV tracks into Float32 buffers and mixes them in a single
# AAudio output stream callback. Each track has independent volume control.
#
# Architecture:
#   - Single AAudio output stream with data callback
#   - Callback sums all track buffers x per-track gain -> output buffer
#   - All tracks start from frame 0 for synchronized playback

module CrystalAudio
  class AAudioPlayer
    MAX_TRACKS = 16

    struct AAudioTrack
      getter samples : Slice(Float32)
      getter sample_rate : Int32
      getter channels : Int32
      property volume : Float32
      property position : Int64  # current playback frame

      def initialize(@samples, @sample_rate, @channels, @volume = 1.0_f32)
        @position = 0_i64
      end

      def frame_count : Int64
        (@samples.size // @channels).to_i64
      end

      def finished? : Bool
        @position >= frame_count
      end
    end

    getter? playing : Bool
    getter master_volume : Float32

    @stream : LibAAudio::AAudioStreamRef
    @tracks : Array(AAudioTrack)
    @output_sample_rate : Int32

    def initialize
      @stream = Pointer(Void).null
      @tracks = Array(AAudioTrack).new(MAX_TRACKS)
      @playing = false
      @master_volume = 1.0_f32
      @output_sample_rate = 44100
    end

    def add_track(path : String, volume : Float32 = 1.0_f32) : Int32
      raise "Maximum #{MAX_TRACKS} tracks" if @tracks.size >= MAX_TRACKS
      decoder = WavDecoder.new(path)
      track = AAudioTrack.new(
        samples: decoder.samples,
        sample_rate: decoder.sample_rate,
        channels: decoder.channels,
        volume: volume
      )
      @tracks << track
      @tracks.size - 1
    end

    def volume(track index : Int32, level : Float32)
      raise IndexError.new("Invalid track index") unless @tracks[index]?
      @tracks[index].volume = level.clamp(0.0_f32, 1.0_f32)
    end

    def master_volume=(level : Float32)
      @master_volume = level.clamp(0.0_f32, 1.0_f32)
    end

    def play
      return if @playing
      raise "No tracks added" if @tracks.empty?

      # Reset all track positions
      @tracks.each { |t| t.position = 0_i64 }

      # Create AAudio output stream
      builder = Pointer(Void).null
      result = LibAAudio.AAudio_createStreamBuilder(pointerof(builder))
      raise "AAudio_createStreamBuilder failed: #{result}" unless result == LibAAudio::AAUDIO_OK

      LibAAudio.AAudioStreamBuilder_setDirection(builder, LibAAudio::AAUDIO_DIRECTION_OUTPUT)
      LibAAudio.AAudioStreamBuilder_setSampleRate(builder, @output_sample_rate)
      LibAAudio.AAudioStreamBuilder_setChannelCount(builder, 2)  # stereo output
      LibAAudio.AAudioStreamBuilder_setFormat(builder, LibAAudio::AAUDIO_FORMAT_PCM_FLOAT)
      LibAAudio.AAudioStreamBuilder_setSharingMode(builder, LibAAudio::AAUDIO_SHARING_MODE_SHARED)
      LibAAudio.AAudioStreamBuilder_setPerformanceMode(builder, LibAAudio::AAUDIO_PERFORMANCE_MODE_LOW_LATENCY)

      LibAAudio.AAudioStreamBuilder_setDataCallback(
        builder,
        ->AAudioPlayer.output_callback,
        Box.box(self).as(Void*)
      )

      stream = Pointer(Void).null
      result = LibAAudio.AAudioStreamBuilder_openStream(builder, pointerof(stream))
      LibAAudio.AAudioStreamBuilder_delete(builder)
      raise "Open output stream failed: #{result}" unless result == LibAAudio::AAUDIO_OK
      @stream = stream

      @output_sample_rate = LibAAudio.AAudioStream_getSampleRate(@stream)

      result = LibAAudio.AAudioStream_requestStart(@stream)
      raise "Start output stream failed: #{result}" unless result == LibAAudio::AAUDIO_OK

      @playing = true
    end

    def pause
      return unless @playing
      LibAAudio.AAudioStream_requestPause(@stream) unless @stream.null?
      @playing = false
    end

    def resume
      return if @playing
      return if @stream.null?
      LibAAudio.AAudioStream_requestStart(@stream)
      @playing = true
    end

    def stop
      return if @stream.null?
      LibAAudio.AAudioStream_requestStop(@stream)
      LibAAudio.AAudioStream_close(@stream)
      @stream = Pointer(Void).null
      @playing = false
    end

    def track_count : Int32
      @tracks.size
    end

    # ── Static output callback ────────────────────────────────────────────

    protected def self.output_callback(
      stream : LibAAudio::AAudioStreamRef,
      user_data : Void*,
      audio_data : Void*,
      num_frames : Int32
    ) : Int32
      player = Box(AAudioPlayer).unbox(user_data)
      player.mix_output(audio_data.as(Float32*), num_frames)
    end

    # Mix all tracks into the output buffer (stereo Float32).
    protected def mix_output(output : Float32*, num_frames : Int32) : Int32
      # Zero the output buffer
      total_samples = num_frames * 2  # stereo
      total_samples.times { |i| output[i] = 0.0_f32 }

      all_finished = true

      @tracks.each do |track|
        next if track.finished?
        all_finished = false

        gain = track.volume * @master_volume
        frames_available = Math.min(num_frames.to_i64, track.frame_count - track.position)

        if track.channels == 1
          # Mono → stereo upmix
          frames_available.times do |f|
            sample = track.samples[(track.position + f).to_i32] * gain
            output[f.to_i32 * 2] += sample      # left
            output[f.to_i32 * 2 + 1] += sample  # right
          end
        elsif track.channels == 2
          # Stereo passthrough
          frames_available.times do |f|
            src_idx = ((track.position + f) * 2).to_i32
            output[f.to_i32 * 2] += track.samples[src_idx] * gain
            output[f.to_i32 * 2 + 1] += track.samples[src_idx + 1] * gain
          end
        end

        track.position += frames_available
      end

      # Clamp output to [-1, 1]
      total_samples.times do |i|
        output[i] = output[i].clamp(-1.0_f32, 1.0_f32)
      end

      all_finished ? LibAAudio::AAUDIO_CALLBACK_RESULT_STOP : LibAAudio::AAUDIO_CALLBACK_RESULT_CONTINUE
    end
  end
end

{% end %}
