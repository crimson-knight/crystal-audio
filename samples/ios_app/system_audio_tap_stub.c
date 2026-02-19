/*
 * system_audio_tap_stub.c
 *
 * iOS Simulator stub for system_audio_tap functions.
 *
 * system_audio_tap.m (the real implementation) uses macOS-only APIs:
 *   - AudioHardwareCreateProcessTap  (macOS 14.2+)
 *   - ScreenCaptureKit               (macOS 13+)
 *
 * Neither API exists on iOS. The Crystal library (libcrystal_audio.a) was
 * compiled with --define ios which skips the SystemAudioCapture class at the
 * Crystal level, but the lib LibSystemAudioTap declarations are still
 * compiled in because system_audio.cr only guards on flag?(:darwin), which
 * is true for both macOS and iOS targets.
 *
 * These stubs satisfy the linker and return failure codes so any accidental
 * call is handled gracefully.
 */

#include <stdint.h>

typedef void (*SystemAudioCallback)(const float *frames,
                                    uint32_t     frame_count,
                                    uint32_t     channel_count,
                                    void        *context);

typedef struct SystemAudioTapHandle SystemAudioTapHandle;

/* Always returns NULL on iOS — system audio tap is not supported. */
SystemAudioTapHandle *system_audio_tap_create(SystemAudioCallback callback,
                                               void               *context,
                                               int32_t            *out_error)
{
    (void)callback;
    (void)context;
    if (out_error) *out_error = -50; /* paramErr */
    return (SystemAudioTapHandle *)0;
}

int32_t system_audio_tap_start(SystemAudioTapHandle *handle)
{
    (void)handle;
    return -50;
}

int32_t system_audio_tap_stop(SystemAudioTapHandle *handle)
{
    (void)handle;
    return -50;
}

void system_audio_tap_destroy(SystemAudioTapHandle *handle)
{
    (void)handle;
}
