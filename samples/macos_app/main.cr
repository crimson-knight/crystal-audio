{% unless flag?(:darwin) %}
  STDERR.puts "Error: crystal-audio macOS app requires macOS."
  exit 1
{% end %}

require "../../src/crystal_audio"

# ── AppKit / ObjC helper bindings ────────────────────────────────────────────

@[Link(framework: "AppKit")]
lib LibAppKit
end

lib LibAppKitHelpers
  # NSString
  fun ca_nsstring(cstr : LibC::Char*) : Void*

  # NSApplication
  fun ca_nsapp : Void*
  fun ca_nsapp_set_policy(app : Void*, policy : Int64)
  fun ca_nsapp_activate(app : Void*)
  fun ca_nsapp_run(app : Void*)
  fun ca_nsapp_stop(app : Void*)
  fun ca_nsapp_post_empty_event(app : Void*)
  fun ca_nsapp_pump_events(app : Void*)
  fun ca_observe_window_close(win : Void*)
  fun ca_window_should_close : Bool

  # NSWindow
  fun ca_nswindow_create(x : Float64, y : Float64, w : Float64, h : Float64,
                         style_mask : UInt64) : Void*
  fun ca_nswindow_set_title(win : Void*, title : LibC::Char*)
  fun ca_nswindow_show(win : Void*)
  fun ca_nswindow_center(win : Void*)
  fun ca_nswindow_content_view(win : Void*) : Void*

  # NSView
  fun ca_view_add_subview(view : Void*, subview : Void*)

  # NSTextField / Label
  fun ca_nslabel_create(x : Float64, y : Float64, w : Float64, h : Float64) : Void*
  fun ca_nslabel_set_text(label : Void*, text : LibC::Char*)
  fun ca_nslabel_set_alignment(label : Void*, alignment : Int64)
  fun ca_nslabel_set_font(label : Void*, font : Void*)
  fun ca_nslabel_set_color(label : Void*, color : Void*)

  # NSFont
  fun ca_nsfont_system(size : Float64) : Void*
  fun ca_nsfont_bold(size : Float64) : Void*

  # NSButton
  fun ca_nsbutton_create(x : Float64, y : Float64, w : Float64, h : Float64,
                         title : LibC::Char*) : Void*
  fun ca_nsbutton_set_title(btn : Void*, title : LibC::Char*)
  fun ca_nsbutton_set_enabled(btn : Void*, enabled : Bool)

  # NSSegmentedControl
  fun ca_nssegmented_create(x : Float64, y : Float64, w : Float64, h : Float64,
                             labels : Void**, count : Int32) : Void*
  fun ca_nssegmented_selected(sc : Void*) : Int64

  # NSColor
  fun ca_nscolor_red : Void*
  fun ca_nscolor_label : Void*

  # C-based button action target (avoids Crystal ObjC class + ARC issues)
  # callback is a plain C function: void (*)(void)
  fun ca_button_target_create(callback : Void*) : Void*
  fun ca_button_set_action(btn : Void*, target : Void*)
end

# ── Application state module ──────────────────────────────────────────────────

module AppState
  @@recording    = false
  @@recorder     : CrystalAudio::Recorder? = nil
  @@start_time   : Time? = nil
  @@out_path     = ""

  # UI widget pointers — set once during setup, accessed from callbacks
  @@btn_record   = Pointer(Void).null
  @@lbl_status   = Pointer(Void).null
  @@lbl_timer    = Pointer(Void).null
  @@lbl_path     = Pointer(Void).null
  @@seg_mode     = Pointer(Void).null
  @@app_ref      = Pointer(Void).null
  # Keep ObjC target object alive (strong ref) so GC and ARC don't drop it
  @@btn_target   = Pointer(Void).null

  def self.recording?   ; @@recording   end
  def self.recorder     ; @@recorder    end
  def self.start_time   ; @@start_time  end
  def self.out_path     ; @@out_path    end
  def self.btn_record   ; @@btn_record  end
  def self.lbl_status   ; @@lbl_status  end
  def self.lbl_timer    ; @@lbl_timer   end
  def self.lbl_path     ; @@lbl_path    end
  def self.seg_mode     ; @@seg_mode    end
  def self.app_ref      ; @@app_ref     end
  def self.btn_target   ; @@btn_target  end

  def self.recording=(v)   ; @@recording   = v end
  def self.recorder=(v)    ; @@recorder    = v end
  def self.start_time=(v)  ; @@start_time  = v end
  def self.out_path=(v)    ; @@out_path    = v end
  def self.btn_record=(v)  ; @@btn_record  = v end
  def self.lbl_status=(v)  ; @@lbl_status  = v end
  def self.lbl_timer=(v)   ; @@lbl_timer   = v end
  def self.lbl_path=(v)    ; @@lbl_path    = v end
  def self.seg_mode=(v)    ; @@seg_mode    = v end
  def self.app_ref=(v)     ; @@app_ref     = v end
  def self.btn_target=(v)  ; @@btn_target  = v end
