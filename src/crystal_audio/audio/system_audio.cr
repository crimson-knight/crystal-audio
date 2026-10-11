{% if flag?(:darwin) %}
  # System audio capture — binds ext/system_audio_tap.m
  #
  # Captures all system audio output (what you'd hear through the speakers)
  # without requiring a virtual audio driver.
  #
  # macOS 14.2+: Uses AudioHardwareCreateProcessTap + aggregate device.
  #   Permission: NSAudioCaptureUsageDescription (no Screen Recording needed)
  #
  # macOS 13.x fallback: Uses ScreenCaptureKit SCStream.
  #   Permission: Screen & System Audio Recording
  #
  # Both paths are wrapped by system_audio_tap.m; this file binds its C API.

  lib LibSystemAudioTap
    alias Handle = Void*
    alias OSStatus = Int32

    # Callback: called on the audio IOProc thread (real-time, no allocations!)
    # frames: interleaved float32 PCM at 48000 Hz (stereo)
    alias Callback = (Float32*, UInt32, UInt32, Void*) -> Void

    fun system_audio_tap_create(
      callback : Callback,
      context : Void*,
      out_error : OSStatus*,
    ) : Handle

    fun system_audio_tap_start(handle : Handle) : OSStatus
    fun system_audio_tap_stop(handle : Handle) : OSStatus
    fun system_audio_tap_destroy(handle : Handle)

    # Starts `queue_to_start_first` (when not null), then creates and starts a
    # tap, on a dispatch queue; returns a pending start, or null when none
    # could be allocated.
    fun system_audio_tap_start_async(
      callback : Callback,
      context : Void*,
      queue_to_start_first : Void*,
    ) : Void*
    fun system_audio_tap_wait_for_queue_start(pending_start : Void*) : OSStatus
    fun system_audio_tap_start_is_finished(pending_start : Void*) : Int32
    fun system_audio_tap_finish_start(
      pending_start : Void*,
      queue_status : OSStatus*,
      was_tap_attempted : Int32*,
      create_status : OSStatus*,
      start_status : OSStatus*,
    ) : Handle
  end

  module CrystalAudio
    # Captures system audio (what's playing through the speakers).
    # Runs the callback on a real-time audio thread — keep it allocation-free.
    #
    # Example:
    #   tap = SystemAudioCapture.new
    #   tap.start do |frames, frame_count, channels|
    #     # frames is a Slice(Float32) of interleaved PCM
    #   end
    #   sleep 10.seconds
    #   tap.stop
    #
    # Example — start without waiting for the audio server, then confirm:
    #
    #   tap = SystemAudioCapture.new
    #   tap.start_without_waiting do |frames, frame_count, channels|
    #     # ...
    #   end
    #   # ... other work on this thread while the tap starts ...
    #   result = tap.finish_start
    #   raise result.error_message.to_s unless result.started?
    class SystemAudioCapture
      SAMPLE_RATE   = 48_000.0
      CHANNEL_COUNT =    2_u32

      # kAudioHardwareUnspecifiedError ('what'), reported when the tap could
      # not be created and Core Audio gave no status of its own.
      UNSPECIFIED_ERROR = 0x77686174

      # How a start begun by `start_without_waiting` ended. Each status is an
      # OSStatus. The tap is created only after the queue given to
      # `start_without_waiting` (if any) started.
      struct StartResult
        # The input queue's AudioQueueStart status; 0 when none was given.
        getter queue_status : Int32
        # system_audio_tap_create's error; 0 when the tap was created or not attempted.
        getter create_status : Int32
        # system_audio_tap_start's status; 0 when the tap started or was not created.
        getter start_status : Int32
        # True when the queue (if any) started, so the tap's creation was tried.
        getter? tap_attempted : Bool

        def initialize(@queue_status : Int32, @tap_attempted : Bool, @create_status : Int32, @start_status : Int32)
        end

        # True when the queue (if any) and the tap both started.
        def started? : Bool
          queue_status == 0 && tap_attempted? && create_status == 0 && start_status == 0
        end

        # The message a synchronous start raises for the same tap failure, or
        # nil when the tap started or the queue failed first (the queue's
        # owner reports that).
        def error_message : String?
          return nil if started? || queue_status != 0
          return "system_audio_tap_create failed: OSStatus #{create_status}" unless create_status == 0

          "system_audio_tap_start failed: OSStatus #{start_status}"
        end
      end

      @handle : LibSystemAudioTap::Handle
      @box : Void*
      # A start running on a dispatch queue; null when none is pending.
      @pending_start : Void*
      # The result of a start that ran synchronously because no pending start
      # could be allocated; `finish_start` hands it out once.
      @synchronous_start_result : StartResult?

      # Kept as a class-level collection so GC doesn't collect live captures
      @@active = [] of SystemAudioCapture

      def initialize
        @handle = Pointer(Void).null
        @box = Pointer(Void).null
        @pending_start = Pointer(Void).null
      end

      # Start capturing system audio. The block receives a Slice(Float32) of
      # interleaved stereo samples at 48 kHz.
      # IMPORTANT: The block runs on a real-time thread. No Crystal allocations.
      def start(&callback : Slice(Float32), UInt32, UInt32 -> Nil)
        raise "Already started" unless idle?

        c_callback, boxed = retain_callback(callback)
        err = 0_i32
        handle = LibSystemAudioTap.system_audio_tap_create(c_callback, boxed, pointerof(err))
        if handle.null?
          release_callback
          raise "system_audio_tap_create failed: OSStatus #{err}"
        end

        status = LibSystemAudioTap.system_audio_tap_start(handle)
        unless status == 0
          LibSystemAudioTap.system_audio_tap_destroy(handle)
          release_callback
          raise "system_audio_tap_start failed: OSStatus #{status}"
        end
        @handle = handle
      end

      # Begins the tap's creation and start on a dispatch queue and returns at
      # once; the block is the same real-time callback `start` takes. When
      # *start_first* is an input AudioQueue, the same dispatch job starts that
      # queue first and creates the tap only after it started, the order in
      # which `Recorder` starts a microphone-plus-system recording. Follow with
      # `finish_start` (once), which reports how the start ended.
      def start_without_waiting(start_first : LibAudioToolbox::AudioQueueRef = Pointer(Void).null, &callback : Slice(Float32), UInt32, UInt32 -> Nil) : Nil
        raise "Already started" unless idle?

        c_callback, boxed = retain_callback(callback)
        pending_start = LibSystemAudioTap.system_audio_tap_start_async(c_callback, boxed, start_first)
        if pending_start.null?
          @synchronous_start_result = start_synchronously(c_callback, boxed, start_first)
        else
          @pending_start = pending_start
        end
      end

      # True while a start begun by `start_without_waiting` awaits `finish_start`.
      def start_pending? : Bool
        !@pending_start.null? || !@synchronous_start_result.nil?
      end

      # True when `finish_start` would return without waiting: no start is
      # pending, or the pending one has finished on its dispatch queue.
      def start_finished? : Bool
        pending_start = @pending_start
        return true if pending_start.null?

        LibSystemAudioTap.system_audio_tap_start_is_finished(pending_start) == 1
      end

      # Waits until the input queue given to `start_without_waiting` has
      # started, and returns its AudioQueueStart status (0 when no queue was
      # given or no start is pending). The tap may still be starting.
      def wait_for_queue_start : Int32
        if result = @synchronous_start_result
          return result.queue_status
        end
        pending_start = @pending_start
        return 0 if pending_start.null?

        LibSystemAudioTap.system_audio_tap_wait_for_queue_start(pending_start)
      end

      # Waits for the start begun by `start_without_waiting` and reports how it
      # ended. When the tap started, `active?` is true from here on; otherwise
      # nothing of the tap remains. Returns a started result with no queue when
      # no start is pending.
      def finish_start : StartResult
        result = take_start_result
        release_callback unless result.started?
        result
      end

      def stop
        finish_start if start_pending?
        return if @handle.null?
        LibSystemAudioTap.system_audio_tap_stop(@handle)
        LibSystemAudioTap.system_audio_tap_destroy(@handle)
        @handle = Pointer(Void).null
        release_callback
      end

      def active? : Bool
        !@handle.null?
      end

      private def idle? : Bool
        @handle.null? && !start_pending?
      end

      private def take_start_result : StartResult
        if result = @synchronous_start_result
          @synchronous_start_result = nil
          return result
        end

        pending_start = @pending_start
        return StartResult.new(0, true, 0, 0) if pending_start.null?

        @pending_start = Pointer(Void).null
        queue_status = 0
        was_tap_attempted = 0
        create_status = 0
        start_status = 0
        handle = LibSystemAudioTap.system_audio_tap_finish_start(
          pending_start, pointerof(queue_status), pointerof(was_tap_attempted),
          pointerof(create_status), pointerof(start_status)
        )
        @handle = handle
        StartResult.new(queue_status, was_tap_attempted == 1, create_status, start_status)
      end

      # The start `start_without_waiting` falls back to on this thread when the
      # C side could not allocate a pending start.
      private def start_synchronously(c_callback : LibSystemAudioTap::Callback, boxed : Void*, start_first : LibAudioToolbox::AudioQueueRef) : StartResult
        unless start_first.null?
          queue_status = LibAudioToolbox.AudioQueueStart(start_first, nil)
          return StartResult.new(queue_status, false, 0, 0) unless queue_status == 0
        end

        err = 0_i32
        handle = LibSystemAudioTap.system_audio_tap_create(c_callback, boxed, pointerof(err))
        return StartResult.new(0, true, err == 0 ? UNSPECIFIED_ERROR : err, 0) if handle.null?

        status = LibSystemAudioTap.system_audio_tap_start(handle)
        unless status == 0
          LibSystemAudioTap.system_audio_tap_destroy(handle)
          return StartResult.new(0, true, 0, status)
        end
        @handle = handle
        StartResult.new(0, true, 0, 0)
      end

      # Boxes *callback* for the C side and keeps this capture reachable from
      # the class-level list, so the GC keeps the box alive while the tap may
      # call it. Returns the closure-free C callback and the boxed context.
      private def retain_callback(callback : Proc(Slice(Float32), UInt32, UInt32, Nil)) : {LibSystemAudioTap::Callback, Void*}
        boxed = Box.box(callback)
        @box = boxed
        @@active << self

        c_callback = LibSystemAudioTap::Callback.new do |frames_ptr, frame_count, channel_count, ctx|
          blk = Box(Proc(Slice(Float32), UInt32, UInt32, Nil)).unbox(ctx)
          slice = Slice(Float32).new(frames_ptr, (frame_count * channel_count).to_i32, read_only: true)
          blk.call(slice, frame_count, channel_count)
        end
        {c_callback, boxed}
      end

      private def release_callback : Nil
        @@active.delete(self)
        @box = Pointer(Void).null
      end
    end
  end
{% end %}
