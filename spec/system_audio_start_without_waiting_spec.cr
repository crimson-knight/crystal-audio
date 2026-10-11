require "spec"
require "../src/crystal_audio"

{% if flag?(:darwin) %}
  # kAudioHardwareBadObjectError ('!obj'): system_audio_tap_create's answer to
  # a null callback, given before it asks the audio server for anything, so
  # these examples never create a tap or prompt for system audio access.
  BAD_OBJECT_ERROR = 0x216F626A

  private def null_tap_callback : LibSystemAudioTap::Callback
    LibSystemAudioTap::Callback.new(Pointer(Void).null, Pointer(Void).null)
  end

  describe "system_audio_tap_start_async" do
    it "creates the tap on its dispatch job and reports the creation error" do
      pending_start = LibSystemAudioTap.system_audio_tap_start_async(null_tap_callback, Pointer(Void).null, Pointer(Void).null)
      pending_start.null?.should be_false

      LibSystemAudioTap.system_audio_tap_wait_for_queue_start(pending_start).should eq(0)

      queue_status = -1
      was_tap_attempted = 0
      create_status = 0
      start_status = -1
      handle = LibSystemAudioTap.system_audio_tap_finish_start(
        pending_start, pointerof(queue_status), pointerof(was_tap_attempted),
        pointerof(create_status), pointerof(start_status)
      )

      handle.null?.should be_true
      queue_status.should eq(0)
      was_tap_attempted.should eq(1)
      create_status.should eq(BAD_OBJECT_ERROR)
      start_status.should eq(0)
    end

    it "reports the job finished once it has returned" do
      pending_start = LibSystemAudioTap.system_audio_tap_start_async(null_tap_callback, Pointer(Void).null, Pointer(Void).null)
      deadline = Time.instant + 5.seconds
      until LibSystemAudioTap.system_audio_tap_start_is_finished(pending_start) == 1
        fail "the start job did not finish within 5 s" if Time.instant > deadline
        sleep 1.millisecond
      end

      queue_status = 0
      was_tap_attempted = 0
      create_status = 0
      start_status = 0
      LibSystemAudioTap.system_audio_tap_finish_start(
        pending_start, pointerof(queue_status), pointerof(was_tap_attempted),
        pointerof(create_status), pointerof(start_status)
      ).null?.should be_true
      create_status.should eq(BAD_OBJECT_ERROR)
    end

    it "reports a finished start for a null pending start" do
      LibSystemAudioTap.system_audio_tap_start_is_finished(Pointer(Void).null).should eq(1)
    end
  end

  describe CrystalAudio::SystemAudioCapture::StartResult do
    describe "#started?" do
      it "is true only when the queue and both tap steps succeeded" do
        CrystalAudio::SystemAudioCapture::StartResult.new(0, true, 0, 0).started?.should be_true
        CrystalAudio::SystemAudioCapture::StartResult.new(-66681, false, 0, 0).started?.should be_false
        CrystalAudio::SystemAudioCapture::StartResult.new(0, true, BAD_OBJECT_ERROR, 0).started?.should be_false
        CrystalAudio::SystemAudioCapture::StartResult.new(0, true, 0, -50).started?.should be_false
      end
    end

    describe "#error_message" do
      it "names the tap step that failed, as a synchronous start does" do
        CrystalAudio::SystemAudioCapture::StartResult.new(0, true, BAD_OBJECT_ERROR, 0).error_message
          .should eq("system_audio_tap_create failed: OSStatus #{BAD_OBJECT_ERROR}")
        CrystalAudio::SystemAudioCapture::StartResult.new(0, true, 0, -50).error_message
          .should eq("system_audio_tap_start failed: OSStatus -50")
      end

      it "leaves a failed queue to its owner and is nil after a start" do
        CrystalAudio::SystemAudioCapture::StartResult.new(-66681, false, 0, 0).error_message.should be_nil
        CrystalAudio::SystemAudioCapture::StartResult.new(0, true, 0, 0).error_message.should be_nil
      end
    end
  end

  describe CrystalAudio::SystemAudioCapture do
    it "has no start pending before one begins" do
      capture = CrystalAudio::SystemAudioCapture.new

      capture.start_pending?.should be_false
      capture.start_finished?.should be_true
      capture.wait_for_queue_start.should eq(0)
      capture.active?.should be_false
    end
  end

  describe CrystalAudio::Recorder do
    describe "#start_finished?" do
      it "is true for every source when no start is pending" do
        {CrystalAudio::RecordingSource::Microphone,
         CrystalAudio::RecordingSource::System,
         CrystalAudio::RecordingSource::Both}.each do |source|
          CrystalAudio::Recorder.new(source: source).start_finished?.should be_true
        end
      end
    end

    describe "#wait_until_microphone_started" do
      it "returns at once when no start is pending" do
        rec = CrystalAudio::Recorder.new(source: CrystalAudio::RecordingSource::Both)

        rec.wait_until_microphone_started
        rec.wait_until_started

        rec.recording?.should be_false
      end
    end

    describe "#start_without_waiting" do
      it "leaves a Both recorder stopped when its microphone cannot be used" do
        system_path = File.tempname("crystal-audio-spec-system", ".wav")
        mic_path = File.tempname("crystal-audio-spec-mic", ".wav")
        rec = CrystalAudio::Recorder.new(
          source: CrystalAudio::RecordingSource::Both,
          output_path: system_path,
          mic_output_path: mic_path,
          input_device_uid: "crystal-audio-spec-invalid-device"
        )

        # Core Audio reports the unknown device when the queue selects it
        # (before the system file opens) or when the queue starts (and then
        # the tap is never created). Either way the recorder ends stopped.
        begin
          rec.start_without_waiting
          expect_raises(Exception, /AudioQueueStart failed/) do
            rec.wait_until_microphone_started
          end
        rescue CrystalAudio::InputDeviceSelectionError
          File.exists?(system_path).should be_false
        end

        rec.recording?.should be_false
        rec.start_finished?.should be_true
        rec.wait_until_started
      ensure
        {system_path, mic_path}.each { |path| File.delete(path) if path && File.exists?(path) }
      end

      it "reports a failed system file before anything starts" do
        rec = CrystalAudio::Recorder.new(
          source: CrystalAudio::RecordingSource::System,
          output_path: "/crystal-audio-spec-missing-directory/system.wav"
        )

        expect_raises(Exception, /ExtAudioFileCreateWithURL failed/) do
          rec.start_without_waiting
        end

        rec.recording?.should be_false
        rec.start_finished?.should be_true
      end
    end

    # Records the microphone and the system output: set
    # CRYSTAL_AUDIO_SPEC_SYSTEM_AUDIO=1 and CRYSTAL_AUDIO_SPEC_INPUT_DEVICE_UID
    # (for example BlackHole2ch_UID) to run it. macOS asks the running
    # process for system audio access on its first run.
    if (input_device_uid = ENV["CRYSTAL_AUDIO_SPEC_INPUT_DEVICE_UID"]?) && ENV["CRYSTAL_AUDIO_SPEC_SYSTEM_AUDIO"]? == "1"
      it "records both sources after a start that does not block the caller" do
        system_path = File.tempname("crystal-audio-spec-system", ".wav")
        mic_path = File.tempname("crystal-audio-spec-mic", ".wav")
        CrystalAudio::Recorder.warm_up_input(input_device_uid)
        rec = CrystalAudio::Recorder.new(
          source: CrystalAudio::RecordingSource::Both,
          output_path: system_path,
          mic_output_path: mic_path,
          input_device_uid: input_device_uid
        )

        started_at = Time.instant
        rec.start_without_waiting
        (Time.instant - started_at).should be < 30.milliseconds
        rec.recording?.should be_true
        rec.wait_until_microphone_started
        rec.wait_until_started
        rec.start_finished?.should be_true
        sleep 300.milliseconds
        rec.stop

        rec.recording?.should be_false
        File.size(mic_path).should be > 44 + 8_820
        File.size(system_path).should be > 44
      ensure
        {system_path, mic_path}.each { |path| File.delete(path) if path && File.exists?(path) }
      end
    end
  end
{% end %}
