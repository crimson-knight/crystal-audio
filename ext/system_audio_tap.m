/*
 * system_audio_tap.m
 *
 * Captures system-wide audio output on macOS using the Core Audio Process
 * Tap API (requires macOS 14.2+, Sonoma).  A ScreenCaptureKit-based path is
 * compiled in as a fallback for macOS 13.0 (Ventura) when the Process Tap
 * API is unavailable at runtime.
 *
 * Prerequisites
 * -------------
 *   • macOS 14.2+ for AudioHardwareCreateProcessTap / CATapDescription.
 *   • macOS 13.0+ for the SCStreamAudio fallback (ScreenCaptureKit).
 *   • Info.plist key NSAudioCaptureUsageDescription (or
 *     com.apple.developer.audio-recording-permission).
 *   • Frameworks: CoreAudio, AudioToolbox, ScreenCaptureKit, Foundation.
 *
 * The pure-C API surface (below) is what Crystal binds via `lib`.
 * Everything ObjC-specific is hidden inside this translation unit.
 *
 * Real-time safety
 * ----------------
 * The AudioDeviceIOProc / IOBlock is called on a real-time audio thread.
 * It MUST NOT allocate memory, take locks, call ObjC/Swift, or enter Crystal.
 * It calls handle->callback — a plain C function pointer — with a pointer
 * into the already-allocated AudioBufferList memory.
 */

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

/* AudioHardwareTapping.h and CATapDescription.h provide the Process Tap API
 * (AudioHardwareCreateProcessTap, AudioHardwareDestroyProcessTap, etc.) and
 * the CATapDescription class.  Both headers are ObjC-only and are guarded by
 * __OBJC__ in the SDK; since this is a .m file __OBJC__ is always defined. */
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

#import <ScreenCaptureKit/ScreenCaptureKit.h>

#import <AudioToolbox/AudioToolbox.h>

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

/* =========================================================================
 * Public C types
 * ====================================================================== */

/*
 * SystemAudioCallback
 *
 * Called from the real-time IOProc with interleaved float32 PCM frames.
 *   frames        — pointer into the driver buffer (valid only during call)
 *   frame_count   — number of sample frames
 *   channel_count — number of interleaved channels (typically 2)
 *   context       — the opaque pointer supplied at tap creation time
 */
typedef void (*SystemAudioCallback)(const float   *frames,
                                    uint32_t       frame_count,
                                    uint32_t       channel_count,
                                    void          *context);

/*
 * SystemAudioTapHandle
 *
 * Opaque (from Crystal's perspective) heap object that owns all Core Audio
 * resources for one active system-audio tap.
 */
typedef struct SystemAudioTapHandle {
    AudioObjectID         tap_id;              /* from AudioHardwareCreateProcessTap */
    AudioObjectID         aggregate_device_id; /* aggregate wrapping the tap */
    AudioDeviceIOProcID   io_proc_id;          /* registered IOProc handle */
    SystemAudioCallback   callback;            /* Crystal-side C callback */
    void                 *context;             /* opaque Crystal context */
    uint32_t              channel_count;       /* channels in use */
    double                sample_rate;         /* nominal sample rate */
} SystemAudioTapHandle;

/* =========================================================================
 * ScreenCaptureKit fallback — macOS 13+ only
 *
 * We need a delegate object that conforms to SCStreamOutput so that
 * SCStream can deliver audio sample buffers to us on macOS 13/Ventura when
 * the Process Tap API is not available.
 * ====================================================================== */

API_AVAILABLE(macos(13.0))
@interface CrystalAudioStreamDelegate : NSObject <SCStreamOutput>
@property (nonatomic, assign) SystemAudioTapHandle *handle;
@end

@implementation CrystalAudioStreamDelegate

- (void)stream:(SCStream *)stream
        didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        ofType:(SCStreamOutputType)type
{
    /* We only care about audio output buffers. */
    if (type != SCStreamOutputTypeAudio) return;

    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!fmt) return;

    const AudioStreamBasicDescription *asbd =
        CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
    if (!asbd) return;

    CMBlockBufferRef blockBuf = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuf) return;

    size_t totalLength = 0;
    char  *dataPtr     = NULL;
    OSStatus st = CMBlockBufferGetDataPointer(blockBuf, 0,
                                              NULL, &totalLength,
                                              &dataPtr);
    if (st != noErr || !dataPtr) return;

    uint32_t channels    = (uint32_t)asbd->mChannelsPerFrame;
    uint32_t frameCount  = (uint32_t)(totalLength /
                            (asbd->mBytesPerFrame ? asbd->mBytesPerFrame : 8));

    self.handle->callback((const float *)dataPtr,
                          frameCount,
                          channels,
                          self.handle->context);
}

