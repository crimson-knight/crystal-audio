{% if flag?(:android) %}

# AAudio bindings — Android's native C audio API (API 26+).
#
# AAudio provides low-latency audio input/output with:
#   - Simple stream-based API (no Java/JNI required)
#   - Configurable sample rate, format, sharing mode
#   - Callback-driven I/O for real-time audio processing
#
# Reference: https://developer.android.com/ndk/guides/audio/aaudio/aaudio

@[Link("aaudio")]
lib LibAAudio
  # ── Result codes ──────────────────────────────────────────────────────────
  alias Result = Int32

  AAUDIO_OK                    =  0_i32
  AAUDIO_ERROR_BASE            = -900_i32
  AAUDIO_ERROR_DISCONNECTED    = -899_i32
  AAUDIO_ERROR_ILLEGAL_ARGUMENT = -898_i32
  AAUDIO_ERROR_INTERNAL        = -896_i32
  AAUDIO_ERROR_INVALID_STATE   = -895_i32
  AAUDIO_ERROR_INVALID_HANDLE  = -892_i32
  AAUDIO_ERROR_UNIMPLEMENTED   = -890_i32
  AAUDIO_ERROR_UNAVAILABLE     = -889_i32
  AAUDIO_ERROR_NO_FREE_HANDLES = -888_i32
  AAUDIO_ERROR_NO_MEMORY       = -887_i32
  AAUDIO_ERROR_NULL            = -886_i32
  AAUDIO_ERROR_TIMEOUT         = -885_i32
  AAUDIO_ERROR_WOULD_BLOCK     = -884_i32

  # ── Direction ─────────────────────────────────────────────────────────────
  AAUDIO_DIRECTION_OUTPUT = 0_i32
  AAUDIO_DIRECTION_INPUT  = 1_i32

  # ── Format ────────────────────────────────────────────────────────────────
  AAUDIO_FORMAT_UNSPECIFIED = 0_i32
  AAUDIO_FORMAT_PCM_I16     = 1_i32
  AAUDIO_FORMAT_PCM_FLOAT   = 2_i32
  AAUDIO_FORMAT_PCM_I24_PACKED = 3_i32
  AAUDIO_FORMAT_PCM_I32     = 4_i32

  # ── Sharing mode ──────────────────────────────────────────────────────────
  AAUDIO_SHARING_MODE_EXCLUSIVE = 0_i32
  AAUDIO_SHARING_MODE_SHARED    = 1_i32

  # ── Performance mode ──────────────────────────────────────────────────────
  AAUDIO_PERFORMANCE_MODE_NONE          = 10_i32
  AAUDIO_PERFORMANCE_MODE_POWER_SAVING  = 11_i32
  AAUDIO_PERFORMANCE_MODE_LOW_LATENCY   = 12_i32

  # ── Stream state ──────────────────────────────────────────────────────────
  AAUDIO_STREAM_STATE_UNINITIALIZED = 0_i32
  AAUDIO_STREAM_STATE_UNKNOWN       = 1_i32
  AAUDIO_STREAM_STATE_OPEN          = 2_i32
  AAUDIO_STREAM_STATE_STARTING      = 3_i32
  AAUDIO_STREAM_STATE_STARTED       = 4_i32
  AAUDIO_STREAM_STATE_PAUSING       = 5_i32
  AAUDIO_STREAM_STATE_PAUSED        = 6_i32
  AAUDIO_STREAM_STATE_FLUSHING      = 7_i32
  AAUDIO_STREAM_STATE_FLUSHED       = 8_i32
  AAUDIO_STREAM_STATE_STOPPING      = 9_i32
  AAUDIO_STREAM_STATE_STOPPED       = 10_i32
  AAUDIO_STREAM_STATE_CLOSING       = 11_i32
  AAUDIO_STREAM_STATE_CLOSED        = 12_i32
  AAUDIO_STREAM_STATE_DISCONNECTED  = 13_i32

  # ── Opaque types ──────────────────────────────────────────────────────────
  alias AAudioStreamBuilderRef = Void*
  alias AAudioStreamRef        = Void*

  # ── Data callback ─────────────────────────────────────────────────────────
  # Returns the number of frames that were written to the output buffer,
  # or AAUDIO_CALLBACK_RESULT_STOP to stop the stream.
  AAUDIO_CALLBACK_RESULT_CONTINUE = 0_i32
  AAUDIO_CALLBACK_RESULT_STOP    = 1_i32

  alias AAudioDataCallback = (AAudioStreamRef, Void*, Void*, Int32) -> Int32
  alias AAudioErrorCallback = (AAudioStreamRef, Void*, Result) ->

  # ── Stream builder ────────────────────────────────────────────────────────
  fun AAudio_createStreamBuilder(builder : AAudioStreamBuilderRef*) : Result
  fun AAudioStreamBuilder_setDirection(builder : AAudioStreamBuilderRef, direction : Int32)
  fun AAudioStreamBuilder_setSampleRate(builder : AAudioStreamBuilderRef, sample_rate : Int32)
  fun AAudioStreamBuilder_setChannelCount(builder : AAudioStreamBuilderRef, channel_count : Int32)
  fun AAudioStreamBuilder_setFormat(builder : AAudioStreamBuilderRef, format : Int32)
  fun AAudioStreamBuilder_setSharingMode(builder : AAudioStreamBuilderRef, sharing_mode : Int32)
  fun AAudioStreamBuilder_setPerformanceMode(builder : AAudioStreamBuilderRef, mode : Int32)
  fun AAudioStreamBuilder_setDataCallback(builder : AAudioStreamBuilderRef, callback : AAudioDataCallback, user_data : Void*)
  fun AAudioStreamBuilder_setErrorCallback(builder : AAudioStreamBuilderRef, callback : AAudioErrorCallback, user_data : Void*)
  fun AAudioStreamBuilder_openStream(builder : AAudioStreamBuilderRef, stream : AAudioStreamRef*) : Result
  fun AAudioStreamBuilder_delete(builder : AAudioStreamBuilderRef) : Result

  # ── Stream operations ─────────────────────────────────────────────────────
  fun AAudioStream_requestStart(stream : AAudioStreamRef) : Result
  fun AAudioStream_requestPause(stream : AAudioStreamRef) : Result
  fun AAudioStream_requestFlush(stream : AAudioStreamRef) : Result
  fun AAudioStream_requestStop(stream : AAudioStreamRef) : Result
  fun AAudioStream_close(stream : AAudioStreamRef) : Result

  # ── Stream queries ────────────────────────────────────────────────────────
  fun AAudioStream_getState(stream : AAudioStreamRef) : Int32
  fun AAudioStream_getSampleRate(stream : AAudioStreamRef) : Int32
  fun AAudioStream_getChannelCount(stream : AAudioStreamRef) : Int32
  fun AAudioStream_getFormat(stream : AAudioStreamRef) : Int32
  fun AAudioStream_getFramesPerBurst(stream : AAudioStreamRef) : Int32
  fun AAudioStream_getFramesRead(stream : AAudioStreamRef) : Int64
  fun AAudioStream_getFramesWritten(stream : AAudioStreamRef) : Int64
  fun AAudioStream_getXRunCount(stream : AAudioStreamRef) : Int32

  # ── Read/Write (non-callback mode) ────────────────────────────────────────
  fun AAudioStream_read(stream : AAudioStreamRef, buffer : Void*, num_frames : Int32, timeout_ns : Int64) : Result
  fun AAudioStream_write(stream : AAudioStreamRef, buffer : Void*, num_frames : Int32, timeout_ns : Int64) : Result
end

{% end %}
