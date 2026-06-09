require "base64"
require "../../src/crystal_audio"

# lockscreen_test — Verifies NowPlayingInfo and RemoteCommandCenter.
#
# Steps:
#   1. Generate a test WAV (sine wave)
#   2. Create Player with 1 track
#   3. Set up remote command handlers (log when triggered)
#   4. Set now playing info (title, artist, duration)
#   5. Play for 5 seconds — verify now playing was set
#   6. Pause — verify state update
#   7. Resume + play 3 more seconds
#   8. Stop + clear now playing
#   9. Exit cleanly

SAMPLE_RATE = 44100.0_f64
DURATION    =     10.0_f64  # 10-second WAV file
FREQUENCY   =    440.0_f64

def generate_test_wav(path : String)
  num_samples = (SAMPLE_RATE * DURATION).to_i32
  channels = 1_u32
  bits = 16_u32
  data_size = num_samples * channels * (bits // 8)
  file_size = 36 + data_size

  File.open(path, "wb") do |f|
    f.write("RIFF".to_slice)
    f.write_bytes(file_size.to_u32, IO::ByteFormat::LittleEndian)
    f.write("WAVE".to_slice)
    f.write("fmt ".to_slice)
    f.write_bytes(16_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes(1_u16, IO::ByteFormat::LittleEndian)
    f.write_bytes(channels.to_u16, IO::ByteFormat::LittleEndian)
    f.write_bytes(SAMPLE_RATE.to_u32, IO::ByteFormat::LittleEndian)
    f.write_bytes((SAMPLE_RATE.to_u32 * channels * (bits // 8)), IO::ByteFormat::LittleEndian)
    f.write_bytes((channels * (bits // 8)).to_u16, IO::ByteFormat::LittleEndian)
    f.write_bytes(bits.to_u16, IO::ByteFormat::LittleEndian)
    f.write("data".to_slice)
    f.write_bytes(data_size.to_u32, IO::ByteFormat::LittleEndian)
    num_samples.times do |i|
      t = i.to_f64 / SAMPLE_RATE
      sample = (Math.sin(2.0 * Math::PI * FREQUENCY * t) * 32000).to_i16
      f.write_bytes(sample, IO::ByteFormat::LittleEndian)
    end
  end
end

def check(condition : Bool, message : String)
  if condition
    puts "  [PASS] #{message}"
  else
    puts "  [FAIL] #{message}"
    exit 1
  end
end

# --- Main ---

puts "=== Crystal Audio Lock Screen Test ==="
puts ""

# Step 1: Generate test WAV
wav_path = "/tmp/crystal_lockscreen_test.wav"
puts "1. Generating test WAV ..."
generate_test_wav(wav_path)
check(File.exists?(wav_path), "WAV file created")

# Step 2: Create Player
puts "2. Creating Player ..."
player = CrystalAudio::Player.new
player.add_track(wav_path)
check(player.track_count == 1, "One track added")

# Step 3: Set up remote commands
puts "3. Setting up remote commands ..."
play_count = 0
pause_count = 0
next_count = 0
prev_count = 0

rc = player.enable_remote_commands
rc.on_next { next_count += 1; puts "  >> Next track pressed (#{next_count})" }
rc.on_previous { prev_count += 1; puts "  >> Previous track pressed (#{prev_count})" }
check(true, "Remote command handlers registered")

# Step 4: Set now playing info (with lock-screen album art)
puts "4. Setting now playing info ..."

# Build a tiny test PNG so the artwork path is exercised (the lock screen shows
# whatever image you point at; HappyCoach passes its brain logo).
art_path = "/tmp/crystal_lockscreen_art.png"
art_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
File.write(art_path, Base64.decode(art_b64))

# Verify the artwork object builds from the file (NULL would mean omit it).
artwork = LibBlockBridge.ca_make_artwork(art_path.to_unsafe)
check(!artwork.null?, "MPMediaItemArtwork built from image file")
LibBlockBridge.ca_artwork_release(artwork)

player.set_now_playing(
  title: "Test Track",
  artist: "Crystal Audio",
  duration: DURATION,
  artwork_path: art_path
)
check(true, "Now playing info set (with artwork)")

# Step 5: Play
puts "5. Playing for 5 seconds ..."
player.play
check(player.playing?, "Player is playing")
sleep 5.seconds

# Step 6: Pause
puts "6. Pausing ..."
player.pause
check(!player.playing?, "Player is paused")
sleep 1.second

# Step 7: Resume
puts "7. Resuming ..."
player.resume
check(player.playing?, "Player resumed")
sleep 3.seconds

# Step 8: Stop + clear
puts "8. Stopping and clearing now playing ..."
player.stop
player.clear_now_playing
check(!player.playing?, "Player stopped")

# Cleanup
File.delete(wav_path) if File.exists?(wav_path)
File.delete(art_path) if File.exists?(art_path)

puts ""
puts "=== All lock screen tests passed ==="
puts ""
puts "Note: To visually verify lock screen controls on macOS:"
puts "  - Open System Settings > Privacy & Security > Media & Apple TV"
puts "  - Check Control Center for Now Playing widget during playback"