@end

/* =========================================================================
 * SCStream wrapper — keeps the stream and delegate alive
 * ====================================================================== */

API_AVAILABLE(macos(13.0))
@interface CrystalSCStreamWrapper : NSObject
@property (nonatomic, strong) SCStream                   *stream;
@property (nonatomic, strong) CrystalAudioStreamDelegate *delegate;
@end

@implementation CrystalSCStreamWrapper
@end

/* We attach the SCStream wrapper to the handle via a side table so we do not
 * bloat SystemAudioTapHandle with ObjC pointers (Crystal would see them as
 * raw pointers, which is fine, but keeping the struct pure-C is cleaner). */
static NSMapTable *g_sc_wrappers = nil;  /* AudioObjectID -> wrapper */
static dispatch_once_t g_sc_table_once;

static void ensure_sc_table(void) {
    dispatch_once(&g_sc_table_once, ^{
        g_sc_wrappers = [NSMapTable strongToStrongObjectsMapTable];
    });
}

/* =========================================================================
 * Forward declarations for the IOProc callback
 * ====================================================================== */

static OSStatus audio_io_proc(AudioObjectID           device,
                               const AudioTimeStamp   *now,
                               const AudioBufferList  *inInputData,
                               const AudioTimeStamp   *inInputTime,
                               AudioBufferList        *outOutputData,
                               const AudioTimeStamp   *inOutputTime,
                               void                   *clientData);

/* =========================================================================
 * Internal helpers
 * ====================================================================== */

/*
 * read_tap_uid
 *
 * Reads kAudioTapPropertyUID from the tap AudioObject and returns a newly
 * created C string (caller must free).  Returns NULL on failure.
 */
static char *read_tap_uid(AudioObjectID tap_id) {
    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioTapPropertyUID,
        .mScope    = kAudioObjectPropertyScopeGlobal,
        .mElement  = kAudioObjectPropertyElementMain,
    };

    CFStringRef uid_ref = NULL;
    UInt32 data_size = sizeof(uid_ref);
    OSStatus st = AudioObjectGetPropertyData(tap_id, &addr,
                                             0, NULL,
                                             &data_size, &uid_ref);
    if (st != noErr || !uid_ref) return NULL;

    /* Convert CFString to a UTF-8 C string. */
    CFIndex len = CFStringGetMaximumSizeForEncoding(CFStringGetLength(uid_ref),
                                                    kCFStringEncodingUTF8) + 1;
    char *buf = (char *)malloc((size_t)len);
    if (!buf) { CFRelease(uid_ref); return NULL; }

    if (!CFStringGetCString(uid_ref, buf, len, kCFStringEncodingUTF8)) {
        free(buf);
        CFRelease(uid_ref);
        return NULL;
    }
    CFRelease(uid_ref);
    return buf;
}

/*
 * create_aggregate_device
 *
 * Builds a Core Audio aggregate device that wraps the tap so we can register
 * an IOProc and receive audio data.
 *
 * The aggregate device dictionary layout:
 *   kAudioAggregateDeviceUIDKey         -> unique UID string
 *   kAudioAggregateDeviceNameKey        -> human-readable name
 *   kAudioAggregateDeviceIsPrivateKey   -> @YES  (invisible in system prefs)
 *   kAudioAggregateDeviceTapListKey     -> array of tap dicts
 *     └─ each tap dict: kAudioSubTapUIDKey -> tap_uid_cstr
 *   kAudioAggregateDeviceSubDeviceListKey -> empty array
 *                                           (tap-only, no real sub-devices)
 */
