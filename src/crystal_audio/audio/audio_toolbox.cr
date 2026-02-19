{% if flag?(:darwin) %}

# AudioToolbox bindings: AudioQueue (microphone capture) + ExtAudioFile (WAV/AAC writing)
#
# AudioQueue uses plain C function pointer callbacks — no ObjC blocks needed.
# This is the recommended first-pass recording path and works with stock Crystal.
#
# ExtAudioFile handles format conversion automatically; we write PCM in and get
# any supported format out (WAV, AAC, AIFF, etc.).

@[Link(framework: "AudioToolbox")]
lib LibAudioToolbox
  alias OSStatus          = Int32
  alias AudioQueueRef     = Void*
  alias AudioQueueBufferRef = Void*
  alias ExtAudioFileRef   = Void*

  # ── AudioStreamBasicDescription (ASBD) ──────────────────────────────────────

  struct AudioStreamBasicDescription
    sample_rate        : Float64   # mSampleRate
    format_id          : UInt32    # mFormatID
    format_flags       : UInt32    # mFormatFlags
    bytes_per_packet   : UInt32    # mBytesPerPacket
    frames_per_packet  : UInt32    # mFramesPerPacket
    bytes_per_frame    : UInt32    # mBytesPerFrame
    channels_per_frame : UInt32    # mChannelsPerFrame
    bits_per_channel   : UInt32    # mBitsPerChannel
    reserved           : UInt32    # mReserved
  end

  # ── AudioBuffer / AudioBufferList ────────────────────────────────────────────

  struct AudioBuffer
    number_channels : UInt32   # mNumberChannels
    data_byte_size  : UInt32   # mDataByteSize
    data            : Void*    # mData
  end

  struct AudioBufferList
    number_buffers : UInt32       # mNumberBuffers
    buffers        : AudioBuffer[8]  # mBuffers (variable length; 8 covers stereo+)
  end

  # ── AudioTimeStamp (partial) ─────────────────────────────────────────────────

  struct AudioTimeStamp
    sample_time   : Float64
    host_time     : UInt64
    rate_scalar   : Float64
    word_clock_time : UInt64
    smpte_pad     : UInt8[24]  # SMPTETime struct
    flags         : UInt32
    reserved      : UInt32
  end

  # ── AudioStreamPacketDescription ─────────────────────────────────────────────

  struct AudioStreamPacketDescription
    start_offset                  : Int64
    variable_frames_in_packet     : UInt32
    data_byte_size                : UInt32
  end

  # ── AudioQueueBuffer ─────────────────────────────────────────────────────────

  struct AudioQueueBuffer
    audio_data_bytes_capacity    : UInt32   # const — set at allocation
    audio_data                   : Void*    # const ptr — read captured PCM here
    audio_data_byte_size         : UInt32   # set by callback: bytes captured
    user_data                    : Void*
    packet_description_capacity  : UInt32
    packet_descriptions          : Void*
    packet_description_count     : UInt32
  end

  # ── Format / file type constants ─────────────────────────────────────────────

  AUDIO_FORMAT_LINEAR_PCM          = 0x6C70636D_u32  # 'lpcm'
  AUDIO_FORMAT_MPEG4_AAC           = 0x61616320_u32  # 'aac '
  AUDIO_FORMAT_FLAG_IS_FLOAT       = 0x01_u32
  AUDIO_FORMAT_FLAG_IS_SIGNED_INT  = 0x04_u32
  AUDIO_FORMAT_FLAG_IS_PACKED      = 0x08_u32
  AUDIO_FORMAT_FLAG_IS_NON_INTERLEAVED = 0x20_u32
  AUDIO_FILE_WAVE_TYPE             = 0x57415645_u32  # 'WAVE'
  AUDIO_FILE_M4A_TYPE              = 0x6D346166_u32  # 'm4af'

  EXT_AUDIO_FILE_PROPERTY_CLIENT_DATA_FORMAT = 0x63666D74_u32  # 'cfmt'

  # ── AudioQueue input callback ────────────────────────────────────────────────
  # Plain C function pointer — no block bridge needed.
  # Called on the AudioQueue's internal OS thread.
  # CRITICAL: Never allocate Crystal objects in this callback.

  alias AudioQueueInputCallback = (
    Void*,                                    # inUserData
    AudioQueueRef,                            # inAQ
    AudioQueueBufferRef,                      # inBuffer
    AudioTimeStamp*,                          # inStartTime
    UInt32,                                   # inNumberPacketDescriptions
    AudioStreamPacketDescription*             # inPacketDescs (may be nil)
  ) -> Void

  # ── AudioQueue functions ─────────────────────────────────────────────────────

  fun AudioQueueNewInput(
    in_format             : AudioStreamBasicDescription*,
    in_callback_proc      : AudioQueueInputCallback,
    in_user_data          : Void*,
    in_callback_run_loop  : Void*,   # nil = AudioQueue manages own thread
    in_callback_run_loop_mode : Void*,  # nil = kCFRunLoopCommonModes
    in_flags              : UInt32,  # must be 0
    out_aq                : AudioQueueRef*
  ) : OSStatus

  fun AudioQueueAllocateBuffer(
    in_aq             : AudioQueueRef,
    in_buffer_byte_size : UInt32,
    out_buffer        : AudioQueueBufferRef*
  ) : OSStatus

  fun AudioQueueEnqueueBuffer(
    in_aq             : AudioQueueRef,
    in_buf            : AudioQueueBufferRef,
    in_num_packet_descs : UInt32,
    in_packet_descs   : AudioStreamPacketDescription*
  ) : OSStatus

  fun AudioQueueStart(in_aq : AudioQueueRef, in_start_time : Void*) : OSStatus
  fun AudioQueueStop(in_aq : AudioQueueRef, in_immediate : Bool) : OSStatus
  fun AudioQueueDispose(in_aq : AudioQueueRef, in_immediate : Bool) : OSStatus
  fun AudioQueueFreeBuffer(in_aq : AudioQueueRef, in_buf : AudioQueueBufferRef) : OSStatus

  # ── ExtAudioFile functions ───────────────────────────────────────────────────

  fun ExtAudioFileCreateWithURL(
    in_url           : LibCoreFoundation::CFURLRef,
    in_file_type     : UInt32,
    in_stream_desc   : AudioStreamBasicDescription*,
    in_channel_layout : Void*,  # nil
    in_flags         : UInt32,  # 0
    out_ext_file     : ExtAudioFileRef*
  ) : OSStatus

  fun ExtAudioFileSetProperty(
    in_ext_file       : ExtAudioFileRef,
    in_property_id    : UInt32,
    in_property_data_size : UInt32,
    in_property_data  : Void*
  ) : OSStatus

  fun ExtAudioFileWrite(
    in_ext_file    : ExtAudioFileRef,
    in_num_frames  : UInt32,
    io_data        : AudioBufferList*
  ) : OSStatus

  fun ExtAudioFileDispose(in_ext_file : ExtAudioFileRef) : OSStatus
end

{% end %}
