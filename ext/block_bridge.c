/*
 * block_bridge.c
 *
 * Allows Crystal to pass callbacks into Objective-C APIs that expect block
 * parameters.  Crystal cannot express ObjC blocks natively, so each factory
 * function here builds a heap block (via _Block_copy) whose "invoke" slot
 * points to a small C trampoline that turns the block call into an ordinary
 * C function-pointer call back into Crystal.
 *
 * ObjC Block ABI (ARM64 / Clang, llvm/clang-runtime/BlocksRuntime):
 *   A block object is a C struct laid out as:
 *     [0]  void  *isa;            -- class pointer (_NSConcreteStackBlock etc.)
 *     [1]  int    flags;          -- feature bits (BLOCK_HAS_SIGNATURE, etc.)
 *     [2]  int    reserved;       -- always 0
 *     [3]  void  *invoke;         -- pointer to the trampoline function
 *     [4]  struct Block_descriptor_1 *descriptor;
 *     ... captured variables follow immediately ...
 *
 *   The descriptor is two (optionally three) sub-structs:
 *     Block_descriptor_1: reserved (8 B), size (8 B)
 *     Block_descriptor_3: (only when BLOCK_HAS_SIGNATURE set)
 *                         layout (const char*), signature (const char*)
 *
 * References:
 *   https://clang.llvm.org/docs/Block-ABI-Apple.html
 *   llvm-project: compiler-rt/lib/BlocksRuntime/Block_private.h
 */

#include <stdlib.h>
#include <stdint.h>
#include <Block.h>

/* -------------------------------------------------------------------------
 * Block ABI structures
 * ---------------------------------------------------------------------- */

/* Required prefix of every block descriptor when BLOCK_HAS_SIGNATURE is set.
 * The first two fields are always present (descriptor_1). */
struct Block_descriptor_1 {
    unsigned long reserved;   /* always 0 */
    unsigned long size;       /* sizeof the whole block struct */
};

/* Present when BLOCK_HAS_SIGNATURE (bit 30) is set in flags. */
struct Block_descriptor_3 {
    const char *layout;       /* GC layout string — NULL when ARC / non-GC */
    const char *signature;    /* ObjC type-encoding of the block type */
};

/* Generic block layout header (the fields every block starts with). */
struct Block_layout {
    void        *isa;
    int          flags;
    int          reserved;
    void        *invoke;
    struct Block_descriptor_1 *descriptor;
    /* captured variables follow here in concrete subtypes */
};

/* _NSConcreteStackBlock is exported by libobjc / CoreFoundation.
 * Using a stack-block isa is correct for the temporary we build on the
 * stack; _Block_copy() will copy it to the heap and fix the isa to
 * _NSConcreteMallocBlock automatically. */
extern void *_NSConcreteStackBlock[];

/* Bit 30: block carries an extended type-encoding (signature) descriptor. */
#define BLOCK_HAS_SIGNATURE (1 << 30)

/* -------------------------------------------------------------------------
 * Helper macro
 *
 * DEFINE_BLOCK_TYPE(Name, RetType, ...)
 *   Creates:
 *     - a typedef for the C trampoline function pointer
 *     - a capture struct that holds {fn, ctx}
 *     - a block struct that embeds the capture after the generic header
 * ---------------------------------------------------------------------- */