static OSStatus create_aggregate_device(const char   *tap_uid_cstr,
                                         AudioObjectID *out_aggregate_id)
{
    /* Build a unique UID for the aggregate device itself. */
    CFUUIDRef   uuid     = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uuid_str = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);

    CFStringRef tap_uid_cf = CFStringCreateWithCString(kCFAllocatorDefault,
                                                        tap_uid_cstr,
                                                        kCFStringEncodingUTF8);
    if (!tap_uid_cf) { CFRelease(uuid_str); return kAudioHardwareUnspecifiedError; }

    /* Sub-tap descriptor dict: { kAudioSubTapUIDKey: tap_uid_cf }
     *
     * kAudioSubTapUIDKey expands to the C string literal "uid".  We need a
     * CFStringRef key for CFDictionaryCreate with kCFTypeDictionaryKeyCallBacks,
     * so wrap every key with CFSTR(). */
    const void *tap_dict_keys[]   = { CFSTR("uid") };   /* kAudioSubTapUIDKey */
    const void *tap_dict_values[] = { tap_uid_cf };
    CFDictionaryRef tap_dict =
        CFDictionaryCreate(kCFAllocatorDefault,
                           tap_dict_keys,
                           tap_dict_values,
                           1,
                           &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);
    CFRelease(tap_uid_cf);

    /* Tap list: [ tap_dict ] */
    const void *tap_list_items[] = { tap_dict };
    CFArrayRef tap_list =
        CFArrayCreate(kCFAllocatorDefault,
                      tap_list_items,
                      1,
                      &kCFTypeArrayCallBacks);
    CFRelease(tap_dict);

    /* Empty sub-device list (tap-only aggregate). */
    CFArrayRef sub_device_list =
        CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);

    /* Top-level aggregate dict.
     *
     * All kAudioAggregateDevice* macros expand to C string literals.  Wrap
     * them in CFSTR() to produce the CFStringRef values that
     * kCFTypeDictionaryKeyCallBacks requires. */
    const void *agg_keys[] = {
        CFSTR("uid"),           /* kAudioAggregateDeviceUIDKey          */
        CFSTR("name"),          /* kAudioAggregateDeviceNameKey         */
        CFSTR("private"),       /* kAudioAggregateDeviceIsPrivateKey    */
        CFSTR("taps"),          /* kAudioAggregateDeviceTapListKey      */
        CFSTR("subdevices"),    /* kAudioAggregateDeviceSubDeviceListKey */
    };
    const void *agg_values[] = {
        uuid_str,
        CFSTR("CrystalAudioSystemTap"),
        kCFBooleanTrue,
        tap_list,
        sub_device_list,
    };
    CFDictionaryRef agg_dict =
        CFDictionaryCreate(kCFAllocatorDefault,
                           agg_keys,
                           agg_values,
                           5,
                           &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);
    CFRelease(uuid_str);
    CFRelease(tap_list);
    CFRelease(sub_device_list);

    OSStatus st = AudioHardwareCreateAggregateDevice(agg_dict, out_aggregate_id);
    CFRelease(agg_dict);
    return st;
}

/*
 * query_format
 *
 * Reads the current stream format from the aggregate device and fills in
 * channel_count and sample_rate in the handle.
 */
static void query_format(AudioObjectID aggregate_id,
                          SystemAudioTapHandle *handle)
{
    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioDevicePropertyStreamFormat,
        .mScope    = kAudioObjectPropertyScopeInput,
        .mElement  = kAudioObjectPropertyElementMain,
    };
    AudioStreamBasicDescription asbd = {0};
    UInt32 size = sizeof(asbd);
    OSStatus st = AudioObjectGetPropertyData(aggregate_id, &addr,
                                             0, NULL, &size, &asbd);
    if (st == noErr) {
        handle->channel_count = (uint32_t)asbd.mChannelsPerFrame;
        handle->sample_rate   = asbd.mSampleRate;
    } else {
        /* Sensible defaults if the query fails. */
        handle->channel_count = 2;
        handle->sample_rate   = 48000.0;
    }
}

/* =========================================================================
 * ScreenCaptureKit fallback path (macOS 13.0–14.1)
 *
 * We capture all audio via SCStream with audio enabled.  The delegate
 * receives CMSampleBuffers on a background queue and converts them to the
 * flat float32 format the Crystal callback expects.
 * ====================================================================== */

