require "../../src/crystal_audio"

# Microphone recorder sample
#
# Records microphone audio to a WAV file for the specified duration.
# Uses AudioQueue (pure C callback, no block bridge required).
#
# Build: make sample
# Run:   samples/mic_recorder/mic_recorder [duration_seconds] [output_path]
#
# Examples:
#   samples/mic_recorder/mic_recorder
#   samples/mic_recorder/mic_recorder 10
#   samples/mic_recorder/mic_recorder 30 /tmp/my_recording.wav

duration_s   = (ARGV[0]? || "5").to_f
output_path  = ARGV[1]? || "/tmp/recording.wav"

{% unless flag?(:darwin) %}
  STDERR.puts "Error: crystal-audio microphone recording requires macOS or iOS."
  exit 1
{% end %}

puts "crystal-audio mic_recorder"
puts "  Duration : #{duration_s}s"
puts "  Output   : #{output_path}"
puts "  macOS    : #{CrystalAudio::MacOS.version.values.join(".")}"
puts

recorder = CrystalAudio::Recorder.new(
  source:      CrystalAudio::RecordingSource::Microphone,
  output_path: output_path
)

Signal::INT.trap do
  puts "\nStopping..."
  recorder.stop
  exit 0
end

puts "Recording... (Ctrl+C to stop early)"
recorder.start
sleep duration_s.seconds
recorder.stop

puts "Done. Wrote: #{output_path}"
puts "Play with: afplay #{output_path}"
