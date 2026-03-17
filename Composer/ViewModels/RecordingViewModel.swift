import Foundation
import Combine
import SwiftUI

// MARK: - RecordingState

enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case reviewing
    case complete
    case error(String)

    var displayName: String {
        switch self {
        case .idle:        return "Ready"
        case .recording:   return "Recording..."
        case .processing:  return "Processing..."
        case .reviewing:   return "Review Take"
        case .complete:    return "Complete"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isRecording: Bool { self == .recording }
    var isProcessing: Bool { self == .processing }
    var canRecord: Bool { self == .idle || self == .reviewing }
    var canAccept: Bool { self == .reviewing }
}

// MARK: - RecordingViewModel

@MainActor
final class RecordingViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var state: RecordingState = .idle
    @Published var detectedNotes: [Note] = []
    @Published var selectedInstrument: Instrument = Instrument.defaultInstrument
    @Published var takes: [URL] = []
    @Published var selectedTake: Int = 0
    @Published var waveformSamples: [Float] = []
    @Published var quantizationGrid: QuantizationGrid = .eighth
    @Published var recordingError: String?

    // Pass-through from AudioRecordingEngine
    @Published var isRecordingActive: Bool = false
    @Published var inputLevel: Float = -160.0
    @Published var normalizedLevel: Float = 0.0
    @Published var silenceDetected: Bool = false

    // Pass-through from PitchDetector
    @Published var currentPitch: Float = 0.0
    @Published var currentMIDINote: Int = 0
    @Published var pitchConfidence: Float = 0.0
    @Published var currentNoteName: String = "--"
    @Published var centsDeviation: Float = 0.0

    // MARK: - Dependencies

    let audioEngine = AudioRecordingEngine()
    let pitchDetector = PitchDetector()
    private let rhythmQuantizer = RhythmQuantizer()
    private let playbackEngine = PlaybackEngine()

    // MARK: - Private State

    private var rawPitchSamples: [(time: TimeInterval, pitch: Int, confidence: Float)] = []
    private var recordingStartTime: Date?
    private var pitchSamplingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializer

    init() {
        bindPublishedValues()
    }

    private func bindPublishedValues() {
        audioEngine.$isRecording
            .receive(on: RunLoop.main)
            .assign(to: &$isRecordingActive)

        audioEngine.$inputLevel
            .receive(on: RunLoop.main)
            .assign(to: &$inputLevel)

        audioEngine.$normalizedLevel
            .receive(on: RunLoop.main)
            .assign(to: &$normalizedLevel)

        audioEngine.$silenceDetected
            .receive(on: RunLoop.main)
            .assign(to: &$silenceDetected)

        audioEngine.$takes
            .receive(on: RunLoop.main)
            .assign(to: &$takes)

        pitchDetector.$currentPitch
            .receive(on: RunLoop.main)
            .assign(to: &$currentPitch)

        pitchDetector.$currentMIDINote
            .receive(on: RunLoop.main)
            .assign(to: &$currentMIDINote)

        pitchDetector.$confidence
            .receive(on: RunLoop.main)
            .assign(to: &$pitchConfidence)

        pitchDetector.$noteName
            .receive(on: RunLoop.main)
            .assign(to: &$currentNoteName)

        pitchDetector.$centsDeviation
            .receive(on: RunLoop.main)
            .assign(to: &$centsDeviation)
    }

    // MARK: - Public API

    func startRecording() {
        guard state.canRecord else { return }

        state = .recording
        recordingError = nil
        rawPitchSamples.removeAll()
        recordingStartTime = Date()

        // Start pitch detector
        pitchDetector.startDetection()

        // Start recording engine
        Task {
            do {
                try await audioEngine.startRecording()
            } catch {
                state = .error(error.localizedDescription)
                recordingError = error.localizedDescription
                pitchDetector.stopDetection()
            }
        }

        // Start sampling pitch at ~20Hz
        startPitchSampling()
    }

    func stopRecording() {
        guard state == .recording else { return }

        pitchSamplingTask?.cancel()
        pitchSamplingTask = nil
        pitchDetector.stopDetection()

        let _ = audioEngine.stopRecording()

        state = .processing

        Task {
            await processRecording()
        }
    }

    func processRecording() async {
        state = .processing

        // Simulate minimum processing time for UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        guard !rawPitchSamples.isEmpty else {
            detectedNotes = []
            state = .reviewing
            return
        }

        // Build pitch events from sampled data
        let events = rhythmQuantizer.buildEvents(
            fromPitchSamples: rawPitchSamples,
            sampleInterval: 0.05 // 20Hz sampling
        )

        // Quantize to musical grid
        let quantized = rhythmQuantizer.quantize(
            events: events,
            tempo: 120.0, // Will be set from project
            grid: quantizationGrid
        )

        detectedNotes = quantized
        state = .reviewing
    }

    /// Accept the current take and build a Part from it.
    func acceptTake() -> Part {
        let url = takes.indices.contains(selectedTake) ? takes[selectedTake] : nil
        var part = Part(
            name: selectedInstrument.name,
            instrument: selectedInstrument,
            notes: detectedNotes,
            recordingURL: url
        )
        // Validate note ranges
        part.validateNoteRanges()
        state = .complete
        return part
    }

    /// Discard the current take and return to idle.
    func discardTake() {
        if takes.indices.contains(selectedTake) {
            audioEngine.deleteTake(at: selectedTake)
        }
        detectedNotes = []
        state = .idle
    }

    /// Discard everything and re-record.
    func reRecord() {
        audioEngine.clearAllTakes()
        detectedNotes = []
        rawPitchSamples = []
        state = .idle
        startRecording()
    }

    func reset() {
        pitchSamplingTask?.cancel()
        pitchDetector.stopDetection()
        _ = audioEngine.stopRecording()
        audioEngine.clearAllTakes()
        detectedNotes = []
        rawPitchSamples = []
        state = .idle
    }

    /// Audition the current detected notes through the playback engine.
    func auditNotes(tempo: Double = 120) {
        playbackEngine.play(notes: detectedNotes, instrument: selectedInstrument, tempo: tempo)
    }

    func stopAudit() {
        playbackEngine.stop()
    }

    // MARK: - Pitch Sampling

    private func startPitchSampling() {
        pitchSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                let elapsed = self.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
                let pitch = await self.pitchDetector.currentMIDINote
                let confidence = await self.pitchDetector.confidence

                if confidence > 0.3 && pitch > 0 {
                    self.rawPitchSamples.append((time: elapsed, pitch: pitch, confidence: confidence))
                }

                // Sample waveform for display
                let samples = self.audioEngine.waveformSamples
                if !samples.isEmpty {
                    self.waveformSamples = samples
                }

                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms = 20Hz
            }
        }
    }

    // MARK: - Take Management

    func selectTake(_ index: Int) {
        guard index < takes.count else { return }
        selectedTake = index
    }

    func deleteCurrentTake() {
        audioEngine.deleteTake(at: selectedTake)
        if takes.isEmpty {
            state = .idle
        }
    }

    // MARK: - Computed Properties

    var canStopRecording: Bool { state == .recording }
    var isProcessingOrReviewing: Bool { state == .processing || state == .reviewing }

    var statusColor: Color {
        switch state {
        case .idle:       return .secondary
        case .recording:  return .red
        case .processing: return .orange
        case .reviewing:  return .blue
        case .complete:   return .green
        case .error:      return .red
        }
    }
}
