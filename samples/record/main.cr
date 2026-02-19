require "../../src/crystal_audio"

# crystal-audio — simple recorder
#
# Usage:
#   record                      record mic for 5s → /tmp/recording.wav
#   record 30                   record mic for 30s
#   record meeting              record system + mic simultaneously
#   record meeting 60           meeting mode, 60 seconds
#   record dictation 10 ~/notes.wav
#
# Modes:
#   mic        Microphone only (default)
#   meeting    System audio + microphone in parallel
#   system     System audio only
#
# Build:   make record
# Run:     samples/record/record

{% unless flag?(:darwin) %}
  STDERR.puts "Error: crystal-audio requires macOS."
  exit 1
{% end %}

# ── Parse args ──────────────────────────────────────────────────────────────

args = ARGV.dup

# First arg: mode or duration
mode_str  = "mic"
duration  = 5.0
out_path  = ""
mic_path  = ""

if args.first? =~ /\A(mic|meeting|system|dictation)\z/i
  mode_str = args.shift.downcase
end

if args.first? =~ /\A\d+(\.\d+)?\z/
  duration = args.shift.to_f
end

if args.first?
  out_path = args.shift
end

# Derive paths
case mode_str
when "meeting"
  out_path = out_path.empty? ? "/tmp/meeting_system_#{Time.local.to_s("%Y%m%d_%H%M%S")}.wav" : out_path
  mic_path = out_path.sub(".wav", "_dictation.wav").sub("_system", "")
when "system"
  out_path = out_path.empty? ? "/tmp/system_audio_#{Time.local.to_s("%Y%m%d_%H%M%S")}.wav" : out_path
else # mic / dictation
  out_path = out_path.empty? ? "/tmp/recording_#{Time.local.to_s("%Y%m%d_%H%M%S")}.wav" : out_path
end

source = case mode_str
         when "meeting" then CrystalAudio::RecordingSource::Both
         when "system"  then CrystalAudio::RecordingSource::System
         else                CrystalAudio::RecordingSource::Microphone
         end

# ── Display ─────────────────────────────────────────────────────────────────

puts ""
puts "  crystal-audio recorder"
puts "  ─────────────────────────────────────"
puts "  Mode     : #{mode_str}"
puts "  Duration : #{duration}s"
case source
when CrystalAudio::RecordingSource::Both
  puts "  System   → #{out_path}"
  puts "  Mic      → #{mic_path}"
else
  puts "  Output   → #{out_path}"
end
puts "  ─────────────────────────────────────"
puts "  Press Ctrl+C to stop early"
puts ""

# ── Record ──────────────────────────────────────────────────────────────────

recorder = CrystalAudio::Recorder.new(
  source:          source,
  output_path:     out_path,
  mic_output_path: mic_path.empty? ? nil : mic_path
)

stopped = false

Signal::INT.trap do
  unless stopped
    stopped = true
    puts "\r  Stopping...                    "
    recorder.stop
    puts ""
    puts "  Done."
    exit 0
  end
end

recorder.start
puts "  ● Recording"

# Progress indicator
elapsed = 0.0
step    = 0.5
while elapsed < duration && !stopped
  sleep step.seconds
  elapsed += step
  bar_width = 30
  filled = (elapsed / duration * bar_width).to_i.clamp(0, bar_width)
  bar = "█" * filled + "░" * (bar_width - filled)
  remaining = (duration - elapsed).ceil.to_i
  print "\r  [#{bar}] #{remaining}s remaining   "
  STDOUT.flush
end

unless stopped
  recorder.stop
  puts ""
  puts ""
  puts "  Done."
  puts ""
  case source
  when CrystalAudio::RecordingSource::Both
    puts "  System audio → #{out_path}"
    puts "  Mic audio    → #{mic_path}"
    puts ""
    puts "  Play:  afplay \"#{out_path}\""
  else
    puts "  Saved  → #{out_path}"
    puts ""
    puts "  Play:  afplay \"#{out_path}\""
  end
  puts ""
end