API_AVAILABLE(macos(13.0))
static OSStatus create_via_screen_capture_kit(SystemAudioCallback  callback,
                                               void                *context,
                                               SystemAudioTapHandle *handle)
{
    ensure_sc_table();

    __block OSStatus result = noErr;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    /* We need the shareable content to create the stream, even though we
     * only want audio (we set excludesCurrentProcessAudio = NO to get all). */
    [SCShareableContent
     getShareableContentWithCompletionHandler:^(SCShareableContent *content,
                                                NSError *err) {
        if (err || !content) {
            result = kAudioHardwareUnspecifiedError;
            dispatch_semaphore_signal(sem);
            return;
        }

        /* Capture the entire display (first one) — audio is system-wide
         * regardless of which display/window we choose. */
        SCDisplay *display = content.displays.firstObject;
        if (!display) {
            result = kAudioHardwareUnspecifiedError;
            dispatch_semaphore_signal(sem);
            return;
        }

        SCContentFilter *filter =
            [[SCContentFilter alloc] initWithDisplay:display
                                   excludingWindows:@[]];

        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.capturesAudio           = YES;
        config.excludesCurrentProcessAudio = NO;
        config.sampleRate              = 48000;
        config.channelCount            = 2;
        /* Minimise video overhead — we only want audio. */
        config.width                   = 2;
        config.height                  = 2;
        config.minimumFrameInterval    =
            CMTimeMake(1, 1);  /* 1 fps — basically never */

        CrystalAudioStreamDelegate *delegate =
            [[CrystalAudioStreamDelegate alloc] init];
        delegate.handle = handle;

        SCStream *stream = [[SCStream alloc] initWithFilter:filter
                                              configuration:config
                                                   delegate:nil];

        NSError *addErr = nil;
        BOOL added =
            [stream addStreamOutput:delegate
                               type:SCStreamOutputTypeAudio
                 sampleHandlerQueue:
                     dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)
                              error:&addErr];
        if (!added) {
            result = kAudioHardwareUnspecifiedError;
            dispatch_semaphore_signal(sem);
            return;
        }

        /* Start the stream; completion fires on an internal queue. */
        [stream startCaptureWithCompletionHandler:^(NSError *startErr) {
            if (startErr) {
                result = kAudioHardwareUnspecifiedError;
            } else {
                /* Store wrapper so we can stop/release later. */
                CrystalSCStreamWrapper *wrapper =
                    [[CrystalSCStreamWrapper alloc] init];
                wrapper.stream   = stream;
                wrapper.delegate = delegate;

                /* Use the handle pointer value as the map key. */
                NSValue *key = [NSValue valueWithPointer:handle];
                @synchronized(g_sc_wrappers) {
                    [g_sc_wrappers setObject:wrapper forKey:key];
                }

                handle->channel_count = 2;
                handle->sample_rate   = 48000.0;
                handle->tap_id              = kAudioObjectUnknown;
                handle->aggregate_device_id = kAudioObjectUnknown;
                handle->io_proc_id          = NULL;
            }
            dispatch_semaphore_signal(sem);
        }];
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return result;
}

/* =========================================================================
 * Real-time IOProc
 *
 * Called by the HAL on a dedicated real-time thread.
 * MUST NOT: allocate, call ObjC, take non-spinlocks, or enter Crystal.
 * ====================================================================== */
static OSStatus audio_io_proc(AudioObjectID           device          __attribute__((unused)),
                               const AudioTimeStamp   *now            __attribute__((unused)),
                               const AudioBufferList  *inInputData,
                               const AudioTimeStamp   *inInputTime    __attribute__((unused)),
                               AudioBufferList        *outOutputData  __attribute__((unused)),
                               const AudioTimeStamp   *inOutputTime   __attribute__((unused)),
                               void                   *clientData)
{
    SystemAudioTapHandle *handle = (SystemAudioTapHandle *)clientData;
    if (!inInputData || !handle->callback) return noErr;

    for (UInt32 b = 0; b < inInputData->mNumberBuffers; b++) {
        const AudioBuffer *buf = &inInputData->mBuffers[b];
        if (!buf->mData || buf->mDataByteSize == 0) continue;

        uint32_t channels    = (uint32_t)buf->mNumberChannels;
        uint32_t byte_per_f  = channels * sizeof(float);
        uint32_t frame_count = (byte_per_f > 0)
                               ? buf->mDataByteSize / byte_per_f
                               : 0;

        handle->callback((const float *)buf->mData,
                         frame_count,
                         channels,
                         handle->context);
    }
    return noErr;
}

/* =========================================================================
 * Public C API
 * ====================================================================== */

/*
 * system_audio_tap_create
 *
 * Creates a system-audio tap and wires it up to an aggregate Core Audio
 * device with a registered IOProc.
 *
 * Parameters
 *   callback   — C function called on the audio thread with PCM data
 *   context    — opaque pointer forwarded to callback unchanged
 *   out_error  — receives an OSStatus if the call fails (may be NULL)
 *
 * Returns
 *   A newly allocated SystemAudioTapHandle on success, or NULL on error.
 *   Caller owns the handle; free with system_audio_tap_destroy().
 *
 * Implementation notes
 *   1. Checks whether AudioHardwareCreateProcessTap is available at runtime.
 *   2. On macOS 14.2+ uses the Process Tap path.
 *   3. On macOS 13.0–14.1 falls back to ScreenCaptureKit audio capture.
 *   4. Returns NULL with *out_error set on anything older or on failure.
 */
SystemAudioTapHandle *system_audio_tap_create(SystemAudioCallback  callback,
                                               void                *context,
                                               OSStatus            *out_error)
{
    if (!callback) {
        if (out_error) *out_error = kAudioHardwareBadObjectError;
        return NULL;
    }

    SystemAudioTapHandle *handle =
        (SystemAudioTapHandle *)calloc(1, sizeof(SystemAudioTapHandle));
    if (!handle) {
        if (out_error) *out_error = kAudioHardwareUnspecifiedError;
        return NULL;
    }
    handle->callback = callback;
    handle->context  = context;

    /* ------------------------------------------------------------------
     * Runtime availability check for AudioHardwareCreateProcessTap.
     * This symbol was added in macOS 14.2 (Sonoma 14.2).
     * ---------------------------------------------------------------- */
    if (@available(macOS 14.2, *)) {

        /* ----------------------------------------------------------------
         * Build CATapDescription: global stereo tap, no process exclusions.
         * -------------------------------------------------------------- */
        CATapDescription *tap_desc =
            [[CATapDescription alloc]
             initStereoGlobalTapButExcludeProcesses:@[]];

        /* If the API is present but the description class isn't, bail. */
        if (!tap_desc) {
            free(handle);
            if (out_error) *out_error = kAudioHardwareUnspecifiedError;
            return NULL;
        }

        /* ----------------------------------------------------------------
         * Create the process tap.
         * -------------------------------------------------------------- */
        AudioObjectID tap_id = kAudioObjectUnknown;
        OSStatus st = AudioHardwareCreateProcessTap(tap_desc, &tap_id);
        if (st != noErr || tap_id == kAudioObjectUnknown) {
            free(handle);
            if (out_error) *out_error = st;
            return NULL;
        }
        handle->tap_id = tap_id;

        /* ----------------------------------------------------------------
         * Read the tap UID — needed to build the aggregate device dict.
         * -------------------------------------------------------------- */
        char *tap_uid = read_tap_uid(tap_id);
        if (!tap_uid) {
            AudioHardwareDestroyProcessTap(tap_id);
            free(handle);
            if (out_error) *out_error = kAudioHardwareUnspecifiedError;
            return NULL;
        }

        /* ----------------------------------------------------------------
         * Create an aggregate device that wraps the tap.
         * -------------------------------------------------------------- */
        AudioObjectID agg_id = kAudioObjectUnknown;
        st = create_aggregate_device(tap_uid, &agg_id);
        free(tap_uid);

        if (st != noErr || agg_id == kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tap_id);
            free(handle);
            if (out_error) *out_error = st;
            return NULL;
        }
        handle->aggregate_device_id = agg_id;

        /* Read back the actual format the aggregate settled on. */
        query_format(agg_id, handle);

        /* ----------------------------------------------------------------
         * Register the IOProc on the aggregate device.
         *
         * We use the block-based variant because this is a .m file and the
         * block captures `handle` directly, matching the function-pointer
         * version's behaviour but written more naturally.
         *
         * The block itself only calls the plain C function audio_io_proc so
         * the real-time safety rules are preserved (the block dispatch overhead
         * is in the block trampoline, which is provided by the OS and is
         * real-time safe on Apple platforms).
         * -------------------------------------------------------------- */
        AudioDeviceIOBlock io_block =
            ^(const AudioTimeStamp   *now,
              const AudioBufferList  *inInputData,
              const AudioTimeStamp   *inInputTime,
              AudioBufferList        *outOutputData,
              const AudioTimeStamp   *inOutputTime)
        {
            audio_io_proc(agg_id,
                          now,
                          inInputData, inInputTime,
                          outOutputData, inOutputTime,
                          handle);
        };

        AudioDeviceIOProcID io_proc_id = NULL;
        st = AudioDeviceCreateIOProcIDWithBlock(&io_proc_id, agg_id, NULL,
                                                io_block);
        if (st != noErr || !io_proc_id) {
            AudioHardwareDestroyAggregateDevice(agg_id);
            AudioHardwareDestroyProcessTap(tap_id);
            free(handle);
            if (out_error) *out_error = st;
            return NULL;
        }
        handle->io_proc_id = io_proc_id;

        if (out_error) *out_error = noErr;
        return handle;

    } else if (@available(macOS 13.0, *)) {

        /* ----------------------------------------------------------------
         * ScreenCaptureKit fallback for macOS 13.0 – 14.1
         * -------------------------------------------------------------- */
        OSStatus st = create_via_screen_capture_kit(callback, context, handle);
        if (st != noErr) {
            free(handle);
            if (out_error) *out_error = st;
            return NULL;
        }
        if (out_error) *out_error = noErr;
        return handle;

    } else {
        /* macOS < 13.0: neither API is available. */
        free(handle);
        if (out_error) *out_error = kAudioHardwareUnsupportedOperationError;
        return NULL;
    }
}

