module CrystalAudio
  # Identifies an input device selection failure while configuring an AudioQueue.
  class InputDeviceSelectionError < Exception
    # The UID that AudioQueue could not select.
    getter input_device_uid : String

    # The OSStatus returned while AudioQueue selected the input device.
    getter status : Int32

    def initialize(@input_device_uid : String, @status : Int32)
      super("AudioQueueSetProperty(kAudioQueueProperty_CurrentDevice) failed for input device UID '#{@input_device_uid}': OSStatus #{@status}")
    end
  end
end

{% if flag?(:android) %}
  # Android recording: delegate to AndroidRecorder (AAudio-based).
  require "mutex"

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
      getter source : RecordingSource
      getter output_path : String
      getter input_device_uid : String?
      getter? recording : Bool

      @android_recorder : AndroidRecorder?

      def initialize(
        source : RecordingSource = RecordingSource::Microphone,
        output_path : String = "/data/local/tmp/recording.wav",
        mic_output_path : String? = nil,
        mic_tap : Proc(Slice(UInt8), UInt32, UInt32, Float64, Nil)? = nil,
        input_device_uid : String? = nil,
      )
        raise ArgumentError.new("input_device_uid is supported only on macOS") if input_device_uid

        @source = source
        @output_path = output_path
        @input_device_uid = input_device_uid
        @recording = false
      end

      def start
        raise "Already recording" if @recording
        raise "Only microphone recording is supported on Android" unless @source == RecordingSource::Microphone

        rec = AndroidRecorder.new(@output_path)
        rec.start
        @android_recorder = rec
        @recording = true
      end

      # Android starts synchronously; these keep the macOS call shape.
      def self.warm_up_input(input_device_uid : String? = nil) : Nil
        raise ArgumentError.new("input_device_uid is supported only on macOS") if input_device_uid
      end

      def start_without_waiting : Nil
        start
      end

      def wait_until_started : Nil
      end

      def wait_until_microphone_started : Nil
      end

      def start_finished? : Bool
        true
      end

      def stop
        return unless @recording
        @android_recorder.try(&.stop)
        @android_recorder = nil
        @recording = false
      end
    end
  end
{% elsif flag?(:darwin) %}
  require "mutex"

  module CrystalAudio::AudioQueue
    # :nodoc:
    # Sets the current input device for *queue* before the queue starts.
    def self.set_current_input_device(queue : LibAudioToolbox::AudioQueueRef, input_device_uid : String) : Nil
      cf_input_device_uid = CF.string(input_device_uid)
      status = -1

      begin
        unless cf_input_device_uid.null?
          status = LibAudioToolbox.AudioQueueSetProperty(
            queue,
            LibAudioToolbox::AUDIO_QUEUE_PROPERTY_CURRENT_DEVICE,
            pointerof(cf_input_device_uid).as(Void*),
            sizeof(LibCoreFoundation::CFStringRef).to_u32
          )
        end
      ensure
        LibCoreFoundation.CFRelease(cf_input_device_uid) unless cf_input_device_uid.null?
      end

      raise InputDeviceSelectionError.new(input_device_uid, status) unless status == 0
    end
  end

  # C helpers (ext/audio_queue_start.c) that run AudioQueueStart and the
  # one-time Core Audio input setup on a dispatch queue, in plain C.
  lib LibAudioQueueStart
    fun ca_audio_queue_start_async(queue : LibAudioToolbox::AudioQueueRef) : Void*
    fun ca_audio_queue_start_wait(handle : Void*) : Int32
    fun ca_audio_queue_start_is_finished(handle : Void*) : Int32
    fun ca_audio_input_warm_up_async(device_uid : UInt8*) : Void
  end

  # C helper that constructs AudioBufferList on the C stack and calls
  # ExtAudioFileWrite — avoids Crystal struct layout issues.
  lib LibAudioWriteHelper
    fun ca_ext_audio_file_write_pcm(
      ext_file : Void*,
      data : Void*,
      byte_size : UInt32,
      channels : UInt32,
      bytes_per_frame : UInt32,
    ) : Int32
  end

  # High-level audio recording API.
  #
  # A macOS microphone recording can target a Core Audio device UID with
  # `input_device_uid`; `nil` follows the current system input device.
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
  # Example — start a microphone recording without waiting for the input
  # device, do other work (draw a recording indicator), then confirm:
  #
  #   CrystalAudio::Recorder.warm_up_input # once, while idle
  #   rec = CrystalAudio::Recorder.new(output_path: "/tmp/recording.wav")
  #   rec.start_without_waiting
  #   # ... other work on this thread while the device spins up ...
  #   rec.wait_until_started # raises if the device did not start
  #
  # Example — start a microphone-plus-system recording without blocking the
  # calling thread, and confirm the system tap later:
  #
  #   rec = CrystalAudio::Recorder.new(source: :both, output_path: "/tmp/meeting.wav")
  #   rec.start_without_waiting         # the microphone, then the tap, start on a dispatch queue
  #   rec.wait_until_microphone_started # raises if the microphone did not start
  #   # ... once rec.start_finished? is true, this returns without waiting:
  #   rec.wait_until_started # raises if the system tap did not start
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
      SAMPLE_RATE     = 44_100.0_f64
      CHANNELS        =        1_u32 # mono for mic; system tap returns stereo
      BITS_PER_SAMPLE =       16_u32
      BUFFER_SIZE     =   0x1000_u32 # 4 KB ≈ 46ms at 44100 mono 16-bit
      NUM_BUFFERS     =            3 # triple buffering

      getter source : RecordingSource
      getter output_path : String
      getter mic_output_path : String?
      getter input_device_uid : String?
      getter? recording : Bool

      # user_data for the AudioQueue C callback. The callback must be a plain
      # (non-closure) Proc, so everything it needs travels through this state
      # object instead of captured locals. Retained on the Recorder so the GC
      # keeps it alive for the queue's lifetime.
      private class MicQueueState
        getter ext_file : LibAudioToolbox::ExtAudioFileRef
        getter tap : Proc(Slice(UInt8), UInt32, UInt32, Float64, Nil)?

        def initialize(@ext_file, @tap)
        end
      end

      @mutex : Mutex
      @queue : LibAudioToolbox::AudioQueueRef
      @ext_file : LibAudioToolbox::ExtAudioFileRef
      @system_tap : SystemAudioCapture?
      @sys_ext_file : LibAudioToolbox::ExtAudioFileRef
      @mic_tap : Proc(Slice(UInt8), UInt32, UInt32, Float64, Nil)?
      @mic_state : MicQueueState?
      # The handle of an AudioQueueStart running on a dispatch queue; null
      # when no start is pending.
      @pending_mic_start : Void*

      def initialize(
        source : RecordingSource = RecordingSource::Microphone,
        output_path : String = "/tmp/recording.wav",
        mic_output_path : String? = nil,
        @mic_tap : Proc(Slice(UInt8), UInt32, UInt32, Float64, Nil)? = nil,
        @input_device_uid : String? = nil,
      )
        @source = source
        @output_path = output_path
        @mic_output_path = mic_output_path
        @recording = false
        @mutex = Mutex.new
        @queue = Pointer(Void).null
        @ext_file = Pointer(Void).null
        @sys_ext_file = Pointer(Void).null
        @pending_mic_start = Pointer(Void).null
      end

      # Pays Core Audio's one-time input setup ahead of the first recording,
      # on a background dispatch queue, and returns at once. It creates one
      # input queue for *input_device_uid* (`nil` for the system input
      # device) and disposes it without starting it, so the device stays
      # closed and the microphone indicator stays off. Call it while idle,
      # for example after launch.
      def self.warm_up_input(input_device_uid : String? = nil) : Nil
        if device_uid = input_device_uid
          LibAudioQueueStart.ca_audio_input_warm_up_async(device_uid.to_unsafe)
        else
          LibAudioQueueStart.ca_audio_input_warm_up_async(Pointer(UInt8).null)
        end
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
            begin
              start_system_tap(@output_path)
            rescue ex
              stop_mic_queue
              raise ex
            end
          end

          @recording = true
        end
      end

      # Starts a recording without waiting for its devices: the WAV files and
      # the input AudioQueue are ready when this returns, and the slow work
      # runs on a dispatch queue. A microphone source runs AudioQueueStart
      # there. A system source creates and starts the system-audio tap
      # there. Both runs the microphone's AudioQueueStart and then, once the
      # microphone started, the tap's creation and start, in the order
      # `start` uses. `recording?` is true from here on; call
      # `wait_until_started` (or `wait_until_microphone_started` first)
      # before relying on the recording.
      def start_without_waiting : Nil
        @mutex.synchronize do
          raise "Already recording" if @recording

          case @source
          when RecordingSource::Microphone
            create_mic_queue(@output_path)
            begin_mic_queue_start
          when RecordingSource::System
            begin_system_tap_start(@output_path, Pointer(Void).null)
          when RecordingSource::Both
            create_mic_queue(@mic_output_path || derive_mic_path(@output_path))
            begin
              begin_system_tap_start(@output_path, @queue)
            rescue ex
              dispose_unstarted_mic_queue
              raise ex
            end
          end
          @recording = true
        end
      end

      # Waits for the start begun by `start_without_waiting`: the microphone
      # and, for a system or Both source, the system-audio tap. Returns at
      # once when no start is pending. When anything did not start, every
      # queue, tap and WAV file of the recording is disposed, `recording?`
      # turns false, and this raises the error `start` raises for the same
      # failure ("AudioQueueStart failed: …", "system_audio_tap_create
      # failed: …" or "system_audio_tap_start failed: …").
      def wait_until_started : Nil
        @mutex.synchronize do
          error_message = finish_pending_start
          return unless error_message

          @recording = false
          raise error_message
        end
      end

      # Waits only until the microphone of the start begun by
      # `start_without_waiting` runs; a Both source's system tap may still
      # be starting, and `wait_until_started` confirms it. Returns at once
      # for a system source or when no start is pending. When the microphone
      # did not start, the whole recording is disposed as in
      # `wait_until_started`, and this raises.
      def wait_until_microphone_started : Nil
        @mutex.synchronize do
          if tap = @system_tap
            return if tap.wait_for_queue_start == 0
          elsif @pending_mic_start.null?
            return
          end

          error_message = finish_pending_start
          return unless error_message

          @recording = false
          raise error_message
        end
      end

      # True when `wait_until_started` would return without waiting: no
      # start is pending, or the pending one has finished on its dispatch
      # queue.
      def start_finished? : Bool
        @mutex.synchronize do
          pending_mic_start = @pending_mic_start
          unless pending_mic_start.null?
            next false if LibAudioQueueStart.ca_audio_queue_start_is_finished(pending_mic_start) == 0
          end

          tap = @system_tap
          tap ? tap.start_finished? : true
        end
      end

      def stop
        @mutex.synchronize do
          return unless @recording

          finish_pending_start
          stop_mic_queue
          stop_system_tap

          @recording = false
        end
      end

      # ── Private: mic via AudioQueue ─────────────────────────────────────────

      private def start_mic_queue(path : String)
        create_mic_queue(path)
        start_created_mic_queue
      end

      # Begins AudioQueueStart on the created queue on a dispatch queue, or
      # starts it here when no pending start could be allocated.
      private def begin_mic_queue_start : Nil
        pending_start = LibAudioQueueStart.ca_audio_queue_start_async(@queue)
        if pending_start.null?
          start_created_mic_queue
        else
          @pending_mic_start = pending_start
        end
      end

      # Waits for whatever `start_without_waiting` left pending and returns
      # the error message of the first step that failed, in start order
      # (microphone, tap creation, tap start), or nil when everything
      # started or nothing was pending. On a failure every queue, tap and
      # WAV file of the recording is already disposed.
      private def finish_pending_start : String?
        mic_status = take_pending_mic_start_status
        unless mic_status == 0
          dispose_unstarted_mic_queue
          return "AudioQueueStart failed: #{mic_status}"
        end

        tap = @system_tap
        return nil unless tap && tap.start_pending?

        result = tap.finish_start
        return nil if result.started?

        @system_tap = nil
        dispose_system_ext_file
        if result.queue_status != 0
          dispose_unstarted_mic_queue
          return "AudioQueueStart failed: #{result.queue_status}"
        end

        stop_mic_queue
        result.error_message
      end

      # The status of the pending dispatch-queue start, after waiting for
      # it; 0 when none was pending.
      private def take_pending_mic_start_status : Int32
        pending_start = @pending_mic_start
        return 0 if pending_start.null?

        @pending_mic_start = Pointer(Void).null
        LibAudioQueueStart.ca_audio_queue_start_wait(pending_start)
      end

      private def start_created_mic_queue : Nil
        status = LibAudioToolbox.AudioQueueStart(@queue, nil)
        return if status == 0

        dispose_unstarted_mic_queue
        raise "AudioQueueStart failed: #{status}"
      end

      # Opens the WAV file and creates the input queue with its buffers
      # enqueued, ready for AudioQueueStart.
      private def create_mic_queue(path : String) : Nil
        asbd = mic_asbd
        @ext_file = open_ext_file(path, asbd)

        # All callback state rides through user_data: the callback Proc must be
        # closure-free or it cannot cross the C boundary ("passing a closure to
        # C is not allowed" at runtime). @mic_state retains the object so the GC
        # cannot collect it while the queue is live.
        state = MicQueueState.new(@ext_file, @mic_tap)
        @mic_state = state

        # AudioQueue C callback — runs on OS audio thread, must NOT allocate Crystal objects.
        # Uses C helper to construct AudioBufferList (avoids Crystal struct layout issues).
        cb = LibAudioToolbox::AudioQueueInputCallback.new do |user_data, aq, buffer_ref, _ts, _npd, _pd|
          st = user_data.as(MicQueueState)
          buf = buffer_ref.as(LibAudioToolbox::AudioQueueBuffer*)
          next if buf.value.audio_data_byte_size == 0

          LibAudioWriteHelper.ca_ext_audio_file_write_pcm(
            st.ext_file,
            buf.value.audio_data,
            buf.value.audio_data_byte_size,
            CHANNELS,
            CHANNELS * (BITS_PER_SAMPLE // 8)
          )
          if tap = st.tap
            bytes = Slice(UInt8).new(buf.value.audio_data.as(UInt8*), buf.value.audio_data_byte_size.to_i32, read_only: true)
            tap.call(bytes, CHANNELS, BITS_PER_SAMPLE, SAMPLE_RATE)
          end
          LibAudioToolbox.AudioQueueEnqueueBuffer(aq, buffer_ref, 0, Pointer(LibAudioToolbox::AudioStreamPacketDescription).null)
        end

        aq = Pointer(Void).null
        status = LibAudioToolbox.AudioQueueNewInput(
          pointerof(asbd), cb, state.as(Void*),
          nil, nil, 0_u32, pointerof(aq)
        )
        raise "AudioQueueNewInput failed: #{status}" unless status == 0
        @queue = aq

        if input_device_uid = @input_device_uid
          begin
            AudioQueue.set_current_input_device(@queue, input_device_uid)
          rescue ex : InputDeviceSelectionError
            dispose_unstarted_mic_queue
            raise ex
          end
        end

        NUM_BUFFERS.times do
          buf = Pointer(Void).null
          LibAudioToolbox.AudioQueueAllocateBuffer(@queue, BUFFER_SIZE, pointerof(buf))
          LibAudioToolbox.AudioQueueEnqueueBuffer(@queue, buf, 0_u32, Pointer(LibAudioToolbox::AudioStreamPacketDescription).null)
        end
      end

      private def dispose_unstarted_mic_queue : Nil
        unless @queue.null?
          LibAudioToolbox.AudioQueueDispose(@queue, true)
          @queue = Pointer(Void).null
        end

        unless @ext_file.null?
          LibAudioToolbox.ExtAudioFileDispose(@ext_file)
          @ext_file = Pointer(Void).null
        end
        @mic_state = nil
      end

      private def stop_mic_queue
        return if @queue.null?
        LibAudioToolbox.AudioQueueStop(@queue, false)
        LibAudioToolbox.AudioQueueDispose(@queue, true)
        @queue = Pointer(Void).null

        LibAudioToolbox.ExtAudioFileDispose(@ext_file) unless @ext_file.null?
        @ext_file = Pointer(Void).null
        @mic_state = nil
      end

      # ── Private: system audio tap ───────────────────────────────────────────

      private def start_system_tap(path : String)
        sys_file_ref = open_system_ext_file(path)
        tap = SystemAudioCapture.new
        begin
          tap.start do |frames, frame_count, channel_count|
            Recorder.write_system_frames(sys_file_ref, frames, frame_count, channel_count)
          end
        rescue ex
          dispose_system_ext_file
          raise ex
        end
        @system_tap = tap
      end

      # Opens the system WAV file here and begins the tap's creation and
      # start on a dispatch queue, after *start_first* (the microphone's
      # queue, or null) starts on the same dispatch job.
      private def begin_system_tap_start(path : String, start_first : LibAudioToolbox::AudioQueueRef) : Nil
        sys_file_ref = open_system_ext_file(path)
        tap = SystemAudioCapture.new
        begin
          tap.start_without_waiting(start_first) do |frames, frame_count, channel_count|
            Recorder.write_system_frames(sys_file_ref, frames, frame_count, channel_count)
          end
        rescue ex
          dispose_system_ext_file
          raise ex
        end
        @system_tap = tap
      end

      private def open_system_ext_file(path : String) : LibAudioToolbox::ExtAudioFileRef
        @sys_ext_file = open_ext_file(path, system_asbd)
      end

      # :nodoc:
      # Writes one tap buffer to the system WAV. Runs on the tap's real-time
      # thread, so it allocates nothing.
      def self.write_system_frames(sys_file_ref : LibAudioToolbox::ExtAudioFileRef, frames : Slice(Float32), frame_count : UInt32, channel_count : UInt32) : Nil
        bytes_per_frame = channel_count * 4_u32 # float32
        LibAudioWriteHelper.ca_ext_audio_file_write_pcm(
          sys_file_ref,
          frames.to_unsafe.as(Void*),
          frame_count * bytes_per_frame,
          channel_count,
          bytes_per_frame
        )
      end

      private def stop_system_tap
        @system_tap.try(&.stop)
        @system_tap = nil
        dispose_system_ext_file
      end

      private def dispose_system_ext_file : Nil
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
        asbd.bytes_per_packet = 2_u32 * 4_u32 # stereo * float32
        asbd.frames_per_packet = 1_u32
        asbd.bytes_per_frame = 2_u32 * 4_u32
        asbd.channels_per_frame = 2_u32
        asbd.bits_per_channel = 32_u32
        asbd.reserved = 0_u32
        asbd
      end

      private def open_ext_file(
        path : String,
        asbd : LibAudioToolbox::AudioStreamBasicDescription,
      ) : LibAudioToolbox::ExtAudioFileRef
        url = CF.file_url(path)
        file_type = path.ends_with?(".wav") ? LibAudioToolbox::AUDIO_FILE_WAVE_TYPE : LibAudioToolbox::AUDIO_FILE_M4A_TYPE

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
