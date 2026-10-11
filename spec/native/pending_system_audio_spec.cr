require "spec"
require "../../src/crystal_audio"

{% if flag?(:audio_pending_fixture) %}
  # This entry point links the controlled C boundary instead of the Core Audio
  # tap. The production Crystal wrapper owns confirmation, callback and stop.
  lib LibPendingAudioFixture
    fun pending_fixture_reset(allocation : Int32, creation : Int32) : Void
    fun pending_fixture_release : Void
    fun pending_fixture_release_after_delay : Void
    fun pending_fixture_stop_started : Void
    fun pending_fixture_stop_finished : Void
    fun pending_fixture_wait_for_finish : Int32
    fun pending_fixture_wait_for_stop : Int32
    fun pending_fixture_finishes : Int32
    fun pending_fixture_destroys : Int32
    fun pending_fixture_synchronous_creates : Int32
    fun pending_fixture_callback : Void
  end

  describe "Native pending system-audio ownership" do
    it "reports recorder startup unfinished promptly while its native waiter owns the handles" do
      LibPendingAudioFixture.pending_fixture_reset(0, 0)
      recorder = CrystalAudio::Recorder.new(source: CrystalAudio::RecordingSource::System, output_path: File.join(Dir.tempdir, "pending-recorder-fixture-#{Process.pid}.wav"))
      recorder.start_without_waiting
      confirmer = Thread.new { recorder.wait_until_started }
      LibPendingAudioFixture.pending_fixture_wait_for_finish.should eq(1)
      releaser = Thread.new { LibPendingAudioFixture.pending_fixture_release_after_delay }
      started_at = Time.instant
      was_finished = recorder.start_finished?
      elapsed_ms = (Time.instant - started_at).total_milliseconds
      confirmer.join
      releaser.join
      recorder.stop
      was_finished.should be_false
      elapsed_ms.should be < 50.0
      LibPendingAudioFixture.pending_fixture_finishes.should eq(1)
      LibPendingAudioFixture.pending_fixture_destroys.should eq(1)
    end

    it "reports unfinished promptly while a native finisher still owns the start" do
      LibPendingAudioFixture.pending_fixture_reset(0, 0)
      capture = CrystalAudio::SystemAudioCapture.new
      capture.start_without_waiting { |_, _, _| }
      confirmer = Thread.new { capture.finish_start }
      LibPendingAudioFixture.pending_fixture_wait_for_finish.should eq(1)
      releaser = Thread.new { LibPendingAudioFixture.pending_fixture_release_after_delay }
      started_at = Time.instant
      was_finished = capture.start_finished?
      elapsed_ms = (Time.instant - started_at).total_milliseconds
      confirmer.join
      releaser.join
      capture.stop
      was_finished.should be_false
      elapsed_ms.should be < 50.0
      LibPendingAudioFixture.pending_fixture_destroys.should eq(1)
    end

    it "retains its callback while pending and releases the successful tap once" do
      LibPendingAudioFixture.pending_fixture_reset(0, 0)
      callback_count = 0
      capture = CrystalAudio::SystemAudioCapture.new
      capture.start_without_waiting do |frames, frame_count, channel_count|
        frames.size.should eq(2)
        frame_count.should eq(1)
        channel_count.should eq(2)
        callback_count += 1
      end
      capture.start_pending?.should be_true
      capture.start_finished?.should be_false
      LibPendingAudioFixture.pending_fixture_callback
      callback_count.should eq(1)
      LibPendingAudioFixture.pending_fixture_release
      capture.finish_start.started?.should be_true
      capture.stop
      capture.stop
      LibPendingAudioFixture.pending_fixture_finishes.should eq(1)
      LibPendingAudioFixture.pending_fixture_destroys.should eq(1)
      capture.active?.should be_false
    end

    it "serializes stop behind an in-flight finisher and destroys its late handle" do
      LibPendingAudioFixture.pending_fixture_reset(0, 0)
      capture = CrystalAudio::SystemAudioCapture.new
      capture.start_without_waiting { |_, _, _| }
      confirmer = Thread.new { capture.finish_start }
      LibPendingAudioFixture.pending_fixture_wait_for_finish.should eq(1)
      stopper = Thread.new do
        LibPendingAudioFixture.pending_fixture_stop_started
        capture.stop
        LibPendingAudioFixture.pending_fixture_stop_finished
      end
      stopped_before_completion = LibPendingAudioFixture.pending_fixture_wait_for_stop
      LibPendingAudioFixture.pending_fixture_release
      confirmer.join
      stopper.join
      stopped_before_completion.should eq(0)
      capture.active?.should be_false
      LibPendingAudioFixture.pending_fixture_finishes.should eq(1)
      LibPendingAudioFixture.pending_fixture_destroys.should eq(1)
    end

    it "reports missing tap creation with the original zero OSStatus" do
      LibPendingAudioFixture.pending_fixture_reset(0, 1)
      capture = CrystalAudio::SystemAudioCapture.new
      capture.start_without_waiting { |_, _, _| }
      LibPendingAudioFixture.pending_fixture_release
      result = capture.finish_start
      result.started?.should be_false
      result.error_message.should eq("system_audio_tap_create failed: OSStatus 0")
      capture.active?.should be_false
      capture.stop
      LibPendingAudioFixture.pending_fixture_finishes.should eq(1)
    end

    it "reports allocation failure promptly through its async entry point" do
      LibPendingAudioFixture.pending_fixture_reset(1, 0)
      capture = CrystalAudio::SystemAudioCapture.new
      expect_raises(Exception, "system audio start could not be scheduled") do
        capture.start_without_waiting { |_, _, _| }
      end
      capture.start_pending?.should be_false
      capture.active?.should be_false
      LibPendingAudioFixture.pending_fixture_synchronous_creates.should eq(0)
    end
  end
{% end %}