/*
 * system_audio_tap_start
 *
 * Starts audio delivery on the aggregate device.  For the SCKit fallback
 * path, streaming is already running after create; this is a no-op there.
 *
 * Returns noErr on success or an OSStatus error code.
 */
OSStatus system_audio_tap_start(SystemAudioTapHandle *handle) {
    if (!handle) return kAudioHardwareBadObjectError;

    /* SCKit fallback: streaming already started during create. */
    if (handle->aggregate_device_id == kAudioObjectUnknown) return noErr;

    return AudioDeviceStart(handle->aggregate_device_id, handle->io_proc_id);
}

/*
 * system_audio_tap_stop
 *
 * Stops audio delivery.  Safe to call multiple times.
 *
 * Returns noErr on success or an OSStatus error code.
 */
OSStatus system_audio_tap_stop(SystemAudioTapHandle *handle) {
    if (!handle) return kAudioHardwareBadObjectError;

    /* SCKit fallback: stop the stream. */
    if (handle->aggregate_device_id == kAudioObjectUnknown) {
        if (@available(macOS 13.0, *)) {
            NSValue *key = [NSValue valueWithPointer:handle];
            CrystalSCStreamWrapper *wrapper = nil;
            @synchronized(g_sc_wrappers) {
                wrapper = [g_sc_wrappers objectForKey:key];
            }
            if (wrapper) {
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                [wrapper.stream stopCaptureWithCompletionHandler:^(NSError *e) {
                    (void)e;
                    dispatch_semaphore_signal(sem);
                }];
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            }
        }
        return noErr;
    }

    return AudioDeviceStop(handle->aggregate_device_id, handle->io_proc_id);
}

