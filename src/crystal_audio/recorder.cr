{% if flag?(:darwin) %}

require "mutex"

# High-level audio recording API.
#
# Supports three recording modes:
#   - :microphone   — mic input only (AudioQueue, no blocks needed)
#   - :system       — system audio only (CoreAudio tap / SCStream)
#   - :both         — mic + system audio simultaneously as separate streams
#
# Output formats: :wav (lossless), :aac (compressed)
#
# Example — record mic for 10 seconds to a WAV file:
#
#   rec = CrystalAudio::Recorder.new(
#     source: :microphone,
#     output_path: "/tmp/recording.wav"
#   )
#   rec.start
#   sleep 10.seconds
#   rec.stop
#
# Example — record both streams in parallel:
#
#   rec = CrystalAudio::Recorder.new(
#     source: :both,
#     output_path: "/tmp/meeting.wav",         # system audio
#     mic_output_path: "/tmp/dictation.wav"    # mic audio
#   )
#   rec.start
#   # ... meeting happens ...
#   rec.stop

module CrystalAudio
  enum RecordingSource
    Microphone
    System
    Both
  end

  enum AudioOutputFormat
    WAV
    AAC
  end

  class Recorder
    SAMPLE_RATE    =  44_100.0_f64
    CHANNELS       =          1_u32  # mono for mic; system tap returns stereo
    BITS_PER_SAMPLE =        16_u32
    BUFFER_SIZE    = 0x4000_u32      # 16 KB ≈ 185ms at 44100 mono 16-bit
    NUM_BUFFERS    =         3       # triple buffering

    getter source        : RecordingSource
    getter output_path   : String
    getter mic_output_path : String?
    getter? recording    : Bool

    @mutex       : Mutex
    @queue       : LibAudioToolbox::AudioQueueRef
    @ext_file    : LibAudioToolbox::ExtAudioFileRef
    @context     : RecordContext*
    @system_tap  : SystemAudioCapture?
    @sys_ext_file : LibAudioToolbox::ExtAudioFileRef

    # Context struct passed to the AudioQueue C callback.
    # Must be C-heap allocated (invisible to GC — intentionally, since no
    # Crystal objects are stored here).
    struct RecordContext
      ext_file : LibAudioToolbox::ExtAudioFileRef
    end

    def initialize(
      source : RecordingSource = RecordingSource::Microphone,
      output_path : String = "/tmp/recording.wav",
      mic_output_path : String? = nil
    )
      @source = source
      @output_path = output_path
      @mic_output_path = mic_output_path
      @recording = false
      @mutex = Mutex.new
      @queue = Pointer(Void).null
      @ext_file = Pointer(Void).null
      @context = Pointer(RecordContext).null
      @sys_ext_file = Pointer(Void).null
    end

    def start
      @mutex.synchronize do
        raise "Already recording" if @recording

        case @source
        when RecordingSource::Microphone
          start_mic_queue(@output_path)
        when RecordingSource::System
          start_system_tap(@output_path)
        when RecordingSource::Both
          mic_path = @mic_output_path || derive_mic_path(@output_path)
          start_mic_queue(mic_path)
          start_system_tap(@output_path)
        end

        @recording = true
      end
    end

    def stop
      @mutex.synchronize do
        return unless @recording

        stop_mic_queue
        stop_system_tap

        @recording = false
      end
    end

    # ── Private: mic via AudioQueue ─────────────────────────────────────────

    private def start_mic_queue(path : String)
      asbd = mic_asbd
      @ext_file = open_ext_file(path, asbd)

      @context = Pointer(RecordContext).malloc(1)
      @context.value.ext_file = @ext_file

      # AudioQueue C callback — runs on OS audio thread, must NOT allocate
      cb = LibAudioToolbox::AudioQueueInputCallback.new do |user_data, aq, buffer_ref, _ts, _npd, _pd|
        ctx = user_data.as(RecordContext*)
        buf = buffer_ref.as(LibAudioToolbox::AudioQueueBuffer*)
        next if buf.value.audio_data_byte_size == 0

        abl = LibAudioToolbox::AudioBufferList.new
        abl.number_buffers = 1
        abl.buffers[0].number_channels = 1
        abl.buffers[0].data_byte_size = buf.value.audio_data_byte_size
        abl.buffers[0].data = buf.value.audio_data

        frames = buf.value.audio_data_byte_size / (BITS_PER_SAMPLE // 8)
        LibAudioToolbox.ExtAudioFileWrite(ctx.value.ext_file, frames, pointerof(abl))
        LibAudioToolbox.AudioQueueEnqueueBuffer(aq, buffer_ref, 0, Pointer(LibAudioToolbox::AudioStreamPacketDescription).null)
      end

      aq = Pointer(Void).null
      status = LibAudioToolbox.AudioQueueNewInput(
        pointerof(asbd), cb, @context.as(Void*),
        nil, nil, 0_u32, pointerof(aq)
      )
      raise "AudioQueueNewInput failed: #{status}" unless status == 0
      @queue = aq

      NUM_BUFFERS.times do
        buf = Pointer(Void).null
        LibAudioToolbox.AudioQueueAllocateBuffer(@queue, BUFFER_SIZE, pointerof(buf))
        LibAudioToolbox.AudioQueueEnqueueBuffer(@queue, buf, 0_u32, Pointer(LibAudioToolbox::AudioStreamPacketDescription).null)
      end

      status = LibAudioToolbox.AudioQueueStart(@queue, nil)
      raise "AudioQueueStart failed: #{status}" unless status == 0
    end

    private def stop_mic_queue
      return if @queue.null?
      LibAudioToolbox.AudioQueueStop(@queue, true)
      LibAudioToolbox.AudioQueueDispose(@queue, true)
      @queue = Pointer(Void).null

      LibAudioToolbox.ExtAudioFileDispose(@ext_file) unless @ext_file.null?
      @ext_file = Pointer(Void).null

      @context.free unless @context.null?
      @context = Pointer(RecordContext).null
    end

    # ── Private: system audio tap ───────────────────────────────────────────

    private def start_system_tap(path : String)
      asbd = system_asbd
      @sys_ext_file = open_ext_file(path, asbd)
      sys_file_ref = @sys_ext_file  # local for callback capture

      @system_tap = SystemAudioCapture.new
      @system_tap.not_nil!.start do |frames, frame_count, channel_count|
        abl = LibAudioToolbox::AudioBufferList.new
        abl.number_buffers = 1
        abl.buffers[0].number_channels = channel_count
        abl.buffers[0].data_byte_size = frame_count * channel_count * 4_u32  # float32
        abl.buffers[0].data = frames.to_unsafe.as(Void*)
        LibAudioToolbox.ExtAudioFileWrite(sys_file_ref, frame_count, pointerof(abl))
      end
    end

    private def stop_system_tap
      @system_tap.try(&.stop)
      @system_tap = nil

      LibAudioToolbox.ExtAudioFileDispose(@sys_ext_file) unless @sys_ext_file.null?
      @sys_ext_file = Pointer(Void).null
    end

    # ── Private: ASBD helpers ───────────────────────────────────────────────

    private def mic_asbd : LibAudioToolbox::AudioStreamBasicDescription
      asbd = LibAudioToolbox::AudioStreamBasicDescription.new
      asbd.sample_rate = SAMPLE_RATE
      asbd.format_id = LibAudioToolbox::AUDIO_FORMAT_LINEAR_PCM
      asbd.format_flags = LibAudioToolbox::AUDIO_FORMAT_FLAG_IS_SIGNED_INT |
                          LibAudioToolbox::AUDIO_FORMAT_FLAG_IS_PACKED
      asbd.bytes_per_packet = CHANNELS * (BITS_PER_SAMPLE // 8)
      asbd.frames_per_packet = 1_u32
      asbd.bytes_per_frame = CHANNELS * (BITS_PER_SAMPLE // 8)
      asbd.channels_per_frame = CHANNELS
      asbd.bits_per_channel = BITS_PER_SAMPLE
      asbd.reserved = 0_u32
      asbd
    end

    private def system_asbd : LibAudioToolbox::AudioStreamBasicDescription
      # System tap delivers stereo float32 at 48 kHz
      asbd = LibAudioToolbox::AudioStreamBasicDescription.new
      asbd.sample_rate = 48_000.0
      asbd.format_id = LibAudioToolbox::AUDIO_FORMAT_LINEAR_PCM
      asbd.format_flags = LibAudioToolbox::AUDIO_FORMAT_FLAG_IS_FLOAT |
                          LibAudioToolbox::AUDIO_FORMAT_FLAG_IS_PACKED
      asbd.bytes_per_packet = 2_u32 * 4_u32   # stereo * float32
      asbd.frames_per_packet = 1_u32
      asbd.bytes_per_frame = 2_u32 * 4_u32
      asbd.channels_per_frame = 2_u32
      asbd.bits_per_channel = 32_u32
      asbd.reserved = 0_u32
      asbd
    end

    private def open_ext_file(
      path : String,
      asbd : LibAudioToolbox::AudioStreamBasicDescription
    ) : LibAudioToolbox::ExtAudioFileRef
      url = CF.file_url(path)
      file_type = path.ends_with?(".wav") ?
        LibAudioToolbox::AUDIO_FILE_WAVE_TYPE :
        LibAudioToolbox::AUDIO_FILE_M4A_TYPE

      ext_file = Pointer(Void).null
      status = LibAudioToolbox.ExtAudioFileCreateWithURL(
        url, file_type, pointerof(asbd), nil, 0_u32, pointerof(ext_file)
      )
      LibCoreFoundation.CFRelease(url)
      raise "ExtAudioFileCreateWithURL failed: #{status}" unless status == 0

      # Set client format (what we write) = same as file format
      status = LibAudioToolbox.ExtAudioFileSetProperty(
        ext_file,
        LibAudioToolbox::EXT_AUDIO_FILE_PROPERTY_CLIENT_DATA_FORMAT,
        sizeof(LibAudioToolbox::AudioStreamBasicDescription).to_u32,
        pointerof(asbd).as(Void*)
      )
      raise "ExtAudioFileSetProperty failed: #{status}" unless status == 0

      ext_file
    end

    private def derive_mic_path(system_path : String) : String
      ext = File.extname(system_path)
      base = system_path[0..-(ext.size + 1)]
      "#{base}_mic#{ext}"
    end
  end
end

{% end %}
