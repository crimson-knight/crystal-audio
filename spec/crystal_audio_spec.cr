require "spec"
require "../src/crystal_audio"

describe CrystalAudio do
  it "has a version" do
    CrystalAudio::VERSION.should_not be_empty
  end
end

{% if flag?(:darwin) %}
  describe CrystalAudio::MacOS do
    it "detects macOS version" do
      v = CrystalAudio::MacOS.version
      v[:major].should be >= 13
    end

    it "reports process tap availability correctly" do
      v = CrystalAudio::MacOS.version
      expected = v[:major] > 14 || (v[:major] == 14 && v[:minor] >= 2)
      CrystalAudio::MacOS.process_tap?.should eq(expected)
    end
  end

  describe CrystalAudio::Recorder do
    it "initializes with default options" do
      rec = CrystalAudio::Recorder.new
      rec.source.should eq(CrystalAudio::RecordingSource::Microphone)
      rec.recording?.should be_false
      rec.input_device_uid.should be_nil
    end

    it "stores a selected input device UID" do
      rec = CrystalAudio::Recorder.new(input_device_uid: "BlackHole2ch_UID")

      rec.input_device_uid.should eq("BlackHole2ch_UID")
      rec.recording?.should be_false
    end

    it "uses input buffers that can produce one thousand callbacks per minute" do
      bytes_per_second = CrystalAudio::Recorder::SAMPLE_RATE *
                         CrystalAudio::Recorder::CHANNELS *
                         (CrystalAudio::Recorder::BITS_PER_SAMPLE / 8)
      callbacks_per_minute = bytes_per_second * 60 /
                             CrystalAudio::Recorder::BUFFER_SIZE

      callbacks_per_minute.should be >= 1_000.0
    end

    it "raises a named error when the current input device cannot be selected" do
      error = expect_raises(CrystalAudio::InputDeviceSelectionError) do
        CrystalAudio::AudioQueue.set_current_input_device(
          Pointer(Void).null,
          "crystal-audio-spec-invalid-device"
        )
      end

      error.input_device_uid.should eq("crystal-audio-spec-invalid-device")
      error.status.should_not eq(0)
    end

    it "warms up the input path without starting a recording" do
      CrystalAudio::Recorder.warm_up_input
      CrystalAudio::Recorder.warm_up_input("crystal-audio-spec-invalid-device")

      CrystalAudio::Recorder.new.recording?.should be_false
    end

    it "returns at once from wait_until_started when no start is pending" do
      rec = CrystalAudio::Recorder.new

      rec.wait_until_started

      rec.recording?.should be_false
    end

    it "leaves the recorder stopped when a non-blocking start cannot use the input device" do
      output_path = File.tempname("crystal-audio-spec", ".wav")
      rec = CrystalAudio::Recorder.new(
        output_path: output_path,
        input_device_uid: "crystal-audio-spec-invalid-device"
      )

      # Core Audio reports an unknown device either when the queue selects it
      # or when the queue starts; both must leave the recorder stopped.
      begin
        rec.start_without_waiting
        expect_raises(Exception, /AudioQueueStart failed/) do
          rec.wait_until_started
        end
      rescue CrystalAudio::InputDeviceSelectionError
      end

      rec.recording?.should be_false
    ensure
      File.delete(output_path) if output_path && File.exists?(output_path)
    end

    # Records from a real input device: set CRYSTAL_AUDIO_SPEC_INPUT_DEVICE_UID
    # (for example BlackHole2ch_UID) to run it.
    if input_device_uid = ENV["CRYSTAL_AUDIO_SPEC_INPUT_DEVICE_UID"]?
      it "records audio after a non-blocking start" do
        output_path = File.tempname("crystal-audio-spec", ".wav")
        CrystalAudio::Recorder.warm_up_input(input_device_uid)
        rec = CrystalAudio::Recorder.new(output_path: output_path, input_device_uid: input_device_uid)

        rec.start_without_waiting
        rec.recording?.should be_true
        rec.wait_until_started
        sleep 300.milliseconds
        rec.stop

        rec.recording?.should be_false
        # A 44-byte WAV header plus at least 100 ms of 16-bit mono samples.
        File.size(output_path).should be > 44 + 8_820
      ensure
        File.delete(output_path) if output_path && File.exists?(output_path)
      end
    end

    it "initializes with all sources" do
      rec = CrystalAudio::Recorder.new(
        source: CrystalAudio::RecordingSource::Both,
        output_path: "/tmp/test_system.wav",
        mic_output_path: "/tmp/test_mic.wav"
      )
      rec.output_path.should eq("/tmp/test_system.wav")
      rec.mic_output_path.should eq("/tmp/test_mic.wav")
    end
  end

  describe CrystalAudio::AudioEngine do
    it "initializes AVAudioEngine" do
      engine = CrystalAudio::AudioEngine.new
      engine.ptr.should_not be_nil
      engine.running?.should be_false
    end

    it "provides input and output nodes" do
      engine = CrystalAudio::AudioEngine.new
      engine.input_node.should_not be_nil
      engine.output_node.should_not be_nil
      engine.main_mixer_node.should_not be_nil
    end
  end

  describe CrystalAudio::AudioPlayerNode do
    it "initializes an AVAudioPlayerNode" do
      node = CrystalAudio::AudioPlayerNode.new
      node.ptr.should_not be_nil
      node.playing?.should be_false
    end

    it "sets and gets volume" do
      node = CrystalAudio::AudioPlayerNode.new
      node.volume = 0.5_f32
      node.volume.should be_close(0.5_f32, 0.001_f32)
    end
  end

  describe CrystalAudio::Player do
    it "initializes with no tracks" do
      player = CrystalAudio::Player.new
      player.track_count.should eq(0)
      player.playing?.should be_false
      player.master_volume.should eq(1.0_f32)
    end
  end
{% end %}

describe CrystalAudio::Transcription::TranscribeConfig do
  it "has sensible defaults" do
    config = CrystalAudio::Transcription::TranscribeConfig.new
    config.language.should eq("en")
    config.translate.should be_false
    config.no_speech_thold.should eq(0.6_f32)
  end
end

describe CrystalAudio::Transcription::Segment do
  it "formats timestamps" do
    seg = CrystalAudio::Transcription::Segment.new("Hello world", 5_000_i64, 7_500_i64)
    seg.duration_ms.should eq(2_500)
    seg.t0_ms.should eq(5_000)
  end
end

describe CrystalAudio::Transcription::Pipeline do
  it "initializes with default mode" do
    pipeline = CrystalAudio::Transcription::Pipeline.new
    pipeline.mode.should eq(CrystalAudio::Transcription::PipelineMode::Dictation)
  end
end