/*
 * system_audio_tap_destroy
 *
 * Stops streaming, unregisters the IOProc, destroys the aggregate device
 * and the process tap, then frees the handle.  After this call the handle
 * pointer is invalid.
 */
void system_audio_tap_destroy(SystemAudioTapHandle *handle) {
    if (!handle) return;

    /* ------------------------------------------------------------------
     * SCKit fallback cleanup
     * ---------------------------------------------------------------- */
    if (handle->aggregate_device_id == kAudioObjectUnknown) {
        if (@available(macOS 13.0, *)) {
            NSValue *key = [NSValue valueWithPointer:handle];
            CrystalSCStreamWrapper *wrapper = nil;
            @synchronized(g_sc_wrappers) {
                wrapper = [g_sc_wrappers objectForKey:key];
                [g_sc_wrappers removeObjectForKey:key];
            }
            if (wrapper) {
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                [wrapper.stream stopCaptureWithCompletionHandler:^(NSError *e) {
                    (void)e;
                    dispatch_semaphore_signal(sem);
                }];
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            }
        }
        free(handle);
        return;
    }

    /* ------------------------------------------------------------------
     * Process Tap path cleanup (macOS 14.2+)
     *
     * AudioHardwareDestroyProcessTap is API_AVAILABLE(macos(14.2)), so all
     * use of it must be inside an @available guard even though we only reach
     * this branch when aggregate_device_id is valid (set only in the 14.2+
     * path of system_audio_tap_create).  The guard satisfies the compiler
     * without adding any runtime overhead in practice.
     * ---------------------------------------------------------------- */

    if (@available(macOS 14.2, *)) {
        /* Stop first (ignore error if already stopped). */
        AudioDeviceStop(handle->aggregate_device_id, handle->io_proc_id);

        /* Destroy the IOProc. */
        if (handle->io_proc_id) {
            AudioDeviceDestroyIOProcID(handle->aggregate_device_id,
                                       handle->io_proc_id);
            handle->io_proc_id = NULL;
        }

        /* Destroy the aggregate device. */
        if (handle->aggregate_device_id != kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(handle->aggregate_device_id);
            handle->aggregate_device_id = kAudioObjectUnknown;
        }

        /* Destroy the process tap. */
        if (handle->tap_id != kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(handle->tap_id);
            handle->tap_id = kAudioObjectUnknown;
        }
    }

    free(handle);
}

