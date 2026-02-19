# whisper.cpp FFI bindings for Crystal.
#
# Links against libwhisper (from whisper.cpp build).
# Build whisper.cpp: see README.md#transcription-setup
#
# whisper.cpp requires: float32 PCM at 16000 Hz mono.
# All other formats must be resampled before passing to whisper_full.
#
# This file is not platform-gated — whisper.cpp runs on macOS, Linux, and
# Windows. iOS support requires the crystal-alpha compiler for cross-compilation.

@[Link("whisper")]
lib LibWhisper
  # ── Opaque handles ────────────────────────────────────────────────────────

  type Context = Void
  type State   = Void
  alias Token  = Int32

  # ── Sampling strategy ─────────────────────────────────────────────────────

  enum SamplingStrategy : Int32
    Greedy     = 0
    BeamSearch = 1
  end

  # ── Context initialization params ─────────────────────────────────────────

  struct ContextParams
    use_gpu              : Bool
    flash_attn           : Bool
    gpu_device           : Int32
    dtw_token_timestamps : Bool
    dtw_aheads_preset    : Int32
    dtw_n_top            : Int32
    dtw_aheads_n_heads   : LibC::SizeT
    dtw_aheads_heads     : Void*
    dtw_mem_size         : LibC::SizeT
  end

  # ── VAD params ────────────────────────────────────────────────────────────

  struct VadParams
    threshold               : Float32
    min_speech_duration_ms  : Int32
    min_silence_duration_ms : Int32
    max_speech_duration_s   : Float32
    speech_pad_ms           : Int32
    samples_overlap         : Float32
  end

  # ── Callback types ────────────────────────────────────────────────────────

  alias NewSegmentCallback   = (Context*, State*, Int32, Void*) -> Void
  alias ProgressCallback     = (Context*, State*, Int32, Void*) -> Void
  alias EncoderBeginCallback = (Context*, State*, Void*) -> Bool
  alias AbortCallback        = (Void*) -> Bool

  # ── Full params struct ────────────────────────────────────────────────────
  # Passed BY VALUE to whisper_full. Crystal handles this correctly.

  struct FullParams
    strategy       : SamplingStrategy
    n_threads      : Int32
    n_max_text_ctx : Int32
    offset_ms      : Int32
    duration_ms    : Int32

    translate        : Bool
    no_context       : Bool
    no_timestamps    : Bool
    single_segment   : Bool
    print_special    : Bool
    print_progress   : Bool
    print_realtime   : Bool
    print_timestamps : Bool

    token_timestamps : Bool
    thold_pt         : Float32
    thold_ptsum      : Float32
    max_len          : Int32
    split_on_word    : Bool
    max_tokens       : Int32

    debug_mode  : Bool
    audio_ctx   : Int32
    tdrz_enable : Bool

    suppress_regex       : LibC::Char*
    initial_prompt       : LibC::Char*
    carry_initial_prompt : Bool
    prompt_tokens        : Token*
    prompt_n_tokens      : Int32

    language        : LibC::Char*
    detect_language : Bool

    suppress_blank : Bool
    suppress_nst   : Bool

    temperature     : Float32
    max_initial_ts  : Float32
    length_penalty  : Float32
    temperature_inc : Float32
    entropy_thold   : Float32
    logprob_thold   : Float32
    no_speech_thold : Float32

    greedy_best_of        : Int32
    beam_search_beam_size : Int32
    beam_search_patience  : Float32

    new_segment_callback             : NewSegmentCallback
    new_segment_callback_user_data   : Void*
    progress_callback                : ProgressCallback
    progress_callback_user_data      : Void*
    encoder_begin_callback           : EncoderBeginCallback
    encoder_begin_callback_user_data : Void*
    abort_callback                   : AbortCallback
    abort_callback_user_data         : Void*

    grammar_rules   : Void*
    n_grammar_rules : LibC::SizeT
    i_start_rule    : LibC::SizeT
    grammar_penalty : Float32

    vad            : Bool
    vad_model_path : LibC::Char*
    vad_params     : VadParams
  end

  # ── Context lifecycle ─────────────────────────────────────────────────────

  fun whisper_context_default_params : ContextParams

  fun whisper_init_from_file_with_params(
    path_model : LibC::Char*,
    params     : ContextParams
  ) : Context*

  fun whisper_free(ctx : Context*)

  # ── Params init ───────────────────────────────────────────────────────────

  fun whisper_full_default_params(strategy : SamplingStrategy) : FullParams

  # ── Transcription ─────────────────────────────────────────────────────────
  # samples: float32 PCM at 16000 Hz mono

  fun whisper_full(
    ctx      : Context*,
    params   : FullParams,
    samples  : Float32*,
    n_samples : Int32
  ) : Int32

  # ── Result extraction ─────────────────────────────────────────────────────

  fun whisper_full_n_segments(ctx : Context*) : Int32
  fun whisper_full_get_segment_text(ctx : Context*, i_segment : Int32) : LibC::Char*
  fun whisper_full_get_segment_t0(ctx : Context*, i_segment : Int32) : Int64
  fun whisper_full_get_segment_t1(ctx : Context*, i_segment : Int32) : Int64
  fun whisper_full_get_segment_speaker_turn_next(ctx : Context*, i_segment : Int32) : Bool

  # ── Utility ───────────────────────────────────────────────────────────────

  fun whisper_print_system_info : LibC::Char*
  fun whisper_is_multilingual(ctx : Context*) : Int32