end

# ── UI helpers ────────────────────────────────────────────────────────────────

def set_label(lbl : Void*, text : String)
  LibAppKitHelpers.ca_nslabel_set_text(lbl, text.to_unsafe)
end

def set_button_title(btn : Void*, title : String)
  LibAppKitHelpers.ca_nsbutton_set_title(btn, title.to_unsafe)
end

def format_elapsed(secs : Int32) : String
  m = secs // 60
  s = secs % 60
  "#{m}:#{s.to_s.rjust(2, '0')}"
end

def make_label(x : Float64, y : Float64, w : Float64, h : Float64,
               text : String, font_size : Float64 = 13.0,
               bold : Bool = false, center : Bool = false) : Void*
  lbl = LibAppKitHelpers.ca_nslabel_create(x, y, w, h)
  LibAppKitHelpers.ca_nslabel_set_text(lbl, text.to_unsafe)
  font = bold ? LibAppKitHelpers.ca_nsfont_bold(font_size) :
                LibAppKitHelpers.ca_nsfont_system(font_size)
  LibAppKitHelpers.ca_nslabel_set_font(lbl, font)
  LibAppKitHelpers.ca_nslabel_set_alignment(lbl, 2_i64) if center  # NSTextAlignmentCenter
  lbl
end

# ── Recording logic ───────────────────────────────────────────────────────────

def start_recording
  return if AppState.recording?

  mode_idx = LibAppKitHelpers.ca_nssegmented_selected(AppState.seg_mode)
  source = case mode_idx
           when 0 then CrystalAudio::RecordingSource::Microphone
           when 1 then CrystalAudio::RecordingSource::System
           else        CrystalAudio::RecordingSource::Both
           end

  ts = Time.local.to_s("%Y%m%d_%H%M%S")
  AppState.out_path = "/tmp/crystal_audio_#{ts}.wav"

  rec = CrystalAudio::Recorder.new(
    source: source,
    output_path: AppState.out_path
  )

  begin
    rec.start
  rescue ex
    set_label(AppState.lbl_status, "Error: #{ex.message}")
    return
  end

  AppState.recorder = rec
  AppState.recording = true
  AppState.start_time = Time.local

  set_button_title(AppState.btn_record, "Stop")
  set_label(AppState.lbl_status, "Recording...")
  set_label(AppState.lbl_path, AppState.out_path)
  set_label(AppState.lbl_timer, "0:00")
end

def stop_recording
  return unless AppState.recording?

  AppState.recording = false

  AppState.recorder.try do |rec|
    begin
      rec.stop
    rescue
    end
  end
  AppState.recorder = nil

  if t = AppState.start_time
    elapsed = (Time.local - t).total_seconds.to_i
    set_label(AppState.lbl_timer, format_elapsed(elapsed) + " (done)")
  end

  set_button_title(AppState.btn_record, "Record")
  set_label(AppState.lbl_status, "Saved to #{AppState.out_path}")
  AppState.start_time = nil
end

# ── Button callback — C-callable, no closures ─────────────────────────────────
#
# This proc has no captured variables and is passed as a plain C function
# pointer to ca_button_target_create. All state access is via AppState module.

RECORD_BUTTON_CB = Proc(Void).new do
  if AppState.recording?
    stop_recording
  else
    start_recording
  end
end

# ── Main ──────────────────────────────────────────────────────────────────────

app = LibAppKitHelpers.ca_nsapp
AppState.app_ref = app

# NSApplicationActivationPolicyRegular = 0
LibAppKitHelpers.ca_nsapp_set_policy(app, 0_i64)
LibAppKitHelpers.ca_nsapp_activate(app)

# ── Build window ──────────────────────────────────────────────────────────────

WIN_W = 400.0
WIN_H = 320.0

