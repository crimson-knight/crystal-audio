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