/* =========================================================================
 * Starting a tap without blocking the caller
 *
 * Creating a process tap and its aggregate device, and starting the device,
 * wait on the audio server (tens of milliseconds, more for the first tap in
 * a process). system_audio_tap_start_async runs that work on a dispatch
 * queue, in plain C, so the calling thread (often AppKit's main thread)
 * keeps working and no Crystal code runs on a foreign thread.
 *
 * When `queue_to_start_first` is not NULL, the same dispatch job first runs
 * AudioQueueStart on that input queue and creates the tap only after the
 * queue started, in the order a synchronous microphone-plus-system start
 * uses. A queue that fails to start leaves the tap uncreated.
 *
 * The semaphores are held as retained CF-bridged pointers because this file
 * compiles with ARC, which keeps no Objective-C object in a calloc'd struct.
 * ====================================================================== */

typedef struct SystemAudioTapPendingStart {
    AudioQueueRef          queue_to_start_first;
    SystemAudioCallback    callback;
    void                  *context;
    void                  *queue_started;  /* dispatch_semaphore_t, retained */
    void                  *finished;       /* dispatch_semaphore_t, retained */
    _Atomic int            is_finished;
    int                    has_taken_queue_status;
    OSStatus               queue_status;   /* noErr when no queue was given */
    OSStatus               create_status;  /* system_audio_tap_create's error */
    OSStatus               start_status;   /* system_audio_tap_start's status */
    int                    was_tap_attempted;
    SystemAudioTapHandle  *handle;         /* the started tap, or NULL */
} SystemAudioTapPendingStart;

static void system_audio_tap_start_run(void *argument) {
    SystemAudioTapPendingStart *pending = (SystemAudioTapPendingStart *)argument;

    pending->queue_status = noErr;
    if (pending->queue_to_start_first) {
        pending->queue_status = AudioQueueStart(pending->queue_to_start_first, NULL);
    }
    dispatch_semaphore_signal((__bridge dispatch_semaphore_t)pending->queue_started);

    if (pending->queue_status == noErr) {
        pending->was_tap_attempted = 1;
        OSStatus create_status = noErr;
        SystemAudioTapHandle *handle =
            system_audio_tap_create(pending->callback, pending->context, &create_status);
        if (!handle) {
            pending->create_status = (create_status != noErr)
                                     ? create_status
                                     : kAudioHardwareUnspecifiedError;
        } else {
            pending->start_status = system_audio_tap_start(handle);
            if (pending->start_status == noErr) {
                pending->handle = handle;
            } else {
                system_audio_tap_destroy(handle);
            }
        }
    }

    atomic_store_explicit(&pending->is_finished, 1, memory_order_release);
    dispatch_semaphore_signal((__bridge dispatch_semaphore_t)pending->finished);
}

