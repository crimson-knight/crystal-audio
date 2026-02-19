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

// ── ObjC lifecycle helpers ────────────────────────────────────────────────────

// [[ClassName alloc] init] in one call
ca_id ca_alloc_init(const char *class_name) {
    Class cls = objc_getClass(class_name);
    if (!cls) return NULL;
    ca_id obj = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
    if (!obj) return NULL;
    return ((ca_id (*)(ca_id, SEL))objc_msgSend)(obj, sel_registerName("init"));
}
