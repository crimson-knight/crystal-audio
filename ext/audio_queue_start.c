// AudioQueue start and input warm-up helpers for CrystalAudio::Recorder.
//
// AudioQueueStart on an input queue waits for the input device to spin up
// (about 40-60 ms, more after a long idle). These helpers run that wait, and
// the one-time Core Audio input setup, on a Grand Central Dispatch queue in
// plain C, so the calling thread (often AppKit's main thread) keeps working
// and no Crystal code runs on a foreign thread.

#include <AudioToolbox/AudioToolbox.h>
#include <dispatch/dispatch.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    AudioQueueRef queue;
    dispatch_semaphore_t done;
    OSStatus status;
    _Atomic int is_finished;
} ca_audio_queue_start_t;

static void ca_audio_queue_start_run(void *context) {
    ca_audio_queue_start_t *start = (ca_audio_queue_start_t *)context;
    start->status = AudioQueueStart(start->queue, NULL);
    atomic_store_explicit(&start->is_finished, 1, memory_order_release);
    dispatch_semaphore_signal(start->done);
}

// Begins AudioQueueStart(queue) on a user-interactive dispatch queue and
// returns a handle for ca_audio_queue_start_wait, or NULL when the handle
// could not be allocated (the caller then starts the queue itself).
void *ca_audio_queue_start_async(AudioQueueRef queue) {
    ca_audio_queue_start_t *start = calloc(1, sizeof(ca_audio_queue_start_t));
    if (!start) return NULL;
    start->done = dispatch_semaphore_create(0);
    if (!start->done) {
        free(start);
        return NULL;
    }
    start->queue = queue;
    dispatch_async_f(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0),
                     start, ca_audio_queue_start_run);
    return start;
}

// Returns 1 once the start begun by ca_audio_queue_start_async has returned,
// so ca_audio_queue_start_wait will not wait, and 0 while it runs.
int ca_audio_queue_start_is_finished(void *handle) {
    ca_audio_queue_start_t *start = (ca_audio_queue_start_t *)handle;
    if (!start) return 1;
    return atomic_load_explicit(&start->is_finished, memory_order_acquire);
}

// Waits for the start begun by ca_audio_queue_start_async, frees the handle,
// and returns AudioQueueStart's status.
OSStatus ca_audio_queue_start_wait(void *handle) {
    ca_audio_queue_start_t *start = (ca_audio_queue_start_t *)handle;
    if (!start) return kAudioQueueErr_InvalidQueueType;
    dispatch_semaphore_wait(start->done, DISPATCH_TIME_FOREVER);
    OSStatus status = start->status;
    dispatch_release(start->done);
    free(start);
    return status;
}

static void ca_audio_input_warm_up_callback(void *user_data, AudioQueueRef queue,
                                            AudioQueueBufferRef buffer,
                                            const AudioTimeStamp *start_time,
                                            UInt32 packet_count,
                                            const AudioStreamPacketDescription *packets) {
    (void)user_data; (void)queue; (void)buffer; (void)start_time;
    (void)packet_count; (void)packets;
}

static void ca_audio_input_warm_up_run(void *context) {
    char *device_uid = (char *)context;
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 44100.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 2;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;

    AudioQueueRef queue = NULL;
    if (AudioQueueNewInput(&format, ca_audio_input_warm_up_callback, NULL, NULL, NULL, 0, &queue) == noErr) {
        if (device_uid) {
            CFStringRef uid = CFStringCreateWithCString(NULL, device_uid, kCFStringEncodingUTF8);
            if (uid) {
                AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid, sizeof(uid));
                CFRelease(uid);
            }
        }
        AudioQueueDispose(queue, true);
    }
    free(device_uid);
}

// Creates and disposes one input AudioQueue (never started) on a utility
// dispatch queue. The first input queue a process creates pays Core Audio's
// one-time input setup (about 85 ms measured in Scribe); after this call the
// next AudioQueueNewInput takes well under a millisecond. The queue is never
// started, so the input device stays closed and the microphone indicator
// stays off. `device_uid` may be NULL for the system input device.
void ca_audio_input_warm_up_async(const char *device_uid) {
    char *device_uid_copy = device_uid ? strdup(device_uid) : NULL;
    if (device_uid && !device_uid_copy) return;
    dispatch_async_f(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                     device_uid_copy, ca_audio_input_warm_up_run);
}
