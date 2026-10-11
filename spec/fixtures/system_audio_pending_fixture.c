#include <stdatomic.h>
#include <stdint.h>
#include <unistd.h>

typedef void (*Callback)(float *, uint32_t, uint32_t, void *);
static Callback saved_callback;
static void *saved_context;
static atomic_int is_released, finish_entered, finish_count, destroy_count;
static atomic_int synchronous_create_count, stop_thread_started, stop_thread_finished;
static int allocation_failure, creation_failure;
static int pending_token, tap_token;

void pending_fixture_reset(int allocation, int creation) {
  allocation_failure = allocation; creation_failure = creation;
  atomic_store(&is_released, 0); atomic_store(&finish_entered, 0);
  atomic_store(&finish_count, 0); atomic_store(&destroy_count, 0);
  atomic_store(&synchronous_create_count, 0);
  atomic_store(&stop_thread_started, 0); atomic_store(&stop_thread_finished, 0);
}
void pending_fixture_release(void) { atomic_store(&is_released, 1); }
void pending_fixture_stop_started(void) { atomic_store(&stop_thread_started, 1); }
void pending_fixture_stop_finished(void) { atomic_store(&stop_thread_finished, 1); }
int pending_fixture_wait_for_finish(void) {
  for (int i = 0; i < 1000; ++i) {
    if (atomic_load(&finish_entered)) return 1;
    usleep(1000);
  }
  return 0;
}
int pending_fixture_wait_for_stop(void) {
  for (int i = 0; i < 1000; ++i) {
    if (atomic_load(&stop_thread_started)) break;
    usleep(1000);
  }
  for (int i = 0; i < 100; ++i) {
    if (atomic_load(&stop_thread_finished)) return 1;
    usleep(1000);
  }
  return 0;
}
int pending_fixture_finishes(void) { return atomic_load(&finish_count); }
int pending_fixture_destroys(void) { return atomic_load(&destroy_count); }
int pending_fixture_synchronous_creates(void) { return atomic_load(&synchronous_create_count); }
void pending_fixture_callback(void) {
  float frames[2] = {0.25f, -0.25f};
  saved_callback(frames, 1, 2, saved_context);
}
void *system_audio_tap_start_async(Callback callback, void *context, void *queue) {
  (void)queue; saved_callback = callback; saved_context = context;
  return allocation_failure ? 0 : &pending_token;
}
int32_t system_audio_tap_wait_for_queue_start(void *pending) { (void)pending; return 0; }
int system_audio_tap_start_is_finished(void *pending) { (void)pending; return atomic_load(&is_released); }
void *system_audio_tap_finish_start(void *pending, int32_t *queue_status, int32_t *attempted,
                                  int32_t *create_status, int32_t *start_status) {
  (void)pending; atomic_fetch_add(&finish_count, 1); atomic_store(&finish_entered, 1);
  while (!atomic_load(&is_released)) usleep(1000);
  *queue_status = 0; *attempted = 1; *create_status = 0; *start_status = 0;
  return creation_failure ? 0 : &tap_token;
}
void *system_audio_tap_create(Callback callback, void *context, int32_t *error) {
  (void)callback; (void)context; atomic_fetch_add(&synchronous_create_count, 1);
  *error = 0; return 0;
}
int32_t system_audio_tap_start(void *tap) { (void)tap; return 0; }
int32_t system_audio_tap_stop(void *tap) { (void)tap; return 0; }
void system_audio_tap_destroy(void *tap) { (void)tap; atomic_fetch_add(&destroy_count, 1); }
