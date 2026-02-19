# crystal-audio: Cross-platform audio library for Crystal
#
# Microphone capture, multi-track playback, system audio recording,
# and on-device transcription via whisper.cpp.
#
# Requires:
#   - macOS 13.0+ (or iOS 16+ with crystal-alpha compiler)
#   - Native extensions compiled: `make ext`
#   - Link flags: see Makefile

require "./crystal_audio/platform"
require "./crystal_audio/foundation/core_foundation"
require "./crystal_audio/foundation/objc_bridge"
require "./crystal_audio/audio/block_bridge"
require "./crystal_audio/audio/audio_toolbox"
require "./crystal_audio/audio/av_foundation"
require "./crystal_audio/audio/system_audio"
require "./crystal_audio/recorder"
require "./crystal_audio/player"
require "./crystal_audio/transcription/whisper"
require "./crystal_audio/transcription/pipeline"

module CrystalAudio
  VERSION = "0.1.0"
end