#define DEFINE_BLOCK_TYPE(Name, RetType, ...)                               \
    typedef RetType (*Name##_fn_t)(void *ctx, ##__VA_ARGS__);               \
    typedef struct {                                                         \
        Name##_fn_t fn;                                                      \
        void       *ctx;                                                     \
    } Name##_capture_t;                                                      \
    typedef struct {                                                         \
        void                  *isa;                                          \
        int                    flags;                                        \
        int                    reserved;                                     \
        void                  *invoke;                                       \
        struct Block_descriptor_1 *descriptor;                               \
        Name##_capture_t       capture;                                      \
    } Name##_block_t;

/* =========================================================================
 * 1. AVAudioNodeTapBlock  —  void (^)(AVAudioPCMBuffer *, AVAudioTime *)
 *
 * ObjC type encoding:
 *   v  = void return
 *   24 = total arg bytes on ARM64 (8 block-self + 8 buffer + 8 time)
 *   @?0 = block pointer at offset 0
 *   @"AVAudioPCMBuffer"8  = object at offset 8
 *   @"AVAudioTime"16      = object at offset 16
 * ====================================================================== */
DEFINE_BLOCK_TYPE(AudioTap, void, void *buffer, void *when)

static struct Block_descriptor_1 audio_tap_d1 = {
    .reserved = 0,
    .size     = sizeof(AudioTap_block_t),
};
static struct Block_descriptor_3 audio_tap_d3 = {
    .layout    = NULL,
    .signature = "v24@?0@\"AVAudioPCMBuffer\"8@\"AVAudioTime\"16",
};

/* The trampoline.  The ObjC runtime calls this with the block itself as the
 * first argument, followed by the block's declared parameters. */
static void audio_tap_invoke(AudioTap_block_t *blk, void *buffer, void *when) {
    blk->capture.fn(blk->capture.ctx, buffer, when);
}

/*
 * crystal_audio_tap_block_create
 *
 * fn  — Crystal proc compiled to a C function:
 *          void fn(void *ctx, void *avAudioPCMBuffer, void *avAudioTime)
 * ctx — opaque pointer forwarded to fn unchanged (e.g. a Crystal Proc box)
 *
 * Returns a heap-allocated ObjC block object.  Pass it directly to
 * -installTapOnBus:bufferSize:format:block:.  Release with
 * crystal_block_release() once the tap has been installed.
 */
void *crystal_audio_tap_block_create(void (*fn)(void *ctx,
                                                void *buffer,
                                                void *when),
                                     void *ctx)
{
    AudioTap_block_t tmp;
    tmp.isa        = _NSConcreteStackBlock;
    tmp.flags      = BLOCK_HAS_SIGNATURE;
    tmp.reserved   = 0;
    tmp.invoke     = (void *)audio_tap_invoke;
    tmp.descriptor = &audio_tap_d1;
    tmp.capture.fn  = (AudioTap_fn_t)fn;
    tmp.capture.ctx = ctx;

    /* Attach the signature descriptor immediately after d1 in memory.
     * Clang emits a single allocation that contains both; we replicate that
     * by pointing descriptor at audio_tap_d1 and relying on the runtime
     * reading &descriptor[1] for the signature when BLOCK_HAS_SIGNATURE. */
    /* NOTE: The Block runtime reads the signature by casting descriptor to
     * a struct that overlays d1 + d3 consecutively.  We therefore need them
     * adjacent.  We use a local compound descriptor for this block type. */
    static struct {
        struct Block_descriptor_1 d1;
        struct Block_descriptor_3 d3;
    } audio_tap_desc = {
        .d1 = { .reserved = 0, .size = sizeof(AudioTap_block_t) },
        .d3 = { .layout   = NULL,
                .signature = "v24@?0@\"AVAudioPCMBuffer\"8@\"AVAudioTime\"16" },
    };
    tmp.descriptor = &audio_tap_desc.d1;

    return _Block_copy(&tmp);
}

/* =========================================================================
 * 2. NSError completion handler  —  void (^)(NSError *)
 *
 * ObjC type encoding:
 *   v  = void return
 *   16 = total arg bytes (8 block-self + 8 error)
 *   @?0 = block at offset 0
 *   @8  = object at offset 8
 * ====================================================================== */
DEFINE_BLOCK_TYPE(ErrorCompletion, void, void *error)

static struct {
    struct Block_descriptor_1 d1;
    struct Block_descriptor_3 d3;
} error_completion_desc = {
    .d1 = { .reserved = 0, .size = sizeof(ErrorCompletion_block_t) },
    .d3 = { .layout   = NULL, .signature = "v16@?0@8" },
};

static void error_completion_invoke(ErrorCompletion_block_t *blk, void *error) {
    blk->capture.fn(blk->capture.ctx, error);
}

/*
 * crystal_error_completion_block_create
 *
 * fn  — Crystal proc: void fn(void *ctx, void *nsError)
 * ctx — opaque Crystal context pointer
 *
 * Use for APIs such as -startWithCompletionHandler:,
 * -setCategory:error:, etc.
 */
void *crystal_error_completion_block_create(void (*fn)(void *ctx, void *error),
                                             void *ctx)
{
    ErrorCompletion_block_t tmp;
    tmp.isa        = _NSConcreteStackBlock;
    tmp.flags      = BLOCK_HAS_SIGNATURE;
    tmp.reserved   = 0;
    tmp.invoke     = (void *)error_completion_invoke;
    tmp.descriptor = &error_completion_desc.d1;
    tmp.capture.fn  = (ErrorCompletion_fn_t)fn;
    tmp.capture.ctx = ctx;
    return _Block_copy(&tmp);
}

/* =========================================================================
 * 3. MPRemoteCommand handler  —  NSInteger (^)(MPRemoteCommandEvent *)
 *
 * ObjC type encoding:
 *   q  = long long (NSInteger on 64-bit)
 *   16 = total arg bytes (8 block-self + 8 event)
 *   @?0 = block at offset 0
 *   @8  = object at offset 8
 * ====================================================================== */
DEFINE_BLOCK_TYPE(MPHandler, long, void *event)

static struct {
    struct Block_descriptor_1 d1;
    struct Block_descriptor_3 d3;
} mp_handler_desc = {
    .d1 = { .reserved = 0, .size = sizeof(MPHandler_block_t) },
    .d3 = { .layout   = NULL, .signature = "q16@?0@8" },
};

static long mp_handler_invoke(MPHandler_block_t *blk, void *event) {
    return blk->capture.fn(blk->capture.ctx, event);
}

/*
 * crystal_mp_handler_block_create
 *
 * fn  — Crystal proc: Int64 fn(void *ctx, void *mpRemoteCommandEvent)
 * ctx — opaque Crystal context pointer
 *
 * The return value maps to MPRemoteCommandHandlerStatus:
 *   0 = MPRemoteCommandHandlerStatusSuccess
 *   1 = MPRemoteCommandHandlerStatusNoSuchContent
 *   100 = MPRemoteCommandHandlerStatusCommandFailed
 */
void *crystal_mp_handler_block_create(long (*fn)(void *ctx, void *event),
                                       void *ctx)
{
    MPHandler_block_t tmp;
    tmp.isa        = _NSConcreteStackBlock;
    tmp.flags      = BLOCK_HAS_SIGNATURE;
    tmp.reserved   = 0;
    tmp.invoke     = (void *)mp_handler_invoke;
    tmp.descriptor = &mp_handler_desc.d1;
    tmp.capture.fn  = (MPHandler_fn_t)fn;
    tmp.capture.ctx = ctx;
    return _Block_copy(&tmp);
}

/* =========================================================================
 * 4. crystal_block_release
 *
 * Releases the heap block returned by any factory above.  Call this after
 * passing the block to the ObjC API; the API retains its own reference so
 * releasing the factory copy does not prematurely free the block.
 * ====================================================================== */
void crystal_block_release(void *block) {
    _Block_release(block);
}
