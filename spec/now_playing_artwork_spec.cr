require "spec"
require "base64"
require "../src/crystal_audio"

# Exercises NowPlayingInfo's lock-screen album-art support (B2.4).
#
# Full VISUAL verification (the logo actually appearing on the lock screen)
# needs a real device. This spec proves the artwork CODE PATH runs without
# crashing: building an MPMediaItemArtwork from a file via the C helper,
# handling a missing file, and releasing it.
#
# NOTE: MPNowPlayingInfoCenter.defaultCenter is unavailable in a headless
# `crystal spec` process (no foreground app / audio session), so we cannot
# build a NowPlayingInfo here — that path is verified on-device + in the
# samples/lockscreen_test realtime check. We test the artwork BUILDER directly.
{% if flag?(:darwin) %}

# 1x1 transparent PNG (base64-decoded) — small valid image UIImage/NSImage loads.
private def write_test_png(path : String)
  b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  File.write(path, Base64.decode(b64))
end

describe "NowPlayingInfo artwork (ca_make_artwork)" do
  it "builds an MPMediaItemArtwork from a valid image file" do
    png = "/tmp/crystal_audio_artwork_spec.png"
    write_test_png(png)
    File.exists?(png).should be_true

    art = LibBlockBridge.ca_make_artwork(png.to_unsafe)
    art.null?.should be_false # non-null MPMediaItemArtwork*

    # Releasing the artwork (and the image it owns) must not crash.
    LibBlockBridge.ca_artwork_release(art)

    File.delete(png) if File.exists?(png)
  end

  it "returns NULL for a missing image file (caller then omits artwork)" do
    missing = "/tmp/crystal_audio_artwork_missing_#{Random.rand(1_000_000)}.png"
    File.exists?(missing).should be_false
    art = LibBlockBridge.ca_make_artwork(missing.to_unsafe)
    art.null?.should be_true
  end

  it "is safe to release a null artwork pointer" do
    LibBlockBridge.ca_artwork_release(Pointer(Void).null)
  end

  # If MPNowPlayingInfoCenter happens to be available (e.g. a future test host),
  # exercise the full update path including the artwork cache. Skipped headless.
  it "caches artwork across per-second updates when the center is available" do
    center = CrystalAudio::ObjC.send(
      LibObjC.objc_getClass("MPNowPlayingInfoCenter").as(LibObjC::Id),
      "defaultCenter"
    )
    pending! "MPNowPlayingInfoCenter unavailable in headless spec" if center.null?

    png = "/tmp/crystal_audio_artwork_spec_full.png"
    write_test_png(png)
    info = CrystalAudio::NowPlayingInfo.new
    info.update(title: "T", artist: "CA", duration: 10.0, rate: 1.0, artwork_path: png)
    5.times { |i| info.update(title: "T", elapsed: i.to_f64, rate: 1.0, artwork_path: png) }
    info.update(title: "T", elapsed: 5.0, rate: 0.0, artwork_path: png) # pause
    info.update(title: "T", rate: 1.0) # nil path drops artwork
    info.clear
    File.delete(png) if File.exists?(png)
  end
end

{% end %}
