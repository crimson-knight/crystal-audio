#pragma once
/*
 * crystal_bridge.h
 *
 * C interface to the Crystal audio library compiled as a static library
 * (libcrystal_audio.a) for iOS.  Include this file as the Xcode
 * "Objective-C Bridging Header" so Swift can call these functions directly.
 *
 * Build the static library with:
 *   ./build_crystal_lib.sh
 * then add libcrystal_audio.a to Xcode → Build Phases →
 * "Link Binary with Libraries".
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize the Crystal runtime (GC, fibers, threads).
 * MUST be called once from the main thread before any other crystal_audio_* call.
 * Safe to call multiple times.
 *
 * @return  0 on success, -1 on error.
 */
int crystal_audio_init(void);

/**
 * Start microphone recording to a WAV file at the given path.
 *
 * @param output_path  Absolute filesystem path for the output WAV file.
 *                     The directory must already exist and be writable.
 * @return  0 on success.
 *         -1 if a recording is already in progress or on any error.
 */
int crystal_audio_start_mic(const char *output_path);

/**
 * Stop the current recording and finalize the output file.
 *
 * @return  0 on success.
 *         -1 if no recording is active or on any error.
 */
int crystal_audio_stop(void);

/**
 * Query whether a recording is currently in progress.
 *
 * @return  1 if recording is active, 0 otherwise.
 */
int crystal_audio_is_recording(void);

#ifdef __cplusplus
}
#endif
