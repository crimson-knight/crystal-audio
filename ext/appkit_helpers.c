// appkit_helpers.c — typed C wrappers for AppKit ObjC APIs
//
// Crystal cannot express NSRect structs or mixed integer/struct message sends
// directly. This file provides helpers that handle the struct layout and
// correct ABI calls so Crystal only needs to pass plain C scalars.
//
// ARM64 macOS: structs <= 4 x 8 bytes are passed in registers (x0-x3),
// so NSRect (4 doubles = 32 bytes on 64-bit) is passed in registers d0-d3
// when it is the first argument after obj/sel. The C compiler handles this.

#include <objc/runtime.h>
#include <objc/message.h>
#include <stdbool.h>
#include <stdint.h>

// objc_autoreleasePoolPush/Pop are in libobjc but not exposed via a public
// C header; declare them explicitly to avoid implicit-function-declaration errors.
extern void *objc_autoreleasePoolPush(void);
extern void  objc_autoreleasePoolPop(void *pool);

typedef void* ca_id;
typedef void* ca_sel;

// NSRect = { NSPoint { x, y }, NSSize { w, h } } as CGFloat (double) fields
typedef struct {
    double x, y, w, h;
} CARect;

// ── NSString helpers ──────────────────────────────────────────────────────────

// [NSString stringWithUTF8String:cstr]
ca_id ca_nsstring(const char *cstr) {
    Class cls = objc_getClass("NSString");
    SEL sel = sel_registerName("stringWithUTF8String:");
    return ((ca_id (*)(Class, SEL, const char*))objc_msgSend)(cls, sel, cstr);
}

// [[NSNumber numberWithInteger:n]
ca_id ca_nsnumber_int(long n) {
    Class cls = objc_getClass("NSNumber");
    SEL sel = sel_registerName("numberWithInteger:");
    return ((ca_id (*)(Class, SEL, long))objc_msgSend)(cls, sel, n);
}

// ── NSApplication ─────────────────────────────────────────────────────────────

// [NSApplication sharedApplication]
ca_id ca_nsapp(void) {
    Class cls = objc_getClass("NSApplication");
    SEL sel = sel_registerName("sharedApplication");
    return ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel);
}

// [app setActivationPolicy:policy]  (NSInteger arg)
void ca_nsapp_set_policy(ca_id app, long policy) {
    SEL sel = sel_registerName("setActivationPolicy:");
    ((void (*)(ca_id, SEL, long))objc_msgSend)(app, sel, policy);
}

// [app activateIgnoringOtherApps:YES]
void ca_nsapp_activate(ca_id app) {
    SEL sel = sel_registerName("activateIgnoringOtherApps:");
    ((void (*)(ca_id, SEL, bool))objc_msgSend)(app, sel, true);
}

// [app run]
void ca_nsapp_run(ca_id app) {
    SEL sel = sel_registerName("run");
    ((void (*)(ca_id, SEL))objc_msgSend)(app, sel);
}

// [app stop:nil]
void ca_nsapp_stop(ca_id app) {
    SEL sel = sel_registerName("stop:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(app, sel, NULL);
}

// ── NSWindow ──────────────────────────────────────────────────────────────────

// [[NSWindow alloc] initWithContentRect:styleMask:backing:defer:]
// styleMask: NSWindowStyleMaskTitled(1)|Closable(2)|Miniaturizable(4)|Resizable(8) = 15
// backing:   NSBackingStoreBuffered = 2
// defer:     NO = 0
ca_id ca_nswindow_create(double x, double y, double w, double h,
                          unsigned long style_mask) {
    Class cls = objc_getClass("NSWindow");
    SEL alloc_sel = sel_registerName("alloc");
    ca_id win = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, alloc_sel);

    // NSRect is passed as struct in registers on ARM64
    typedef struct { double x, y, w, h; } NSRect;
    NSRect rect = { x, y, w, h };

    SEL init_sel = sel_registerName("initWithContentRect:styleMask:backing:defer:");
    return ((ca_id (*)(ca_id, SEL, NSRect, unsigned long, unsigned long, bool))objc_msgSend)(
        win, init_sel, rect, style_mask, 2UL, false
    );
}