# NSWindowStyleMask: Titled(1) | Closable(2) | Miniaturizable(4) | Resizable(8) = 15
win = LibAppKitHelpers.ca_nswindow_create(0.0, 0.0, WIN_W, WIN_H, 15_u64)
LibAppKitHelpers.ca_nswindow_set_title(win, "Crystal Audio Recorder")
LibAppKitHelpers.ca_nswindow_center(win)

content = LibAppKitHelpers.ca_nswindow_content_view(win)

# ── Mode label (top) ─────────────────────────────────────────────────────────
mode_hdr = make_label(20.0, WIN_H - 30.0, WIN_W - 40.0, 20.0,
                       "Recording Mode", bold: true)
LibAppKitHelpers.ca_view_add_subview(content, mode_hdr)

# ── Segmented control ─────────────────────────────────────────────────────────
seg_y = WIN_H - 62.0

seg_label0 = "Microphone"
seg_label1 = "System Audio"
seg_label2 = "Both"
seg_cptrs = StaticArray(Pointer(UInt8), 3).new(Pointer(UInt8).null)
seg_cptrs[0] = seg_label0.to_unsafe
seg_cptrs[1] = seg_label1.to_unsafe
seg_cptrs[2] = seg_label2.to_unsafe

seg = LibAppKitHelpers.ca_nssegmented_create(
  20.0, seg_y, WIN_W - 40.0, 30.0,
  seg_cptrs.to_unsafe.as(Void**), 3_i32
)
AppState.seg_mode = seg
LibAppKitHelpers.ca_view_add_subview(content, seg)

# ── Record/Stop button ────────────────────────────────────────────────────────
btn_y = WIN_H - 140.0
btn = LibAppKitHelpers.ca_nsbutton_create(
  WIN_W / 2.0 - 80.0, btn_y, 160.0, 44.0, "Record"
)
AppState.btn_record = btn

# Create C-side ObjC action target; pass our Crystal proc as a C function pointer.
# The proc must not capture any variables — it accesses state via AppState module.
btn_target = LibAppKitHelpers.ca_button_target_create(
  RECORD_BUTTON_CB.pointer.as(Void*)
)
# Store in AppState to prevent GC collection
AppState.btn_target = btn_target
# Wire the button to the C-created target
LibAppKitHelpers.ca_button_set_action(btn, btn_target)

LibAppKitHelpers.ca_view_add_subview(content, btn)

# ── Timer label (large, centered) ─────────────────────────────────────────────
timer_y = btn_y - 54.0
timer_lbl = make_label(20.0, timer_y, WIN_W - 40.0, 38.0,
                        "0:00", font_size: 30.0, bold: true, center: true)
AppState.lbl_timer = timer_lbl
LibAppKitHelpers.ca_view_add_subview(content, timer_lbl)

# ── Status label ──────────────────────────────────────────────────────────────
status_y = timer_y - 32.0
status_lbl = make_label(20.0, status_y, WIN_W - 40.0, 22.0,
                         "Ready", center: true)
AppState.lbl_status = status_lbl
LibAppKitHelpers.ca_view_add_subview(content, status_lbl)

# ── Output path label ─────────────────────────────────────────────────────────
path_y = status_y - 28.0
path_lbl = make_label(20.0, path_y, WIN_W - 40.0, 20.0,
                       "Output: /tmp/crystal_audio_<timestamp>.wav",
                       font_size: 10.0, center: true)
AppState.lbl_path = path_lbl
LibAppKitHelpers.ca_view_add_subview(content, path_lbl)

# ── Credit label (bottom) ─────────────────────────────────────────────────────
credit_lbl = make_label(20.0, 6.0, WIN_W - 40.0, 14.0,
                         "crystal-audio · github.com/crimson-knight/crystal-audio",
                         font_size: 9.0, center: true)
LibAppKitHelpers.ca_view_add_subview(content, credit_lbl)

# ── Show window and enter pump-based event loop ────────────────────────────
LibAppKitHelpers.ca_observe_window_close(win)
LibAppKitHelpers.ca_nswindow_show(win)

loop do
  LibAppKitHelpers.ca_nsapp_pump_events(app)
  if AppState.recording? && (t = AppState.start_time)
    elapsed = (Time.local - t).total_seconds.to_i
    set_label(AppState.lbl_timer, format_elapsed(elapsed))
  end
  break if LibAppKitHelpers.ca_window_should_close
  sleep 50.milliseconds
end
