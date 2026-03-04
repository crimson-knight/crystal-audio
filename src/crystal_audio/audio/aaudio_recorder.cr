{% if flag?(:android) %}

require "mutex"

# Android audio recorder using AAudio input streams.
#
# Records microphone input to a WAV file using AAudio's callback-driven API.
# The data callback copies PCM frames to a ring buffer; a separate thread
# writes the ring buffer to disk.
#
# Known limitation: Android emulator returns silence for mic input.
# Non-silence verification requires a real device.

module CrystalAudio
  class AndroidRecorder
    SAMPLE_RATE     = 44100
    CHANNELS        = 1
    BITS_PER_SAMPLE = 16
    BUFFER_FRAMES   = 4096
    RING_SIZE       = SAMPLE_RATE * CHANNELS * 2 * 5  # 5 seconds of ring buffer

    getter? recording : Bool
    getter output_path : String

    @stream : LibAAudio::AAudioStreamRef
    @mutex : Mutex
    @ring_buffer : Slice(UInt8)
    @ring_write_pos : Int32
    @ring_read_pos : Int32
    @file : File?
    @writer_running : Bool
    @total_frames : Int64

    def initialize(@output_path : String)
      @stream = Pointer(Void).null
      @recording = false
      @mutex = Mutex.new
      @ring_buffer = Slice(UInt8).new(RING_SIZE)
      @ring_write_pos = 0
      @ring_read_pos = 0
      @file = nil
      @writer_running = false
      @total_frames = 0_i64
    end

    def start
      @mutex.synchronize do
        raise "Already recording" if @recording

        # Open WAV file and write placeholder header
        @file = File.open(@output_path, "wb")
        write_wav_header(@file.not_nil!, 0_u32)  # will be updated on stop

        # Reset ring buffer
        @ring_write_pos = 0
        @ring_read_pos = 0
        @total_frames = 0_i64

        # Create AAudio input stream
        builder = Pointer(Void).null
        result = LibAAudio.AAudio_createStreamBuilder(pointerof(builder))
        raise "AAudio_createStreamBuilder failed: #{result}" unless result == LibAAudio::AAUDIO_OK

        LibAAudio.AAudioStreamBuilder_setDirection(builder, LibAAudio::AAUDIO_DIRECTION_INPUT)
        LibAAudio.AAudioStreamBuilder_setSampleRate(builder, SAMPLE_RATE)
        LibAAudio.AAudioStreamBuilder_setChannelCount(builder, CHANNELS)
        LibAAudio.AAudioStreamBuilder_setFormat(builder, LibAAudio::AAUDIO_FORMAT_PCM_I16)
        LibAAudio.AAudioStreamBuilder_setSharingMode(builder, LibAAudio::AAUDIO_SHARING_MODE_SHARED)
        LibAAudio.AAudioStreamBuilder_setPerformanceMode(builder, LibAAudio::AAUDIO_PERFORMANCE_MODE_LOW_LATENCY)

        # Set data callback
        LibAAudio.AAudioStreamBuilder_setDataCallback(
          builder,
          ->AndroidRecorder.data_callback,
          Box.box(self).as(Void*)
        )

        stream = Pointer(Void).null
        result = LibAAudio.AAudioStreamBuilder_openStream(builder, pointerof(stream))
        LibAAudio.AAudioStreamBuilder_delete(builder)
        raise "AAudioStreamBuilder_openStream failed: #{result}" unless result == LibAAudio::AAUDIO_OK
        @stream = stream

        # Start the disk writer thread
        @writer_running = true
        spawn_writer_fiber

        # Start the stream
        result = LibAAudio.AAudioStream_requestStart(@stream)
        raise "AAudioStream_requestStart failed: #{result}" unless result == LibAAudio::AAUDIO_OK

        @recording = true
      end
    end

    def stop
      @mutex.synchronize do
        return unless @recording

        # Stop the AAudio stream
        LibAAudio.AAudioStream_requestStop(@stream) unless @stream.null?
        LibAAudio.AAudioStream_close(@stream) unless @stream.null?
        @stream = Pointer(Void).null

        # Stop the writer
        @writer_running = false
        # Give writer a moment to flush
        sleep 100.milliseconds

        # Flush remaining ring buffer data
        flush_ring_to_disk

        # Update WAV header with final data size
        if file = @file
          data_size = @total_frames * CHANNELS * (BITS_PER_SAMPLE // 8)
          file.seek(0)
          write_wav_header(file, data_size.to_u32)
          file.close
          @file = nil
        end

        @recording = false
      end
    end

    # ── Static data callback (called from AAudio on audio thread) ──────────

    protected def self.data_callback(
      stream : LibAAudio::AAudioStreamRef,
      user_data : Void*,
      audio_data : Void*,
      num_frames : Int32
    ) : Int32
      recorder = Box(AndroidRecorder).unbox(user_data)
      recorder.on_audio_data(audio_data, num_frames)
      LibAAudio::AAUDIO_CALLBACK_RESULT_CONTINUE
    end

    # Copy incoming audio data to ring buffer (called on audio thread — must be fast).
    protected def on_audio_data(data : Void*, num_frames : Int32)
      byte_count = num_frames * CHANNELS * (BITS_PER_SAMPLE // 8)
      src = data.as(UInt8*)

      # Simple linear write — wrap around if needed
      byte_count.times do |i|
        @ring_buffer[@ring_write_pos % RING_SIZE] = src[i]
        @ring_write_pos = (@ring_write_pos + 1) % RING_SIZE
      end
    end

    # ── Private ────────────────────────────────────────────────────────────

    private def spawn_writer_fiber
      spawn do
        while @writer_running
          flush_ring_to_disk
          sleep 50.milliseconds  # flush every 50ms
        end
      end
    end

    private def flush_ring_to_disk
      return unless file = @file

      # Calculate how many bytes are available to read
      write_pos = @ring_write_pos
      read_pos = @ring_read_pos
      return if write_pos == read_pos

      available = if write_pos >= read_pos
                    write_pos - read_pos
                  else
                    RING_SIZE - read_pos + write_pos
                  end

      return if available <= 0

      # Write in chunks to avoid spanning the ring boundary
      bytes_written = 0
      while bytes_written < available
        chunk_start = (@ring_read_pos + bytes_written) % RING_SIZE
        chunk_end = Math.min(chunk_start + (available - bytes_written), RING_SIZE)
        chunk_size = chunk_end - chunk_start

        file.write(@ring_buffer[chunk_start, chunk_size])
        bytes_written += chunk_size
      end

      @ring_read_pos = (@ring_read_pos + available) % RING_SIZE
      frames_written = available // (CHANNELS * (BITS_PER_SAMPLE // 8))
      @total_frames += frames_written
    end

    private def write_wav_header(file : File, data_size : UInt32)
      file_size = 36_u32 + data_size
      bytes_per_sec = (SAMPLE_RATE * CHANNELS * (BITS_PER_SAMPLE // 8)).to_u32
      block_align = (CHANNELS * (BITS_PER_SAMPLE // 8)).to_u16

      file.write("RIFF".to_slice)
      file.write_bytes(file_size, IO::ByteFormat::LittleEndian)
      file.write("WAVE".to_slice)
      file.write("fmt ".to_slice)
      file.write_bytes(16_u32, IO::ByteFormat::LittleEndian)
      file.write_bytes(1_u16, IO::ByteFormat::LittleEndian)  # PCM
      file.write_bytes(CHANNELS.to_u16, IO::ByteFormat::LittleEndian)
      file.write_bytes(SAMPLE_RATE.to_u32, IO::ByteFormat::LittleEndian)
      file.write_bytes(bytes_per_sec, IO::ByteFormat::LittleEndian)
      file.write_bytes(block_align, IO::ByteFormat::LittleEndian)
      file.write_bytes(BITS_PER_SAMPLE.to_u16, IO::ByteFormat::LittleEndian)
      file.write("data".to_slice)
      file.write_bytes(data_size, IO::ByteFormat::LittleEndian)
    end
  end
end

{% end %}
