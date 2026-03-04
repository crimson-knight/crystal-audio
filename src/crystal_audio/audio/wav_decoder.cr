# WAV file decoder — reads WAV files into Float32 sample buffers.
#
# Used by Android's AAudioPlayer which needs pre-decoded audio data
# for its manual mixing engine (unlike AVAudioEngine which decodes internally).

module CrystalAudio
  class WavDecoder
    getter sample_rate : Int32
    getter channels : Int32
    getter bit_depth : Int32
    getter samples : Slice(Float32)

    def initialize(path : String)
      raise "File not found: #{path}" unless File.exists?(path)

      # Initialize before block so Crystal doesn't consider them nilable
      @sample_rate = 44100
      @channels = 1
      @bit_depth = 16
      @samples = Slice(Float32).empty

      File.open(path, "rb") do |file|
        # Read RIFF header
        riff = Bytes.new(4)
        file.read(riff)
        raise "Not a RIFF file" unless String.new(riff) == "RIFF"

        file_size = file.read_bytes(UInt32, IO::ByteFormat::LittleEndian)

        wave = Bytes.new(4)
        file.read(wave)
        raise "Not a WAVE file" unless String.new(wave) == "WAVE"

        # Read chunks — fmt and data update instance variables
        format_tag = 1_u16  # PCM

        while file.pos < file.size
          chunk_id = Bytes.new(4)
          bytes_read = file.read(chunk_id)
          break if bytes_read < 4

          chunk_size = file.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
          chunk_name = String.new(chunk_id)

          case chunk_name
          when "fmt "
            format_tag = file.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
            @channels = file.read_bytes(UInt16, IO::ByteFormat::LittleEndian).to_i32
            @sample_rate = file.read_bytes(UInt32, IO::ByteFormat::LittleEndian).to_i32
            _byte_rate = file.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
            _block_align = file.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
            @bit_depth = file.read_bytes(UInt16, IO::ByteFormat::LittleEndian).to_i32
            # Skip any extra fmt data
            remaining = chunk_size.to_i32 - 16
            file.skip(remaining) if remaining > 0
          when "data"
            @samples = decode_pcm_data(file, chunk_size, format_tag)
          else
            # Skip unknown chunks
            file.skip(chunk_size.to_i32)
          end
        end

        raise "No audio data found in WAV file" if @samples.empty?
      end
    end

    # Total number of frames (samples per channel).
    def frame_count : Int32
      @samples.size // @channels
    end

    # Duration in seconds.
    def duration : Float64
      frame_count.to_f64 / @sample_rate.to_f64
    end

    private def decode_pcm_data(
      file : File,
      data_size : UInt32,
      format_tag : UInt16
    ) : Slice(Float32)
      case {format_tag, @bit_depth}
      when {1, 16} # PCM 16-bit signed integer
        num_samples = data_size // 2
        result = Slice(Float32).new(num_samples.to_i32)
        num_samples.times do |i|
          sample_i16 = file.read_bytes(Int16, IO::ByteFormat::LittleEndian)
          result[i.to_i32] = sample_i16.to_f32 / 32768.0_f32
        end
        result
      when {1, 24} # PCM 24-bit signed integer
        num_samples = data_size // 3
        result = Slice(Float32).new(num_samples.to_i32)
        bytes = Bytes.new(3)
        num_samples.times do |i|
          file.read(bytes)
          # Sign-extend 24-bit to 32-bit
          val = bytes[0].to_i32 | (bytes[1].to_i32 << 8) | (bytes[2].to_i32 << 16)
          val = val - 0x1000000 if val >= 0x800000
          result[i.to_i32] = val.to_f32 / 8388608.0_f32
        end
        result
      when {3, 32} # IEEE Float 32-bit
        num_samples = data_size // 4
        result = Slice(Float32).new(num_samples.to_i32)
        num_samples.times do |i|
          result[i.to_i32] = file.read_bytes(Float32, IO::ByteFormat::LittleEndian)
        end
        result
      else
        raise "Unsupported WAV format: tag=#{format_tag}, bits=#{@bit_depth}"
      end
    end
  end
end
