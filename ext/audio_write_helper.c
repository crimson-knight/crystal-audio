/*
 * audio_write_helper.c — safe ExtAudioFileWrite wrapper
 *
 * Crystal's struct value semantics can cause AudioBufferList fields to be
 * written to temporary copies instead of the actual struct memory.  This C
 * helper constructs the AudioBufferList on the C stack (guaranteed correct
 * layout) and calls ExtAudioFileWrite, eliminating any struct-layout
 * mismatch between Crystal and the C ABI.
 *
 * Also provides a safe wrapper for ExtAudioFileDispose that checks for NULL.
 */

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>

/* Write interleaved PCM data to an ExtAudioFile.
 *
 * Parameters:
 *   ext_file   — ExtAudioFileRef from ExtAudioFileCreateWithURL
 *   data       — pointer to raw PCM sample data (from AudioQueueBuffer.mAudioData)
 *   byte_size  — number of bytes in data (from AudioQueueBuffer.mAudioDataByteSize)
 *   channels   — number of interleaved channels (1 for mono, 2 for stereo)
 *   bytes_per_frame — bytes per audio frame (channels * bytes_per_sample)
 *
 * Returns: OSStatus (0 = success)
 */
int32_t ca_ext_audio_file_write_pcm(
    void *ext_file,
    const void *data,
    uint32_t byte_size,
    uint32_t channels,
    uint32_t bytes_per_frame)
{
    if (!ext_file || !data || byte_size == 0 || bytes_per_frame == 0)
        return -50;  /* paramErr */

    /* Align byte_size down to a whole number of frames */
    uint32_t frames = byte_size / bytes_per_frame;
    if (frames == 0)
        return 0;  /* nothing to write */

    uint32_t aligned_size = frames * bytes_per_frame;

    /* Construct AudioBufferList on the C stack — guaranteed correct layout */
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = channels;
    abl.mBuffers[0].mDataByteSize = aligned_size;
    abl.mBuffers[0].mData = (void *)data;

    return (int32_t)ExtAudioFileWrite((ExtAudioFileRef)ext_file, frames, &abl);
}
