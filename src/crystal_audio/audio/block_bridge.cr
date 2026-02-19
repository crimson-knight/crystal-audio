{% if flag?(:darwin) %}

# Crystal-side bindings for ext/block_bridge.c
#
# block_bridge.c constructs valid Objective-C block objects from plain C
# function pointers + void* context. This lets Crystal pass closures to
# Apple audio APIs that use block callbacks (AVAudioEngine.installTap,
# SCStream start/stop, MPRemoteCommand handlers).
#
# The block ABI (confirmed on ARM64 macOS):
#   struct Block { isa, flags, reserved, invoke_fn*, descriptor*, context... }
#   _Block_copy promotes a stack block to the heap; ObjC APIs retain it.
#
# Usage pattern (GC safety is critical):
#   1. Box.box(proc) allocates a GC-tracked wrapper around the Crystal closure
#   2. Store the Box in a class variable (creates a GC root — prevents collection)
#   3. Pass Box pointer as ctx to the block factory
#   4. The inner lambda must be non-closure (receives everything via ctx)
#   5. Call crystal_block_release after the ObjC install call returns

lib LibBlockBridge
  # ── AVAudioNodeTapBlock ─────────────────────────────────────────────────────
  # void (^)(AVAudioPCMBuffer *buffer, AVAudioTime *when)
  # fn receives: (ctx: Void*, buffer: Void*, when: Void*) -> Void
  alias AudioTapFn = (Void*, Void*, Void*) -> Void

  fun crystal_audio_tap_block_create(fn : AudioTapFn, ctx : Void*) : Void*

  # ── NSError completion handler ───────────────────────────────────────────────
  # void (^)(NSError * _Nullable error)
  # fn receives: (ctx: Void*, error: Void*) -> Void
  alias ErrorCompletionFn = (Void*, Void*) -> Void

  fun crystal_error_completion_block_create(fn : ErrorCompletionFn, ctx : Void*) : Void*

  # ── MPRemoteCommand handler ──────────────────────────────────────────────────
  # MPRemoteCommandHandlerStatus (^)(MPRemoteCommandEvent *event)
  # fn receives: (ctx: Void*, event: Void*) -> Int64  (returns command status)
  alias MpHandlerFn = (Void*, Void*) -> Int64

  fun crystal_mp_handler_block_create(fn : MpHandlerFn, ctx : Void*) : Void*

  # ── Lifetime management ──────────────────────────────────────────────────────
  # Release the caller's reference. ObjC APIs retain their own copies;
  # call this immediately after the ObjC install call returns.
  fun crystal_block_release(block : Void*)
end

{% end %}
