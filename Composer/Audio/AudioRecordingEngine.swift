import Foundation
import AVFoundation
import Combine

// MARK: - AudioRecordingEngine

/// Manages AVAudioEngine-based audio recording with real-time metering,
/// silence detection, and multi-take management.
@MainActor
final class AudioRecordingEngine: ObservableObject {

    // MARK: - Published Properties

    @Published var isRecording: Bool = false
    @Published var inputLevel: Float = -160.0        // dBFS
    @Published var normalizedLevel: Float = 0.0      // 0–1
    @Published var silenceDetected: Bool = false
    @Published var takes: [URL] = []
    @Published var selectedTakeIndex: Int = 0
    @Published var recordingError: AudioRecordingError?

    // MARK: - Private State

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentTakeURL: URL?
    private var sampleBuffer: [Float] = []
    private let sampleBufferSize = 1024 * 8

    // Silence detection
    private var silenceSamples: Int = 0
    private let silenceThresholdDB: Float = -50.0
    private let silenceMinSamples: Int = 44100 // ~1 second at 44.1 kHz

    // Noise gate
    private let noiseGateThresholdDB: Float = -45.0

    // Loop recording
    private(set) var isLoopMode: Bool = false
    private var loopDuration: TimeInterval = 4.0

    // Level smoothing
    private var smoothedLevel: Float = -160.0
    private let smoothingFactor: Float = 0.3

    // Document directory for storing takes
    private var recordingsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    // MARK: - Initializer

    init() {
        createRecordingsDirectory()
    }

    // MARK: - Public API

    /// Configures AVAudioSession and begins recording to a new file.
    func startRecording() async throws {
        guard !isRecording else { return }

        do {
            try configureAudioSession()
        } catch {
            recordingError = .sessionConfigurationFailed(error.localizedDescription)
            throw error
        }

        let url = newTakeURL()
        currentTakeURL = url

        let format = engine.inputNode.outputFormat(forBus: 0)

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            recordingError = .fileCreationFailed(error.localizedDescription)
            throw error
        }

        // Install tap on input bus for capturing and metering
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.processBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            recordingError = .engineStartFailed(error.localizedDescription)
            throw error
        }

        isRecording = true
        silenceSamples = 0
        sampleBuffer.removeAll(keepingCapacity: true)
    }

    /// Stops recording and returns the URL of the recorded take.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Non-fatal
        }

        isRecording = false
        inputLevel = -160.0
        normalizedLevel = 0.0
        silenceDetected = false

        guard let url = currentTakeURL else { return nil }

        // Only keep the take if the file has audio content
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           fileSize > 4096 {
            takes.append(url)
            selectedTakeIndex = takes.count - 1
            audioFile = nil
            currentTakeURL = nil
            return url
        } else {
            // Empty take — remove file
            try? FileManager.default.removeItem(at: url)
            audioFile = nil
            currentTakeURL = nil
            return nil
        }
    }

    /// Delete a specific take by index.
    func deleteTake(at index: Int) {
        guard index < takes.count else { return }
        let url = takes[index]
        try? FileManager.default.removeItem(at: url)
        takes.remove(at: index)
        if selectedTakeIndex >= takes.count {
            selectedTakeIndex = max(0, takes.count - 1)
        }
    }

    /// Clear all takes for the current session.
    func clearAllTakes() {
        for url in takes {
            try? FileManager.default.removeItem(at: url)
        }
        takes.removeAll()
        selectedTakeIndex = 0
    }

    /// Enable or disable loop recording mode.
    func setLoopMode(_ enabled: Bool, loopDuration: TimeInterval = 4.0) {
        isLoopMode = enabled
        self.loopDuration = loopDuration
    }

    /// The sample buffer for waveform display (recent audio data).
    var waveformSamples: [Float] {
        Array(sampleBuffer.suffix(512))
    }

    // MARK: - Private Helpers

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Write to file
        do {
            try audioFile?.write(from: buffer)
        } catch {
            // Non-fatal write error
        }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Calculate RMS level
        var rms: Float = 0.0
        for i in 0..<frameCount {
            rms += channelData[i] * channelData[i]
        }
        rms = sqrt(rms / Float(frameCount))

        // Convert to dBFS
        let db = rms > 0 ? 20.0 * log10(rms) : -160.0

        // Smooth the level
        smoothedLevel = smoothingFactor * db + (1.0 - smoothingFactor) * smoothedLevel

        // Collect samples for waveform display
        let stride = max(1, frameCount / 64)
        for i in Swift.stride(from: 0, to: frameCount, by: stride) {
            sampleBuffer.append(channelData[i])
        }
        if sampleBuffer.count > sampleBufferSize {
            sampleBuffer.removeFirst(sampleBuffer.count - sampleBufferSize)
        }

        // Silence detection
        if smoothedLevel < silenceThresholdDB {
            silenceSamples += frameCount
        } else {
            silenceSamples = 0
        }

        // Update published properties on main thread
        let levelDB = smoothedLevel
        let normalized = max(0, min(1, (levelDB + 60.0) / 60.0))
        let isSilent = silenceSamples > silenceMinSamples

        Task { @MainActor [weak self] in
            self?.inputLevel = levelDB
            self?.normalizedLevel = normalized
            self?.silenceDetected = isSilent
        }
    }

    private func newTakeURL() -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        return recordingsDirectory.appendingPathComponent("take_\(timestamp).caf")
    }

    private func createRecordingsDirectory() {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: recordingsDirectory.path, isDirectory: &isDir)
        if !exists || !isDir.boolValue {
            try? FileManager.default.createDirectory(at: recordingsDirectory,
                                                     withIntermediateDirectories: true)
        }
    }
}

// MARK: - AudioRecordingError

enum AudioRecordingError: LocalizedError, Equatable {
    case sessionConfigurationFailed(String)
    case fileCreationFailed(String)
    case engineStartFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .sessionConfigurationFailed(let msg): return "Session error: \(msg)"
        case .fileCreationFailed(let msg):         return "File error: \(msg)"
        case .engineStartFailed(let msg):          return "Engine error: \(msg)"
        case .permissionDenied:                    return "Microphone permission denied."
        }
    }
}
