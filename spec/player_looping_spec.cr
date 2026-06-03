{% if flag?(:darwin) %}
require "spec"
require "../src/crystal_audio"

# Machine-verification for looping playback (CrystalAudio::Player#add_track loop:).
#
# There is no audio device / ear-check available headlessly, so we verify the
# LOOP deterministically via AVAudioEngine OFFLINE manual rendering: render the
# graph to a PCM buffer (no device, no permissions) and inspect the samples.
#
# Proof: render past the source file's single-play length. A LOOPING track still
# has audio there; a one-shot track is silent (the control case below).

# Write a minimal 16-bit PCM mono WAV (sine tone) — AVAudioFile reads it and
# converts to the float processingFormat used for rendering.
private def write_sine_wav(path : String, seconds : Float64, freq : Float64 = 440.0, rate : Int32 = 44100)
  n = (seconds * rate).to_i
  data_bytes = n * 2
  File.open(path, "w") do |f|
    f.write("RIFF".to_slice)
    f.write_bytes((36 + data_bytes).to_u32, IO::ByteFormat::LittleEndian)
    f.write("WAVE".to_slice)
    f.write("fmt ".to_slice)
    f.write_bytes(16_u32, IO::ByteFormat::LittleEndian)              # fmt chunk size
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)              # PCM
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)              # channels = mono
    f.write_bytes(rate.to_u32, IO::ByteFormat::LittleEndian)        # sample rate
    f.write_bytes((rate * 2).to_u32, IO::ByteFormat::LittleEndian)  # byte rate (rate*ch*2)
    f.write_bytes(2_u16, IO::ByteFormat::LittleEndian)              # block align (ch*2)
    f.write_bytes(16_u16, IO::ByteFormat::LittleEndian)             # bits per sample
    f.write("data".to_slice)
    f.write_bytes(data_bytes.to_u32, IO::ByteFormat::LittleEndian)
    n.times do |i|
      s = Math.sin(2.0 * Math::PI * freq * i / rate) * 0.5
      f.write_bytes((s * 32767.0).to_i16, IO::ByteFormat::LittleEndian)
    end
  end
end

describe CrystalAudio::Player do
  describe "looping playback (offline-render verification)" do
    wav = "/tmp/crystal_audio_loop_test.wav"

    it "a looping track keeps producing audio past its single-play length" do
      write_sine_wav(wav, 0.1)
      file = CrystalAudio::AVAudioFile.new(wav)
      file_frames = file.length.to_u32                  # ~4410
      fmt = file.processing_format
      max_frames = file_frames * 3_u32                  # render window > 2x single play

      player = CrystalAudio::Player.new
      player.add_track(wav, 1.0_f32, loop: true)
      player.enable_offline_rendering(fmt, max_frames).should be_true

      out_buf = CrystalAudio::ObjC.pcm_buffer_create(player.manual_rendering_format, max_frames)
      out_buf.should_not be_nil
      out_buf = out_buf.not_nil!

      player.play
      status = player.render_offline(max_frames, out_buf)
      status.should eq(0_i64)
      CrystalAudio::ObjC.pcm_buffer_frame_length(out_buf).should be >= (file_frames * 2_u32)

      rms_first  = CrystalAudio::ObjC.pcm_buffer_rms(out_buf, 0_u32, file_frames)
      rms_second = CrystalAudio::ObjC.pcm_buffer_rms(out_buf, file_frames, file_frames)
      rms_first.should be > 0.05
      rms_second.should be > 0.05                        # ← proof the loop replayed
    end

    it "a non-looping track is silent past its single-play length (control)" do
      write_sine_wav(wav, 0.1)
      file = CrystalAudio::AVAudioFile.new(wav)
      file_frames = file.length.to_u32
      fmt = file.processing_format
      max_frames = file_frames * 3_u32

      player = CrystalAudio::Player.new
      player.add_track(wav, 1.0_f32, loop: false)
      player.enable_offline_rendering(fmt, max_frames).should be_true
      out_buf = CrystalAudio::ObjC.pcm_buffer_create(player.manual_rendering_format, max_frames).not_nil!

      player.play
      player.render_offline(max_frames, out_buf)

      rms_first  = CrystalAudio::ObjC.pcm_buffer_rms(out_buf, 0_u32, file_frames)
      rms_second = CrystalAudio::ObjC.pcm_buffer_rms(out_buf, file_frames, file_frames)
      rms_first.should be > 0.05
      rms_second.should be < 0.01                        # ← one-shot: silent after one play
    end
  end

  describe "position + duration (offline-render verification)" do
    wav = "/tmp/crystal_audio_pos_test.wav"

    it "reports a track's duration in seconds from its file" do
      write_sine_wav(wav, 0.1)
      player = CrystalAudio::Player.new
      player.add_track(wav, 1.0_f32)
      player.duration_seconds(0).should be_close(0.1, 0.02)
    end

    it "advances a track's playback position as the engine renders" do
      write_sine_wav(wav, 0.5)
      file = CrystalAudio::AVAudioFile.new(wav)
      fmt = file.processing_format
      rate = file.sample_rate
      render_frames = (rate * 0.2).to_u32                 # render 0.2s

      player = CrystalAudio::Player.new
      player.add_track(wav, 1.0_f32)
      player.position_seconds(0).should eq(0.0)           # nothing rendered yet

      player.enable_offline_rendering(fmt, render_frames).should be_true
      out_buf = CrystalAudio::ObjC.pcm_buffer_create(player.manual_rendering_format, render_frames).not_nil!
      player.play
      player.render_offline(render_frames, out_buf)

      player.position_seconds(0).should be_close(0.2, 0.05)  # ~0.2s elapsed
    end
  end
end
{% end %}