// [window setTitle:nsstring]
void ca_nswindow_set_title(ca_id win, const char *title) {
    ca_id ns = ca_nsstring(title);
    SEL sel = sel_registerName("setTitle:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(win, sel, ns);
}

// [window makeKeyAndOrderFront:nil]
void ca_nswindow_show(ca_id win) {
    SEL sel = sel_registerName("makeKeyAndOrderFront:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(win, sel, NULL);
}

// [window center]
void ca_nswindow_center(ca_id win) {
    SEL sel = sel_registerName("center");
    ((void (*)(ca_id, SEL))objc_msgSend)(win, sel);
}

// ── NSView / content view ─────────────────────────────────────────────────────

// [window contentView]
ca_id ca_nswindow_content_view(ca_id win) {
    SEL sel = sel_registerName("contentView");
    return ((ca_id (*)(ca_id, SEL))objc_msgSend)(win, sel);
}

// [view addSubview:subview]
void ca_view_add_subview(ca_id view, ca_id subview) {
    SEL sel = sel_registerName("addSubview:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(view, sel, subview);
}

// ── NSTextField (label / editable) ───────────────────────────────────────────

// Create an NSTextField label (non-editable, non-bordered)
ca_id ca_nslabel_create(double x, double y, double w, double h) {
    Class cls = objc_getClass("NSTextField");
    SEL alloc_sel = sel_registerName("alloc");
    ca_id tf = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, alloc_sel);

    typedef struct { double x, y, w, h; } NSRect;
    NSRect rect = { x, y, w, h };
    SEL init_sel = sel_registerName("initWithFrame:");
    tf = ((ca_id (*)(ca_id, SEL, NSRect))objc_msgSend)(tf, init_sel, rect);

    // setEditable:NO
    SEL ed_sel = sel_registerName("setEditable:");
    ((void (*)(ca_id, SEL, bool))objc_msgSend)(tf, ed_sel, false);

    // setBordered:NO
    SEL brd_sel = sel_registerName("setBordered:");
    ((void (*)(ca_id, SEL, bool))objc_msgSend)(tf, brd_sel, false);

    // setDrawsBackground:NO
    SEL bg_sel = sel_registerName("setDrawsBackground:");
    ((void (*)(ca_id, SEL, bool))objc_msgSend)(tf, bg_sel, false);

    return tf;
}

// [label setStringValue:str]
void ca_nslabel_set_text(ca_id label, const char *text) {
    ca_id ns = ca_nsstring(text);
    SEL sel = sel_registerName("setStringValue:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(label, sel, ns);
}

// [label setAlignment:alignment]  (0=left, 1=right, 2=center)
void ca_nslabel_set_alignment(ca_id label, long alignment) {
    SEL sel = sel_registerName("setAlignment:");
    ((void (*)(ca_id, SEL, long))objc_msgSend)(label, sel, alignment);
}

// [label setFont:font]
void ca_nslabel_set_font(ca_id label, ca_id font) {
    SEL sel = sel_registerName("setFont:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(label, sel, font);
}

// ── NSFont ────────────────────────────────────────────────────────────────────

// [NSFont systemFontOfSize:size]
ca_id ca_nsfont_system(double size) {
    Class cls = objc_getClass("NSFont");
    SEL sel = sel_registerName("systemFontOfSize:");
    return ((ca_id (*)(Class, SEL, double))objc_msgSend)(cls, sel, size);
}

// [NSFont boldSystemFontOfSize:size]
ca_id ca_nsfont_bold(double size) {
    Class cls = objc_getClass("NSFont");
    SEL sel = sel_registerName("boldSystemFontOfSize:");
    return ((ca_id (*)(Class, SEL, double))objc_msgSend)(cls, sel, size);
}

// ── NSButton ─────────────────────────────────────────────────────────────────

// Create a push button with a title
ca_id ca_nsbutton_create(double x, double y, double w, double h,
                          const char *title) {
    Class cls = objc_getClass("NSButton");
    SEL alloc_sel = sel_registerName("alloc");
    ca_id btn = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, alloc_sel);

    typedef struct { double x, y, w, h; } NSRect;
    NSRect rect = { x, y, w, h };
    SEL init_sel = sel_registerName("initWithFrame:");
    btn = ((ca_id (*)(ca_id, SEL, NSRect))objc_msgSend)(btn, init_sel, rect);

    // setBezelStyle: NSBezelStyleRounded = 1
    SEL bezel_sel = sel_registerName("setBezelStyle:");
    ((void (*)(ca_id, SEL, long))objc_msgSend)(btn, bezel_sel, 1L);

    // setButtonType: NSButtonTypeMomentaryPushIn = 7
    SEL type_sel = sel_registerName("setButtonType:");
    ((void (*)(ca_id, SEL, long))objc_msgSend)(btn, type_sel, 7L);

    // setTitle:
    ca_id ns_title = ca_nsstring(title);
    SEL title_sel = sel_registerName("setTitle:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(btn, title_sel, ns_title);

    return btn;
}

// [button setTitle:str]
void ca_nsbutton_set_title(ca_id btn, const char *title) {
    ca_id ns = ca_nsstring(title);
    SEL sel = sel_registerName("setTitle:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(btn, sel, ns);
}

// [button setEnabled:flag]
void ca_nsbutton_set_enabled(ca_id btn, bool enabled) {
    SEL sel = sel_registerName("setEnabled:");
    ((void (*)(ca_id, SEL, bool))objc_msgSend)(btn, sel, enabled);
}

// ── NSSegmentedControl ────────────────────────────────────────────────────────

// Create an NSSegmentedControl with N segments
// segments: array of C strings, count: number of segments
ca_id ca_nssegmented_create(double x, double y, double w, double h,
                              const char **labels, int count) {
    Class cls = objc_getClass("NSSegmentedControl");
    SEL alloc_sel = sel_registerName("alloc");
    ca_id sc = ((ca_id (*)(Class, SEL))objc_msgSend)(cls, alloc_sel);

    typedef struct { double x, y, w, h; } NSRect;
    NSRect rect = { x, y, w, h };
    SEL init_sel = sel_registerName("initWithFrame:");
    sc = ((ca_id (*)(ca_id, SEL, NSRect))objc_msgSend)(sc, init_sel, rect);

    // setSegmentCount:
    SEL count_sel = sel_registerName("setSegmentCount:");
    ((void (*)(ca_id, SEL, long))objc_msgSend)(sc, count_sel, (long)count);

    // setLabel:forSegment: for each segment
    SEL label_sel = sel_registerName("setLabel:forSegment:");
    for (int i = 0; i < count; i++) {
        ca_id ns_label = ca_nsstring(labels[i]);
        ((void (*)(ca_id, SEL, ca_id, long))objc_msgSend)(sc, label_sel, ns_label, (long)i);
    }

    // setSelectedSegment:0
    SEL sel_sel = sel_registerName("setSelectedSegment:");
    ((void (*)(ca_id, SEL, long))objc_msgSend)(sc, sel_sel, 0L);

    return sc;
}

// [sc selectedSegment] → long
long ca_nssegmented_selected(ca_id sc) {
    SEL sel = sel_registerName("selectedSegment");
    return ((long (*)(ca_id, SEL))objc_msgSend)(sc, sel);
}

// ── NSColor ───────────────────────────────────────────────────────────────────

ca_id ca_nscolor_red(void) {
    Class cls = objc_getClass("NSColor");
    SEL sel = sel_registerName("redColor");
    return ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel);
}

ca_id ca_nscolor_label(void) {
    Class cls = objc_getClass("NSColor");
    SEL sel = sel_registerName("labelColor");
    return ((ca_id (*)(Class, SEL))objc_msgSend)(cls, sel);
}

// [label setTextColor:color]
void ca_nslabel_set_color(ca_id label, ca_id color) {
    SEL sel = sel_registerName("setTextColor:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(label, sel, color);
}

// ── NSTimer — dispatch_after on main queue ───────────────────────────────────
// We use GCD dispatch_after for timer ticks since NSTimer requires a target/action
// ObjC class which is complex to set up from Crystal.

// dispatch_queue_t dispatch_get_main_queue(void)
// dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block)
// We just need to run callbacks from C — Crystal uses a background fiber + sleep.

// ── Utility: post an empty NSEvent to wake NSApplication run loop ─────────────

void ca_nsapp_post_empty_event(ca_id app) {
    // Post a dummy application-defined event to wake the run loop so
    // a background thread can signal the main thread to update the UI.
    Class cls = objc_getClass("NSEvent");
    SEL sel = sel_registerName("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:");

    typedef struct { double x, y; } NSPoint;
    NSPoint loc = { 0.0, 0.0 };

    // NSEventTypeApplicationDefined = 15
    ca_id event = ((ca_id (*)(Class, SEL, long, NSPoint, unsigned long, double, long, ca_id, short, long, long))objc_msgSend)(
        cls, sel,
        15L,         // type: NSEventTypeApplicationDefined
        loc,         // location
        0UL,         // modifierFlags
        0.0,         // timestamp
        0L,          // windowNumber
        NULL,        // context (deprecated, nil)
        0,           // subtype
        0L,          // data1
        0L           // data2
    );

    if (event) {
        SEL post_sel = sel_registerName("postEvent:atStart:");
        ((void (*)(ca_id, SEL, ca_id, bool))objc_msgSend)(app, post_sel, event, false);
    }
}

// ── Button action target (C-side) ────────────────────────────────────────────
//
// We create a proper ObjC class "CAAudioTarget" in C rather than from Crystal,
// which avoids ARC/weak-reference compatibility issues.
//
// The class stores one function pointer (the Crystal callback) and calls it
// when the button fires.

typedef void (*ca_button_callback_fn)(void);

// Global slot for the button callback (one button for now)
static ca_button_callback_fn g_record_callback = NULL;

// IMP for "recordAction:" method — called by AppKit when button is clicked
static void ca_audio_target_record_action(ca_id self, SEL _cmd, ca_id sender) {
    if (g_record_callback) {
        g_record_callback();
    }
}

// Register the ObjC class and return an instance.
// Returns NULL on failure. Thread-safe (call once from main thread at startup).
ca_id ca_button_target_create(ca_button_callback_fn callback) {
    g_record_callback = callback;

    // Check if already registered (e.g. if called twice)
    Class existing = objc_getClass("CAAudioTarget");
    if (!existing) {
        Class ns_object = objc_getClass("NSObject");
        Class cls = objc_allocateClassPair(ns_object, "CAAudioTarget", 0);
        if (!cls) return NULL;

        SEL action_sel = sel_registerName("recordAction:");
        // "v@:@" = void, id self, SEL cmd, id sender
        class_addMethod(cls, action_sel,
                        (IMP)ca_audio_target_record_action, "v@:@");
        objc_registerClassPair(cls);
        existing = cls;
    }

    // [[CAAudioTarget alloc] init]
    ca_id obj = ((ca_id (*)(Class, SEL))objc_msgSend)(existing,
                    sel_registerName("alloc"));
    return ((ca_id (*)(ca_id, SEL))objc_msgSend)(obj,
                    sel_registerName("init"));
}

// Wire up button target/action using the C-created target
void ca_button_set_action(ca_id btn, ca_id target) {
    SEL set_target = sel_registerName("setTarget:");
    ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(btn, set_target, target);

    SEL set_action = sel_registerName("setAction:");
    SEL action_sel = sel_registerName("recordAction:");
    ((void (*)(ca_id, SEL, SEL))objc_msgSend)(btn, set_action, action_sel);
}

// ── NSRunLoop / display ────────────────────────────────────────────────────────

// Force a view to display (redraw) immediately — call from background threads
// after updating label text. Safe: NSTextField setStringValue is atomic for
// value setting; the display call should be on the main thread only.
void ca_view_set_needs_display(ca_id view) {
    SEL sel = sel_registerName("setNeedsDisplay:");
    ((void (*)(ca_id, SEL, bool))objc_msgSend)(view, sel, true);
}

// ── Non-blocking event pump ───────────────────────────────────────────────────

// Drain all pending NSEvents without blocking.  Call this in a tight loop
// (with a sleep between iterations) to drive the AppKit run loop from Crystal.
void ca_nsapp_pump_events(ca_id app) {
    void *pool = objc_autoreleasePoolPush();

    // NSEventMaskAny = ~0ULL
    unsigned long mask = ~0ULL;

    // [NSDate distantPast]
    Class nsdate_cls = objc_getClass("NSDate");
    SEL dp_sel = sel_registerName("distantPast");
    ca_id distant_past = ((ca_id (*)(Class, SEL))objc_msgSend)(nsdate_cls, dp_sel);

    // NSDefaultRunLoopMode string
    ca_id mode = ca_nsstring("kCFRunLoopDefaultMode");

    SEL next_sel = sel_registerName("nextEventMatchingMask:untilDate:inMode:dequeue:");
    SEL send_sel = sel_registerName("sendEvent:");

    ca_id event;
    while ((event = ((ca_id (*)(ca_id, SEL, unsigned long, ca_id, ca_id, bool))objc_msgSend)(
                app, next_sel, mask, distant_past, mode, true)) != NULL) {
        ((void (*)(ca_id, SEL, ca_id))objc_msgSend)(app, send_sel, event);
    }

    // Flush pending redraws
    SEL upd_sel = sel_registerName("updateWindows");
    ((void (*)(ca_id, SEL))objc_msgSend)(app, upd_sel);

    objc_autoreleasePoolPop(pool);
}

// ── Window close observer ─────────────────────────────────────────────────────

// Global flag set to true when the observed window posts NSWindowWillCloseNotification.
static bool g_window_should_close = false;

// IMP for "windowWillClose:" notification handler
static void ca_window_close_observer_handler(ca_id self, SEL _cmd, ca_id notification) {
    g_window_should_close = true;
}

// Register "CAWindowCloseObserver" ObjC class (same pattern as CAAudioTarget)
// and observe NSWindowWillCloseNotification for the given window.
void ca_observe_window_close(ca_id window) {
    Class existing = objc_getClass("CAWindowCloseObserver");
    if (!existing) {
        Class ns_object = objc_getClass("NSObject");
        Class cls = objc_allocateClassPair(ns_object, "CAWindowCloseObserver", 0);
        if (!cls) return;

        SEL handler_sel = sel_registerName("windowWillClose:");
        // "v@:@" = void, id self, SEL cmd, id notification
        class_addMethod(cls, handler_sel,
                        (IMP)ca_window_close_observer_handler, "v@:@");
        objc_registerClassPair(cls);
        existing = cls;
    }

    // [[CAWindowCloseObserver alloc] init]
    ca_id observer = ((ca_id (*)(Class, SEL))objc_msgSend)(existing,
                        sel_registerName("alloc"));
    observer = ((ca_id (*)(ca_id, SEL))objc_msgSend)(observer,
                    sel_registerName("init"));

    // [[NSNotificationCenter defaultCenter]
    //     addObserver:observer
    //     selector:@selector(windowWillClose:)
    //     name:NSWindowWillCloseNotification
    //     object:window]
    Class nc_cls = objc_getClass("NSNotificationCenter");
    SEL dc_sel = sel_registerName("defaultCenter");
    ca_id nc = ((ca_id (*)(Class, SEL))objc_msgSend)(nc_cls, dc_sel);

    ca_id notif_name = ca_nsstring("NSWindowWillCloseNotification");
    SEL add_sel = sel_registerName("addObserver:selector:name:object:");
    SEL handler_sel = sel_registerName("windowWillClose:");
    ((void (*)(ca_id, SEL, ca_id, SEL, ca_id, ca_id))objc_msgSend)(
        nc, add_sel, observer, handler_sel, notif_name, window);
}

// ── Window close flag accessor ────────────────────────────────────────────────

bool ca_window_should_close(void) {
    return g_window_should_close;
}
