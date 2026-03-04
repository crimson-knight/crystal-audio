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
