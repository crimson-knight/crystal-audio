require "spec"
require "../../src/crystal_audio"

{% if flag?(:audio_setup_fixture) %}
  lib LibAudioSetupFixture
    fun setup_fixture_reset(step : Int32) : Void
    fun setup_fixture_queue_disposals : Int32
    fun setup_fixture_file_disposals : Int32
    fun setup_fixture_synchronous_starts : Int32
  end

  describe "Native recorder setup failure cleanup" do
    {
      {0, "ExtAudioFileCreateWithURL failed: -50", 0},
      {1, "ExtAudioFileSetProperty failed: -50", 0},
      {2, "AudioQueueNewInput failed: -50", 1},
      {3, "AudioQueueAllocateBuffer failed: -50", 1},
      {4, "AudioQueueEnqueueBuffer failed: -50", 1},
      {5, "AudioQueue start could not be scheduled", 1},
    }.each do |step, failure_message, expected_queue_disposals|
      it "releases prepared handles after #{failure_message}" do
        LibAudioSetupFixture.setup_fixture_reset(step)
        recorder = CrystalAudio::Recorder.new(output_path: "/tmp/audio-setup-fixture.wav")
        expect_raises(Exception, failure_message) { recorder.start_without_waiting }
        recorder.recording?.should be_false
        LibAudioSetupFixture.setup_fixture_file_disposals.should eq(1)
        LibAudioSetupFixture.setup_fixture_queue_disposals.should eq(expected_queue_disposals)
        LibAudioSetupFixture.setup_fixture_synchronous_starts.should eq(0)
      ensure
        recorder.try(&.stop)
      end
    end
  end
{% end %}
