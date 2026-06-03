// objc_helpers.c — typed wrappers for objc_msgSend
//
// Crystal cannot declare multiple fun aliases of the same C symbol with
// different return types in one lib block. This file provides typed C wrapper
// functions so Crystal binds them with simple, unambiguous names.
//
// ARM64: no objc_msgSend_fpret/_stret needed for these types.
// The C compiler routes args/return to correct registers per the ABI.

#include <objc/runtime.h>
#include <objc/message.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

// Use ca_id to avoid clash with POSIX id_t (unsigned int)
typedef void*    ca_id;
typedef void*    ca_sel;
typedef void**   ca_id_ptr;

// ── Returns ca_id (void*) ────────────────────────────────────────────────────

ca_id ca_msg_id(ca_id obj, ca_sel sel) {
    return ((ca_id (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

ca_id ca_msg_id_id(ca_id obj, ca_sel sel, ca_id a1) {
    return ((ca_id (*)(ca_id, ca_sel, ca_id))objc_msgSend)(obj, sel, a1);
}

ca_id ca_msg_id_id_id(ca_id obj, ca_sel sel, ca_id a1, ca_id a2) {
    return ((ca_id (*)(ca_id, ca_sel, ca_id, ca_id))objc_msgSend)(obj, sel, a1, a2);
}

// ── Returns void ─────────────────────────────────────────────────────────────

void ca_msg_void(ca_id obj, ca_sel sel) {
    ((void (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

void ca_msg_void_id(ca_id obj, ca_sel sel, ca_id a1) {
    ((void (*)(ca_id, ca_sel, ca_id))objc_msgSend)(obj, sel, a1);
}

// connect:to:format:  (three id args)
void ca_msg_void_id_id_id(ca_id obj, ca_sel sel, ca_id a1, ca_id a2, ca_id a3) {
    ((void (*)(ca_id, ca_sel, ca_id, ca_id, ca_id))objc_msgSend)(obj, sel, a1, a2, a3);
}

// scheduleFile:atTime:completionHandler: (file only; atTime + handler = nil)
void ca_msg_void_id_nil_nil(ca_id obj, ca_sel sel, ca_id a1) {
    ((void (*)(ca_id, ca_sel, ca_id, ca_id, ca_id))objc_msgSend)(obj, sel, a1, NULL, NULL);
}

// setVolume:, setOutputVolume:  (float arg)
void ca_msg_void_f32(ca_id obj, ca_sel sel, float value) {
    ((void (*)(ca_id, ca_sel, float))objc_msgSend)(obj, sel, value);
}

// ── Returns Bool ─────────────────────────────────────────────────────────────

bool ca_msg_bool(ca_id obj, ca_sel sel) {
    return ((bool (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

// startAndReturnError: — returns BOOL, takes NSError** out-parameter
bool ca_msg_bool_err(ca_id obj, ca_sel sel, ca_id_ptr out_err) {
    return ((bool (*)(ca_id, ca_sel, ca_id_ptr))objc_msgSend)(obj, sel, out_err);
}

// ── Returns Float32 ──────────────────────────────────────────────────────────

float ca_msg_f32(ca_id obj, ca_sel sel) {
    return ((float (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

// ── Returns UInt32 ───────────────────────────────────────────────────────────

uint32_t ca_msg_u32(ca_id obj, ca_sel sel) {
    return ((uint32_t (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

// ── Returns Float64 ──────────────────────────────────────────────────────────

double ca_msg_f64(ca_id obj, ca_sel sel) {
    return ((double (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

// ── Returns Int64 ───────────────────────────────────────────────────────────

int64_t ca_msg_i64(ca_id obj, ca_sel sel) {
    return ((int64_t (*)(ca_id, ca_sel))objc_msgSend)(obj, sel);
}

// ── Void with double arg ────────────────────────────────────────────────────

void ca_msg_void_f64(ca_id obj, ca_sel sel, double value) {
    ((void (*)(ca_id, ca_sel, double))objc_msgSend)(obj, sel, value);
}

// ── AVAudioFile: initForReading:error: ──────────────────────────────────────

// [[AVAudioFile alloc] initForReading:url error:&err]
// Returns the file object, or NULL on error.
ca_id ca_audio_file_open(ca_id url) {
    Class cls = objc_getClass("AVAudioFile");
    if (!cls) return NULL;
    ca_id obj = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
    if (!obj) return NULL;
    ca_id err = NULL;
    ca_id result = ((ca_id (*)(ca_id, SEL, ca_id, ca_id*))objc_msgSend)(
        obj, sel_registerName("initForReading:error:"), url, &err);
    return result; // NULL if error
}

// ── AVAudioTime helpers ─────────────────────────────────────────────────────

// [playerNode lastRenderTime] — returns AVAudioTime* (same as ca_msg_id)
// (use ca_msg_id directly)

// [AVAudioTime initWithSampleTime:atRate:] — creates an AVAudioTime from sample position
ca_id ca_audio_time_sample(int64_t sample_time, double sample_rate) {
    Class cls = objc_getClass("AVAudioTime");
    if (!cls) return NULL;
    ca_id obj = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
    if (!obj) return NULL;
    return ((ca_id (*)(ca_id, SEL, int64_t, double))objc_msgSend)(
        obj, sel_registerName("initWithSampleTime:atRate:"), sample_time, sample_rate);
}

// AVAudioTime.sampleTime (AVAudioSampleTime = Int64)
int64_t ca_audio_time_get_sample(ca_id time) {
    return ((int64_t (*)(ca_id, SEL))objc_msgSend)(time, sel_registerName("sampleTime"));
}

// AVAudioTime.sampleRate (double)
double ca_audio_time_get_rate(ca_id time) {
    return ((double (*)(ca_id, SEL))objc_msgSend)(time, sel_registerName("sampleRate"));
}

// AVAudioTime.isSampleTimeValid
bool ca_audio_time_valid(ca_id time) {
    return ((bool (*)(ca_id, SEL))objc_msgSend)(time, sel_registerName("isSampleTimeValid"));
}

// ── scheduleFile:atTime:completionHandler: with time param ──────────────────

void ca_msg_void_id_id_nil(ca_id obj, ca_sel sel, ca_id a1, ca_id a2) {
    ((void (*)(ca_id, ca_sel, ca_id, ca_id, ca_id))objc_msgSend)(obj, sel, a1, a2, NULL);
}

// ── NSDictionary / NSNumber helpers (for NowPlayingInfo) ────────────────────

// Create NSDictionary from parallel C arrays of keys and values
ca_id ca_nsdictionary_create(ca_id *keys, ca_id *values, uint32_t count) {
    Class cls = objc_getClass("NSDictionary");
    if (!cls) return NULL;
    return ((ca_id (*)(Class, SEL, ca_id*, ca_id*, uint64_t))objc_msgSend)(
        cls, sel_registerName("dictionaryWithObjects:forKeys:count:"),
        values, keys, (uint64_t)count);
}

// Wrap a double in NSNumber
ca_id ca_nsnumber_double(double value) {
    Class cls = objc_getClass("NSNumber");
    if (!cls) return NULL;
    return ((ca_id (*)(Class, SEL, double))objc_msgSend)(
        cls, sel_registerName("numberWithDouble:"), value);
}

// Wrap a long in NSNumber
ca_id ca_nsnumber_long(long value) {
    Class cls = objc_getClass("NSNumber");
    if (!cls) return NULL;
    return ((ca_id (*)(Class, SEL, long))objc_msgSend)(
        cls, sel_registerName("numberWithLong:"), value);
}

// ── ObjC lifecycle helpers ────────────────────────────────────────────────────

// [[ClassName alloc] init] in one call
ca_id ca_alloc_init(const char *class_name) {
    Class cls = objc_getClass(class_name);
    if (!cls) return NULL;
    ca_id obj = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
    if (!obj) return NULL;
    return ((ca_id (*)(ca_id, SEL))objc_msgSend)(obj, sel_registerName("init"));
}

// ── Looping playback: AVAudioFile -> AVAudioPCMBuffer + scheduleBuffer .loops ─
// Compiled WITHOUT -fobjc-arc (this is a .c file): alloc returns +1 (owned), so
// the buffer persists until released. We intentionally keep it alive for the
// player's lifetime (a scheduled looping buffer must outlive the schedule).

// Read an entire AVAudioFile into a freshly-allocated AVAudioPCMBuffer sized to
// the file (using its processingFormat). Returns the buffer, or NULL on error.
ca_id ca_pcm_buffer_for_file(ca_id file) {
    if (!file) return NULL;
    ca_id fmt = ((ca_id (*)(ca_id, SEL))objc_msgSend)(file, sel_registerName("processingFormat"));
    if (!fmt) return NULL;
    int64_t length = ((int64_t (*)(ca_id, SEL))objc_msgSend)(file, sel_registerName("length"));
    if (length <= 0) return NULL;
    Class cls = objc_getClass("AVAudioPCMBuffer");
    if (!cls) return NULL;
    ca_id buf = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
    if (!buf) return NULL;
    buf = ((ca_id (*)(ca_id, SEL, ca_id, uint32_t))objc_msgSend)(
        buf, sel_registerName("initWithPCMFormat:frameCapacity:"), fmt, (uint32_t)length);
    if (!buf) return NULL;
    ca_id err = NULL;
    bool ok = ((bool (*)(ca_id, SEL, ca_id, ca_id*))objc_msgSend)(
        file, sel_registerName("readIntoBuffer:error:"), buf, &err);
    return ok ? buf : NULL;
}

// Allocate an empty AVAudioPCMBuffer with the given format + capacity (the
// destination for offline manual rendering). Returns NULL on error.
ca_id ca_pcm_buffer_create(ca_id format, uint32_t frame_capacity) {
    if (!format) return NULL;
    Class cls = objc_getClass("AVAudioPCMBuffer");
    if (!cls) return NULL;
    ca_id buf = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
    if (!buf) return NULL;
    return ((ca_id (*)(ca_id, SEL, ca_id, uint32_t))objc_msgSend)(
        buf, sel_registerName("initWithPCMFormat:frameCapacity:"), format, frame_capacity);
}

// scheduleBuffer:atTime:options:completionHandler: with options =
// AVAudioPlayerNodeBufferLoops (1 << 0). atTime + handler = nil. The buffer
// loops indefinitely until the node is stopped.
void ca_schedule_buffer_loops(ca_id player, ca_id buffer) {
    ((void (*)(ca_id, SEL, ca_id, ca_id, uint64_t, ca_id))objc_msgSend)(
        player, sel_registerName("scheduleBuffer:atTime:options:completionHandler:"),
        buffer, NULL, (uint64_t)1 /* AVAudioPlayerNodeBufferLoops */, NULL);
}

// ── Offline (manual) rendering — deterministic, no audio device required ─────

// enableManualRenderingMode:format:maximumFrameCount:error: with mode =
// AVAudioEngineManualRenderingModeOffline (0). Must be called while the engine
// is stopped, before start. Returns true on success.
bool ca_engine_enable_manual_rendering(ca_id engine, ca_id format, uint32_t max_frames) {
    if (!engine || !format) return false;
    ca_id err = NULL;
    return ((bool (*)(ca_id, SEL, long, ca_id, uint32_t, ca_id*))objc_msgSend)(
        engine, sel_registerName("enableManualRenderingMode:format:maximumFrameCount:error:"),
        (long)0 /* Offline */, format, max_frames, &err);
}

// engine.manualRenderingFormat (AVAudioFormat*)
ca_id ca_engine_manual_rendering_format(ca_id engine) {
    if (!engine) return NULL;
    return ((ca_id (*)(ca_id, SEL))objc_msgSend)(engine, sel_registerName("manualRenderingFormat"));
}

// renderOffline:toBuffer:error: -> AVAudioEngineManualRenderingStatus (NSInteger;
// 0 = Success). Renders up to `frames` frames into out_buffer, whose frameLength
// is set to the count actually produced.
int64_t ca_engine_render_offline(ca_id engine, uint32_t frames, ca_id out_buffer) {
    if (!engine || !out_buffer) return -100;
    ca_id err = NULL;
    return ((long (*)(ca_id, SEL, uint32_t, ca_id, ca_id*))objc_msgSend)(
        engine, sel_registerName("renderOffline:toBuffer:error:"), frames, out_buffer, &err);
}

// ── PCM buffer inspection (verification) ─────────────────────────────────────

// AVAudioPCMBuffer.frameLength (AVAudioFrameCount = UInt32)
uint32_t ca_pcm_buffer_frame_length(ca_id buffer) {
    if (!buffer) return 0;
    return ((uint32_t (*)(ca_id, SEL))objc_msgSend)(buffer, sel_registerName("frameLength"));
}

// RMS amplitude of channel 0 over [start_frame, start_frame+count), reading
// buffer.floatChannelData[0]. Returns -1.0 if the buffer has no float data.
// Used to assert that a looped track keeps producing audio past its single-play
// length (a non-looping track is silent there).
double ca_pcm_buffer_rms(ca_id buffer, uint32_t start_frame, uint32_t count) {
    if (!buffer) return -1.0;
    float * const *chans = ((float * const * (*)(ca_id, SEL))objc_msgSend)(
        buffer, sel_registerName("floatChannelData"));
    if (!chans) return -1.0;
    uint32_t flen = ((uint32_t (*)(ca_id, SEL))objc_msgSend)(buffer, sel_registerName("frameLength"));
    if (start_frame >= flen) return 0.0;
    uint32_t end = start_frame + count;
    if (end > flen) end = flen;
    const float *data = chans[0];
    double sum = 0.0;
    uint32_t n = 0;
    for (uint32_t i = start_frame; i < end; i++) { double s = (double)data[i]; sum += s * s; n++; }
    return n ? sqrt(sum / (double)n) : 0.0;
}

// ── Playback position / duration (progress bar + countdown) ──────────────────

// AVAudioFormat.sampleRate (Hz). 0.0 on error.
double ca_format_sample_rate(ca_id format) {
    if (!format) return 0.0;
    return ((double (*)(ca_id, SEL))objc_msgSend)(format, sel_registerName("sampleRate"));
}

// Current playback position of an AVAudioPlayerNode in sample frames:
// [node playerTimeForNodeTime:[node lastRenderTime]].sampleTime. Returns -1 if
// the node hasn't started rendering yet (lastRenderTime / playerTime nil).
int64_t ca_player_node_position_samples(ca_id node) {
    if (!node) return -1;
    ca_id lrt = ((ca_id (*)(ca_id, SEL))objc_msgSend)(node, sel_registerName("lastRenderTime"));
    if (!lrt) return -1;
    ca_id pt = ((ca_id (*)(ca_id, SEL, ca_id))objc_msgSend)(
        node, sel_registerName("playerTimeForNodeTime:"), lrt);
    if (!pt) return -1;
    return ((int64_t (*)(ca_id, SEL))objc_msgSend)(pt, sel_registerName("sampleTime"));
}
