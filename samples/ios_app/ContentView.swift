import SwiftUI
import AVFoundation

// MARK: - Root view

struct ContentView: View {
    @StateObject private var model = AudioRecorderModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                headerSection
                timerSection
                recordButton
                statusSection
                Spacer()
                recordingListSection
            }
            .padding()
            .navigationTitle("Crystal Audio")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            model.initCrystalRuntime()
            // Auto-test: if CRYSTAL_AUTO_TEST env is set, start recording after permission is confirmed
            let autoTest = ProcessInfo.processInfo.environment["CRYSTAL_AUTO_TEST"] != nil
            model.requestPermission {
                if autoTest {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        model.toggleRecording()
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var headerSection: some View {
        VStack(spacing: 4) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("Microphone Recorder")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var timerSection: some View {
        Group {
            if model.isRecording {
                Text(model.elapsedTimeString)
                    .font(.system(size: 56, design: .monospaced))
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .scale))
            } else {
                Text("0:00")
                    .font(.system(size: 56, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isRecording)
    }

    private var recordButton: some View {
        Button(action: model.toggleRecording) {
            ZStack {
                Circle()
                    .fill(model.isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(model.isRecording ? .red : .blue)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(model.isRecording ? 1.08 : 1.0)
        .animation(.spring(duration: 0.25), value: model.isRecording)
        .disabled(!model.permissionGranted)
        .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")
    }

    private var statusSection: some View {
        VStack(spacing: 6) {
            Text(model.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !model.permissionGranted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)
            }
        }
    }

    private var recordingListSection: some View {
        Group {
            if !model.savedRecordings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved Recordings")
                        .font(.headline)
                        .padding(.bottom, 2)

                    ForEach(model.savedRecordings, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.blue)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - View model

@MainActor
final class AudioRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Ready to record"
    @Published var elapsedTimeString = "0:00"
    @Published var permissionGranted = false
    @Published var savedRecordings: [String] = []

    private var elapsedSeconds = 0
    private var timer: Timer?
    private var currentOutputPath = ""

    // MARK: - Lifecycle

    func initCrystalRuntime() {
        let result = crystal_audio_init()
        if result != 0 {
            statusText = "Crystal runtime init failed (\(result))"
        }
    }

    func requestPermission(completion: (() -> Void)? = nil) {
        let session = AVAudioSession.sharedInstance()
        // Check synchronously first — if already granted (e.g. via simctl privacy grant),
        // the async requestRecordPermission callback may never fire on simulator.
        if session.recordPermission == .granted {
            NSLog("CRYSTAL_SWIFT: permission already granted (sync check)")
            self.permissionGranted = true
            self.statusText = "Ready to record"
            completion?()
            return
        }

        NSLog("CRYSTAL_SWIFT: requesting permission async...")
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                NSLog("CRYSTAL_SWIFT: async permission callback: granted=\(granted)")
                self.permissionGranted = granted
                self.statusText = granted
                    ? "Ready to record"
                    : "Microphone access required — tap 'Open Settings'"
                completion?()
            }
        }
    }

    // MARK: - Recording control

    func toggleRecording() {
        NSLog("CRYSTAL_SWIFT: toggleRecording called, isRecording=\(isRecording), permissionGranted=\(permissionGranted)")
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard permissionGranted else {
            statusText = "Microphone permission not granted"
            return
        }

        // Build output path inside the app's Documents directory
        let timestamp = Int(Date().timeIntervalSince1970)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("recording_\(timestamp).wav")
        currentOutputPath = url.path

        // Configure AVAudioSession for recording
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            statusText = "Audio session error: \(error.localizedDescription)"
            return
        }

        // Call Crystal library
        NSLog("CRYSTAL_SWIFT: calling crystal_audio_start_mic with path: \(currentOutputPath)")
        let result = crystal_audio_start_mic(currentOutputPath)
        NSLog("CRYSTAL_SWIFT: crystal_audio_start_mic returned \(result)")
        guard result == 0 else {
            statusText = "Failed to start recording (error \(result))"
            return
        }

        isRecording = true
        elapsedSeconds = 0
        elapsedTimeString = "0:00"
        statusText = "Recording…"

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedSeconds += 1
                let m = self.elapsedSeconds / 60
                let s = self.elapsedSeconds % 60
                self.elapsedTimeString = String(format: "%d:%02d", m, s)
            }
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil

        let result = crystal_audio_stop()
        isRecording = false

        if result == 0 {
            statusText = "Saved: \(URL(fileURLWithPath: currentOutputPath).lastPathComponent)"
            savedRecordings.insert(currentOutputPath, at: 0)
        } else {
            statusText = "Stop failed (error \(result))"
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
