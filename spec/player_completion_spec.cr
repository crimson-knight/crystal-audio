{% if flag?(:darwin) %}
require "spec"
require "../src/crystal_audio"

# Machine-verification for the per-track completion callback
# (CrystalAudio::Player#on_track_finished).
#
# Threading note: the native AVAudioPlayerNode completion handler fires on an
# arbitrary audio thread; the C bridge (block_bridge.c) hops to the MAIN dispatch
# queue before invoking the Crystal proc. Under offline manual rendering the
# engine renders synchronously on the calling thread, but the dispatched block
# still needs the main run loop to be serviced — so after rendering we pump the
# run loop briefly to let the queued completion fire, then assert.
#
# COMPLETION-TYPE / OFFLINE CAVEAT (verified empirically, 2026-06-09):
# AVAudioPlayerNode's DataPlayedBack callback (the production default — fires
# when audio is genuinely HEARD and not on stop) does NOT fire under offline
# manual rendering, because nothing is played back to an output device. The
# DataRendered callback DOES fire offline (it signals the file's data was fully
# rendered). These specs therefore set completion_callback_type to DataRendered
# to verify the full wiring deterministically (block bridge → main-queue hop →
# Crystal proc → correct index → @stopping guard). The realtime DataPlayedBack
# path (incl. no-fire-on-stop on a real device) is proven by
# samples/completion_test/main.cr, which is compiled AND run.

private def write_sine_wav(path : String, seconds : Float64, freq : Float64 = 440.0, rate : Int32 = 44100)
  n = (seconds * rate).to_i
  data_bytes = n * 2
  File.open(path, "w") do |f|
    f.write("RIFF".to_slice)
    f.write_bytes((36 + data_bytes).to_u32, IO::ByteFormat::LittleEndian)
    f.write("WAVE".to_slice)
    f.write("fmt ".to_slice)
    f.write_bytes(16_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)              # PCM
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)              # mono
    f.write_bytes(rate.to_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes((rate * 2).to_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes(2_u16, IO::ByteFormat::LittleEndian)
    f.write_bytes(16_u16, IO::ByteFormat::LittleEndian)
    f.write("data".to_slice)
    f.write_bytes(data_bytes.to_u32, IO::ByteFormat::LittleEndian)
    n.times do |i|
      s = Math.sin(2.0 * Math::PI * freq * i / rate) * 0.5
      f.write_bytes((s * 32767.0).to_i16, IO::ByteFormat::LittleEndian)
    end
  end
end

# Run the main CFRunLoop for up to `timeout` seconds, returning early once
# `cond` becomes true. The completion handler is dispatched onto the main queue,
# which is serviced by the main run loop.
private def pump_until(timeout : Float64, &cond : -> Bool) : Bool
  deadline = Time.instant + timeout.seconds
  until cond.call
    return false if Time.instant >= deadline
    # CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true)
    LibCoreFoundation.CFRunLoopRunInMode(
      CrystalAudio::CF.default_run_loop_mode, 0.02, true)
  end
  true
end

describe CrystalAudio::Player do
  describe "#on_track_finished (offline-render verification)" do
    it "fires with the finished track index when a one-shot plays to its end" do
      wav = "/tmp/crystal_audio_completion_oneshot.wav"
      write_sine_wav(wav, 0.1)
      file = CrystalAudio::AVAudioFile.new(wav)
      file_frames = file.length.to_u32
      fmt = file.processing_format
      max_frames = file_frames * 3_u32 # render well past one play-through

      finished = [] of Int32
      player = CrystalAudio::Player.new
      player.completion_callback_type = CrystalAudio::ObjC::PLAYER_COMPLETION_DATA_RENDERED
      player.add_track(wav, 1.0_f32, loop: false)
      player.on_track_finished { |idx| finished << idx }

      player.enable_offline_rendering(fmt, max_frames).should be_true
      out_buf = CrystalAudio::ObjC.pcm_buffer_create(player.manual_rendering_format, max_frames).not_nil!

      player.play
      player.render_offline(max_frames, out_buf)

      # The completion is dispatched to the main queue; pump until it lands.
      pump_until(2.0) { !finished.empty? }

      finished.should eq([0])
    end

    it "does NOT fire for a looping track (loops never finish)" do
      wav = "/tmp/crystal_audio_completion_loop.wav"
      write_sine_wav(wav, 0.1)
      file = CrystalAudio::AVAudioFile.new(wav)
      file_frames = file.length.to_u32
      fmt = file.processing_format
      max_frames = file_frames * 3_u32

      finished = [] of Int32
      player = CrystalAudio::Player.new
      player.completion_callback_type = CrystalAudio::ObjC::PLAYER_COMPLETION_DATA_RENDERED
      player.add_track(wav, 1.0_f32, loop: true)
      player.on_track_finished { |idx| finished << idx }

      player.enable_offline_rendering(fmt, max_frames).should be_true
      out_buf = CrystalAudio::ObjC.pcm_buffer_create(player.manual_rendering_format, max_frames).not_nil!

      player.play
      player.render_offline(max_frames, out_buf)
      pump_until(0.5) { !finished.empty? } # give it a chance — must stay empty

      finished.should be_empty
    end

    it "does NOT fire on explicit stop (only on a genuine end-of-file)" do
      wav = "/tmp/crystal_audio_completion_stop.wav"
      write_sine_wav(wav, 0.5) # long enough that one render won't reach the end
      file = CrystalAudio::AVAudioFile.new(wav)
      fmt = file.processing_format
      render_frames = (file.sample_rate * 0.1).to_u32 # render only 0.1s of 0.5s

      finished = [] of Int32
      player = CrystalAudio::Player.new
      player.completion_callback_type = CrystalAudio::ObjC::PLAYER_COMPLETION_DATA_RENDERED
      player.add_track(wav, 1.0_f32, loop: false)
      player.on_track_finished { |idx| finished << idx }

      player.enable_offline_rendering(fmt, render_frames).should be_true
      out_buf = CrystalAudio::ObjC.pcm_buffer_create(player.manual_rendering_format, render_frames).not_nil!

      player.play
      player.render_offline(render_frames, out_buf) # partial — file not done
      player.stop                                   # explicit teardown
      pump_until(0.5) { !finished.empty? }          # must stay empty

      finished.should be_empty
    end
  end
end
{% end %}