/*
 * system_audio_tap_start_async
 *
 * Begins AudioQueueStart(queue_to_start_first) when a queue is given, then
 * system_audio_tap_create and system_audio_tap_start, all on one
 * user-interactive dispatch job, and returns at once. Returns a pending
 * start for the functions below, or NULL when it could not be allocated
 * (the caller then starts synchronously). Exactly one
 * system_audio_tap_finish_start call must follow; it frees the pending start.
 */
void *system_audio_tap_start_async(SystemAudioCallback  callback,
                                   void                *context,
                                   AudioQueueRef        queue_to_start_first)
{
    SystemAudioTapPendingStart *pending =
        (SystemAudioTapPendingStart *)calloc(1, sizeof(SystemAudioTapPendingStart));
    if (!pending) return NULL;

    dispatch_semaphore_t queue_started = dispatch_semaphore_create(0);
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    if (!queue_started || !finished) {
        free(pending);
        return NULL;
    }
    pending->queue_started = (__bridge_retained void *)queue_started;
    pending->finished = (__bridge_retained void *)finished;
    pending->queue_to_start_first = queue_to_start_first;
    pending->callback = callback;
    pending->context = context;
    pending->create_status = noErr;
    pending->start_status = noErr;
    atomic_init(&pending->is_finished, 0);

    dispatch_async_f(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0),
                     pending, system_audio_tap_start_run);
    return pending;
}

/*
 * system_audio_tap_wait_for_queue_start
 *
 * Waits until the queue given to system_audio_tap_start_async has started,
 * or failed to, and returns AudioQueueStart's status: noErr when no queue was
 * given. The tap may still be starting when this returns.
 */
OSStatus system_audio_tap_wait_for_queue_start(void *pending_start) {
    SystemAudioTapPendingStart *pending = (SystemAudioTapPendingStart *)pending_start;
    if (!pending) return kAudioHardwareBadObjectError;
    if (!pending->has_taken_queue_status) {
        dispatch_semaphore_wait((__bridge dispatch_semaphore_t)pending->queue_started,
                                DISPATCH_TIME_FOREVER);
        pending->has_taken_queue_status = 1;
    }
    return pending->queue_status;
}

/*
 * system_audio_tap_start_is_finished
 *
 * Returns 1 once the dispatch job has returned, so
 * system_audio_tap_finish_start will not wait, and 0 while it runs.
 */
int system_audio_tap_start_is_finished(void *pending_start) {
    SystemAudioTapPendingStart *pending = (SystemAudioTapPendingStart *)pending_start;
    if (!pending) return 1;
    return atomic_load_explicit(&pending->is_finished, memory_order_acquire);
}

/*
 * system_audio_tap_finish_start
 *
 * Waits for the dispatch job, reports each step's status, frees the pending
 * start, and returns the started tap (the caller owns it and frees it with
 * system_audio_tap_destroy), or NULL when the queue, the tap's creation or
 * its start failed. *was_tap_attempted is 0 when the queue failed first.
 */
SystemAudioTapHandle *system_audio_tap_finish_start(void     *pending_start,
                                                    OSStatus *queue_status,
                                                    int      *was_tap_attempted,
                                                    OSStatus *create_status,
                                                    OSStatus *start_status)
{
    SystemAudioTapPendingStart *pending = (SystemAudioTapPendingStart *)pending_start;
    if (!pending) {
        if (queue_status) *queue_status = noErr;
        if (was_tap_attempted) *was_tap_attempted = 0;
        if (create_status) *create_status = kAudioHardwareBadObjectError;
        if (start_status) *start_status = noErr;
        return NULL;
    }

    dispatch_semaphore_t queue_started = (__bridge_transfer dispatch_semaphore_t)pending->queue_started;
    dispatch_semaphore_t finished = (__bridge_transfer dispatch_semaphore_t)pending->finished;
    if (!pending->has_taken_queue_status) {
        dispatch_semaphore_wait(queue_started, DISPATCH_TIME_FOREVER);
    }
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);

    if (queue_status) *queue_status = pending->queue_status;
    if (was_tap_attempted) *was_tap_attempted = pending->was_tap_attempted;
    if (create_status) *create_status = pending->create_status;
    if (start_status) *start_status = pending->start_status;
    SystemAudioTapHandle *handle = pending->handle;
    free(pending);
    return handle;
}
