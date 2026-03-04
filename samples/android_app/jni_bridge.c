/*
 * jni_bridge.c — JNI glue between Kotlin and Crystal shared library
 *
 * This file provides the native method implementations for CrystalLib.kt.
 * It stores the JavaVM pointer, initializes the Crystal runtime, and
 * forwards calls to the Crystal C API exported by crystal_bridge.cr.
 *
 * Build: compiled into libcrystal_audio.so alongside the Crystal object files
 */

#include <jni.h>
#include <android/log.h>
#include <string.h>

#define LOG_TAG "CrystalAudio"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* ── Crystal C API (exported by crystal_bridge.cr) ─────────────────────────── */

extern int crystal_audio_init(void);
extern int crystal_audio_start_recording(const char *path);
extern int crystal_audio_stop_recording(void);
extern int crystal_audio_is_recording(void);
extern int crystal_audio_start_playback(const char **paths, int count);
extern int crystal_audio_stop_playback(void);

/* Media session callbacks (called from JNI when lock screen controls are used) */
extern void crystal_on_media_play(void);
extern void crystal_on_media_pause(void);
extern void crystal_on_media_next(void);
extern void crystal_on_media_previous(void);
extern void crystal_on_media_seek(int64_t position_ms);
extern void crystal_on_media_stop(void);

/* ── Trace helper (called by Crystal via LibTrace) ─────────────────────────── */

void crystal_trace(const char *msg) {
    LOGE("CRYSTAL_TRACE: %s", msg);
}

/* ── Global state ──────────────────────────────────────────────────────────── */

static JavaVM *g_jvm = NULL;

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    g_jvm = vm;
    LOGI("JNI_OnLoad: JavaVM stored");
    return JNI_VERSION_1_6;
}

/* ── JNI native method implementations ─────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_init(JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("CrystalLib.init() called");
    int result = crystal_audio_init();
    LOGI("crystal_audio_init returned %d", result);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_startRecording(
    JNIEnv *env, jobject thiz, jstring path) {
    (void)thiz;
    const char *c_path = (*env)->GetStringUTFChars(env, path, NULL);
    if (!c_path) {
        LOGE("startRecording: GetStringUTFChars failed");
        return -1;
    }
    LOGI("startRecording: path=%s", c_path);
    int result = crystal_audio_start_recording(c_path);
    (*env)->ReleaseStringUTFChars(env, path, c_path);
    LOGI("startRecording: result=%d", result);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_stopRecording(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("stopRecording called");
    int result = crystal_audio_stop_recording();
    LOGI("stopRecording: result=%d", result);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_isRecording(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    return crystal_audio_is_recording();
}

JNIEXPORT jint JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_startPlayback(
    JNIEnv *env, jobject thiz, jobjectArray paths) {
    (void)thiz;
    int count = (*env)->GetArrayLength(env, paths);
    if (count <= 0) return -1;

    const char **c_paths = (const char **)malloc(count * sizeof(char *));
    if (!c_paths) return -1;

    for (int i = 0; i < count; i++) {
        jstring jpath = (jstring)(*env)->GetObjectArrayElement(env, paths, i);
        c_paths[i] = (*env)->GetStringUTFChars(env, jpath, NULL);
    }

    LOGI("startPlayback: %d tracks", count);
    int result = crystal_audio_start_playback(c_paths, count);

    // Release strings
    for (int i = 0; i < count; i++) {
        jstring jpath = (jstring)(*env)->GetObjectArrayElement(env, paths, i);
        (*env)->ReleaseStringUTFChars(env, jpath, c_paths[i]);
    }
    free(c_paths);

    LOGI("startPlayback: result=%d", result);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_stopPlayback(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("stopPlayback called");
    return crystal_audio_stop_playback();
}

/* ── Media session callback JNI implementations ────────────────────────────── */

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_onMediaPlay(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("onMediaPlay");
    crystal_on_media_play();
}

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_onMediaPause(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("onMediaPause");
    crystal_on_media_pause();
}

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_onMediaNext(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("onMediaNext");
    crystal_on_media_next();
}

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_onMediaPrevious(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("onMediaPrevious");
    crystal_on_media_previous();
}

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_onMediaSeek(
    JNIEnv *env, jobject thiz, jlong position_ms) {
    (void)env; (void)thiz;
    LOGI("onMediaSeek: %lld ms", (long long)position_ms);
    crystal_on_media_seek((int64_t)position_ms);
}

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_onMediaStop(
    JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    LOGI("onMediaStop");
    crystal_on_media_stop();
}

/* ── Now playing info (Crystal → Java) ─────────────────────────────────────── */
/* These are called by Crystal to push metadata back to the MediaSession.
 * They require a JNI env and calling back into Java, which is complex.
 * For now, these are stubs that log — the actual Kotlin MediaPlaybackService
 * handles its own state management. */

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_updateNowPlaying(
    JNIEnv *env, jobject thiz, jstring title, jstring artist, jlong duration_ms) {
    (void)thiz;
    const char *c_title = (*env)->GetStringUTFChars(env, title, NULL);
    const char *c_artist = (*env)->GetStringUTFChars(env, artist, NULL);
    LOGI("updateNowPlaying: title=%s artist=%s duration=%lld",
         c_title, c_artist, (long long)duration_ms);
    (*env)->ReleaseStringUTFChars(env, title, c_title);
    (*env)->ReleaseStringUTFChars(env, artist, c_artist);
}

JNIEXPORT void JNICALL
Java_com_crimsonknight_crystalaudio_CrystalLib_updatePlaybackState(
    JNIEnv *env, jobject thiz, jint state, jlong position_ms) {
    (void)env; (void)thiz;
    LOGI("updatePlaybackState: state=%d position=%lld", state, (long long)position_ms);
}