end

module CrystalAudio
  module Transcription
    # Centiseconds → milliseconds conversion factor for whisper timestamps
    TIMESTAMP_UNIT_MS = 10_i64

    struct Segment
      getter text              : String
      getter t0_ms             : Int64
      getter t1_ms             : Int64
      getter speaker_turn_next : Bool

      def initialize(@text, @t0_ms, @t1_ms, @speaker_turn_next = false)
      end

      def duration_ms : Int64
        @t1_ms - @t0_ms
      end

      def to_s(io : IO)
        mins = @t0_ms // 60_000
        secs = (@t0_ms % 60_000) // 1000
        ms   = @t0_ms % 1000
        io << "[%02d:%02d.%03d] %s" % {mins, secs, ms, @text.strip}
      end
    end

    # Configuration for a single transcription call
    struct TranscribeConfig
      property language        : String  = "en"
      property translate       : Bool    = false
      property no_context      : Bool    = false
      property single_segment  : Bool    = false
      property max_tokens      : Int32   = 0
      property no_speech_thold : Float32 = 0.6_f32
      property n_threads       : Int32   = 4
      property use_beam_search : Bool    = false
      property beam_size       : Int32   = 5
      property greedy_best_of  : Int32   = 5
      property initial_prompt  : String? = nil
      property vad             : Bool    = false
      property vad_model_path  : String? = nil
    end

    # Wraps a loaded whisper model. Reuse across multiple transcription calls.
    class WhisperContext
      @ctx : LibWhisper::Context*

      def initialize(model_path : String, use_gpu : Bool = true)
        raise "Model not found: #{model_path}" unless File.exists?(model_path)

        ctx_params = LibWhisper.whisper_context_default_params
        ctx_params.use_gpu = use_gpu

        @ctx = LibWhisper.whisper_init_from_file_with_params(model_path.to_unsafe, ctx_params)
        raise "Failed to load whisper model: #{model_path}" if @ctx.null?
      end

      def finalize
        LibWhisper.whisper_free(@ctx) unless @ctx.null?
      end

      # Transcribe float32 PCM samples (16000 Hz mono).
      # Yields each Segment as the model processes it.
      def transcribe(samples : Slice(Float32), config : TranscribeConfig = TranscribeConfig.new, &block : Segment ->)
        params = build_params(config)

        # Box the block for the C callback (GC safety via class variable)
        boxed = Box.box(block)
        @@_active_boxes << boxed

        params.new_segment_callback = ->(ctx : LibWhisper::Context*, _state : LibWhisper::State*, n_new : Int32, user_data : Void*) {
          cb = Box(typeof(block)).unbox(user_data)
          total = LibWhisper.whisper_full_n_segments(ctx)
          start_idx = total - n_new
          start_idx.upto(total - 1) do |i|
            text = String.new(LibWhisper.whisper_full_get_segment_text(ctx, i))
            t0 = LibWhisper.whisper_full_get_segment_t0(ctx, i) * TIMESTAMP_UNIT_MS
            t1 = LibWhisper.whisper_full_get_segment_t1(ctx, i) * TIMESTAMP_UNIT_MS
            turn = LibWhisper.whisper_full_get_segment_speaker_turn_next(ctx, i)
            cb.call(Segment.new(text, t0, t1, turn))
          end
        }
        params.new_segment_callback_user_data = boxed

        result = LibWhisper.whisper_full(@ctx, params, samples.to_unsafe, samples.size)
        @@_active_boxes.delete(boxed)

        raise "whisper_full failed with code #{result}" if result != 0
      end

      # Non-block variant: returns all segments after processing.
      def transcribe(samples : Slice(Float32), config : TranscribeConfig = TranscribeConfig.new) : Array(Segment)
        segs = [] of Segment
        transcribe(samples, config) { |s| segs << s }
        segs
      end

      # GC root collection for active callback boxes
      @@_active_boxes = [] of Void*

      private def build_params(config : TranscribeConfig) : LibWhisper::FullParams
        strategy = config.use_beam_search ?
          LibWhisper::SamplingStrategy::BeamSearch :
          LibWhisper::SamplingStrategy::Greedy

        params = LibWhisper.whisper_full_default_params(strategy)
        params.n_threads        = config.n_threads
        params.language         = config.language.to_unsafe
        params.translate        = config.translate
        params.no_context       = config.no_context
        params.single_segment   = config.single_segment
        params.max_tokens       = config.max_tokens
        params.no_speech_thold  = config.no_speech_thold
        params.print_progress   = false
        params.print_realtime   = false

        if prompt = config.initial_prompt
          params.initial_prompt = prompt.to_unsafe
        end

        if config.use_beam_search
          params.beam_search_beam_size = config.beam_size
        else
          params.greedy_best_of = config.greedy_best_of
        end

        params
      end
    end

    # Near-real-time transcription for dictation via chunked audio processing.
    # Push PCM samples as they arrive; get Segment callbacks as text is recognized.
    class Streamer
      SAMPLE_RATE     = 16_000
      STEP_MS         =  3_000  # process every 3 seconds
      WINDOW_MS       =  5_000  # sliding window of 5 seconds
      OVERLAP_MS      =    500  # 500ms overlap for continuity
      STEP_SAMPLES    = SAMPLE_RATE * STEP_MS   // 1000
      WINDOW_SAMPLES  = SAMPLE_RATE * WINDOW_MS // 1000
      OVERLAP_SAMPLES = SAMPLE_RATE * OVERLAP_MS // 1000

      @ctx             : WhisperContext
      @ring_buffer     : Array(Float32)
      @overlap_buffer  : Array(Float32)
      @callback        : Segment ->
      @config          : TranscribeConfig

      def initialize(model_path : String, &callback : Segment ->)
        @ctx = WhisperContext.new(model_path)
        @ring_buffer = [] of Float32
        @overlap_buffer = [] of Float32
        @callback = callback

        @config = TranscribeConfig.new.tap do |c|
          c.single_segment  = true   # one segment per chunk
          c.no_context      = true   # no cross-chunk hallucination
          c.max_tokens      = 32
          c.no_speech_thold = 0.6_f32
          c.use_beam_search = false
          c.greedy_best_of  = 1      # lowest latency
          c.n_threads       = 4
        end
      end

      # Push new PCM samples (Float32, 16 kHz mono). Thread-safe via Mutex.
      def push(samples : Slice(Float32))
        @ring_buffer.concat(samples.to_a)
        return unless @ring_buffer.size >= STEP_SAMPLES

        working = @overlap_buffer + @ring_buffer
        working = working.last(WINDOW_SAMPLES) if working.size > WINDOW_SAMPLES

        slice = Slice(Float32).new(working.size) { |i| working[i] }
        @ctx.transcribe(slice, @config) { |seg| @callback.call(seg) }

        @overlap_buffer = @ring_buffer.last([OVERLAP_SAMPLES, @ring_buffer.size].min)
        @ring_buffer.clear
      end

      # Flush remaining audio
      def flush
        return if @ring_buffer.empty?
        all = @overlap_buffer + @ring_buffer
        slice = Slice(Float32).new(all.size) { |i| all[i] }
        @ctx.transcribe(slice, @config) { |seg| @callback.call(seg) }
        @ring_buffer.clear
        @overlap_buffer.clear
      end
    end
  end
end
