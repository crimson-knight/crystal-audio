require "../../src/crystal_audio"

# completion_test — Realtime end-to-end proof of the per-track completion
# callback (CrystalAudio::Player#on_track_finished) using the PRODUCTION
# completion type, AVAudioPlayerNodeCompletionDataPlayedBack.
#
# Why a separate realtime sample (vs the spec): DataPlayedBack fires only when
# audio is genuinely played back through an output device — it does NOT fire
# under offline manual rendering. So the offline spec verifies the wiring with
# DataRendered; THIS sample plays a short file in realtime through the default
# output device and proves DataPlayedBack fires (with the right index) at the
# natural end, and does NOT fire on an explicit stop.
#
# The native completion handler is dispatched to the MAIN dispatch queue (the
# C bridge hops there so Crystal is only ever called on the main thread). A
# plain Crystal program's main thread runs the fiber scheduler, not a CFRunLoop,
# so we explicitly pump the run loop to service that queued callback.

SAMPLE_RATE = 44100.0_f64
FREQUENCY   =   440.0_f64

def generate_wav(path : String, seconds : Float64)
  num_samples = (SAMPLE_RATE * seconds).to_i32
  data_size = num_samples * 2
  File.open(path, "wb") do |f|
    f.write("RIFF".to_slice)
    f.write_bytes((36 + data_size).to_u32, IO::ByteFormat::LittleEndian)
    f.write("WAVE".to_slice)
    f.write("fmt ".to_slice)
    f.write_bytes(16_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)   # PCM
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)   # mono
    f.write_bytes(SAMPLE_RATE.to_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes((SAMPLE_RATE.to_u32 * 2), IO::ByteFormat::LittleEndian)
    f.write_bytes(2_u16, IO::ByteFormat::LittleEndian)
    f.write_bytes(16_u16, IO::ByteFormat::LittleEndian)
    f.write("data".to_slice)
    f.write_bytes(data_size.to_u32, IO::ByteFormat::LittleEndian)
    num_samples.times do |i|
      t = i.to_f64 / SAMPLE_RATE
      f.write_bytes((Math.sin(2.0 * Math::PI * FREQUENCY * t) * 32000).to_i16, IO::ByteFormat::LittleEndian)
    end
  end
end

# Pump the main CFRunLoop (which services the main dispatch queue the completion
# is hopped onto) until `cond` is true or `timeout` seconds elapse.
def pump_until(timeout : Float64, &cond : -> Bool) : Bool
  deadline = Time.instant + timeout.seconds
  until cond.call
    return false if Time.instant >= deadline
    LibCoreFoundation.CFRunLoopRunInMode(CrystalAudio::CF.default_run_loop_mode, 0.05, true)
  end
  true
end

def check(condition : Bool, message : String)
  if condition
    puts "  [PASS] #{message}"
  else
    puts "  [FAIL] #{message}"
    exit 1
  end
end

puts "=== Crystal Audio Completion Callback Test (realtime, DataPlayedBack) ==="
puts ""

wav = "/tmp/crystal_completion_realtime.wav"

# ── Case 1: fires with the right index on a genuine end-of-file ──────────────
puts "1. Natural end-of-file fires on_track_finished with the track index ..."
generate_wav(wav, 0.4) # short so the test is quick
finished = [] of Int32
player = CrystalAudio::Player.new          # default completion type = DataPlayedBack
idx = player.add_track(wav, volume: 1.0_f32)
player.on_track_finished { |i| finished << i }
player.play
check(player.playing?, "player.playing? is true after play")

# Audio is ~0.4s; allow generous time for it to be heard + the callback to land.
fired = pump_until(3.0) { !finished.empty? }
check(fired, "completion callback fired within timeout")
check(finished == [idx], "fired with the added track index (#{idx}); got #{finished}")

# ── Case 2: does NOT fire on an explicit stop ───────────────────────────────
puts "2. Explicit stop does NOT fire on_track_finished ..."
generate_wav(wav, 3.0) # long, so it won't finish on its own during the window
finished2 = [] of Int32
player2 = CrystalAudio::Player.new
player2.add_track(wav, volume: 1.0_f32)
player2.on_track_finished { |i| finished2 << i }
player2.play
pump_until(0.3) { false } # let ~0.3s of the 3s file play
player2.stop              # explicit teardown — completion must be suppressed
pump_until(0.5) { false } # drain the run loop; nothing should arrive
check(finished2.empty?, "no completion fired on stop; got #{finished2}")

File.delete(wav) if File.exists?(wav)

puts ""
puts "=== All completion callback tests passed ==="
