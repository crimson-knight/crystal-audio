#include <AudioToolbox/AudioToolbox.h>
static int failure_step, queue_disposals, file_disposals, synchronous_starts;
static int queue_token, file_token, buffer_token;
void setup_fixture_reset(int step) {
  failure_step = step; queue_disposals = 0; file_disposals = 0; synchronous_starts = 0;
}
int setup_fixture_queue_disposals(void) { return queue_disposals; }
int setup_fixture_file_disposals(void) { return file_disposals; }
int setup_fixture_synchronous_starts(void) { return synchronous_starts; }
OSStatus ExtAudioFileCreateWithURL(CFURLRef url, AudioFileTypeID type,
                                 const AudioStreamBasicDescription *format,
                                 const AudioChannelLayout *layout, UInt32 flags,
                                 ExtAudioFileRef *file) {
  (void)url; (void)type; (void)format; (void)layout; (void)flags;
  *file = (ExtAudioFileRef)&file_token; return failure_step == 0 ? -50 : 0;
}
OSStatus ExtAudioFileSetProperty(ExtAudioFileRef file, ExtAudioFilePropertyID property,
                                UInt32 size, const void *value) {
  (void)file; (void)property; (void)size; (void)value; return failure_step == 1 ? -50 : 0;
}
OSStatus ExtAudioFileDispose(ExtAudioFileRef file) { (void)file; ++file_disposals; return 0; }
OSStatus AudioQueueNewInput(const AudioStreamBasicDescription *format, AudioQueueInputCallback callback,
                           void *context, CFRunLoopRef runloop, CFStringRef mode, UInt32 flags,
                           AudioQueueRef *queue) {
  (void)format; (void)callback; (void)context; (void)runloop; (void)mode; (void)flags;
  *queue = (AudioQueueRef)&queue_token; return failure_step == 2 ? -50 : 0;
}
OSStatus AudioQueueAllocateBuffer(AudioQueueRef queue, UInt32 size, AudioQueueBufferRef *buffer) {
  (void)queue; (void)size; *buffer = (AudioQueueBufferRef)&buffer_token; return failure_step == 3 ? -50 : 0;
}
OSStatus AudioQueueEnqueueBuffer(AudioQueueRef queue, AudioQueueBufferRef buffer, UInt32 packets,
                               const AudioStreamPacketDescription *descriptions) {
  (void)queue; (void)buffer; (void)packets; (void)descriptions; return failure_step == 4 ? -50 : 0;
}
OSStatus AudioQueueStart(AudioQueueRef queue, const AudioTimeStamp *timestamp) {
  (void)queue; (void)timestamp; ++synchronous_starts; return 0;
}
OSStatus AudioQueueStop(AudioQueueRef queue, Boolean immediate) { (void)queue; (void)immediate; return 0; }
OSStatus AudioQueueDispose(AudioQueueRef queue, Boolean immediate) { (void)queue; (void)immediate; ++queue_disposals; return 0; }
void *ca_audio_queue_start_async(void *queue) { (void)queue; return 0; }
int ca_audio_queue_start_wait(void *pending) { (void)pending; return 0; }
int ca_audio_queue_start_is_finished(void *pending) { (void)pending; return 1; }
void ca_audio_input_warm_up_async(const unsigned char *device) { (void)device; }
