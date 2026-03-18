import Foundation
import AVFoundation
import Accelerate
import Combine

// MARK: - PitchDetector

/// Real-time pitch detection using an autocorrelation / YIN-inspired algorithm.
/// Runs on a background thread and publishes results to the main thread.
@MainActor
final class PitchDetector: ObservableObject {

    // MARK: - Published Properties

    @Published var currentPitch: Float = 0.0     // Hz
    @Published var currentMIDINote: Int = 0
    @Published var confidence: Float = 0.0       // 0–1
    @Published var noteName: String = "--"
    @Published var centsDeviation: Float = 0.0   // -50 to +50 cents

    // MARK: - Private

    private let engine = AVAudioEngine()
    private var isRunning = false

    // Analysis parameters
    private let sampleRate: Float = 44100.0
    private let bufferSize: AVAudioFrameCount = 4096
    private let minFrequency: Float = 60.0    // B1 – below bass clef range
    private let maxFrequency: Float = 1800.0  // ~ A#6

    // Smoothing history for pitch stability
    private var pitchHistory: [Float] = []
    private let historyLength = 5

    // Background processing queue
    private let processingQueue = DispatchQueue(label: "com.vocalscorepro.pitchdetector", qos: .userInteractive)

    // MARK: - Public API

    func startDetection() {
        guard !isRunning else { return }

        // Step 1 — configure AVAudioSession for recording FIRST
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[PitchDetector] Failed to configure audio session: \(error)")
            return
        }

        // Step 2 — get the hardware native format (after session is active)
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Step 3 — install tap using hardware format
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.analyzeBuffer(buffer)
        }

        // Step 4 — start engine
        do {
            try engine.start()
            isRunning = true
        } catch {
            print("[PitchDetector] Failed to start engine: \(error)")
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    func stopDetection() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        currentPitch = 0
        currentMIDINote = 0
        confidence = 0
        noteName = "--"
        centsDeviation = 0
    }

    // MARK: - Pitch Analysis

    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.detectPitch(samples: samples)

            Task { @MainActor in
                self.updatePublishedValues(result)
            }
        }
    }

    private func detectPitch(samples: [Float]) -> PitchResult {
        let n = samples.count

        // Step 1: Check RMS level — don't detect pitch in silence
        var rms: Float = 0.0
        vDSP_measqv(samples, 1, &rms, vDSP_Length(n))
        rms = sqrt(rms)

        guard rms > 0.01 else {
            return PitchResult(frequency: 0, confidence: 0)
        }

        // Step 2: YIN algorithm — difference function
        let minLag = Int(sampleRate / maxFrequency)
        let maxLag = Int(sampleRate / minFrequency)
        let yinSize = min(maxLag + 1, n / 2)

        var yinBuffer = [Float](repeating: 0.0, count: yinSize)

        // Difference function d(τ)
        for tau in 1..<yinSize {
            var sum: Float = 0.0
            for j in 0..<(yinSize - tau) {
                let diff = samples[j] - samples[j + tau]
                sum += diff * diff
            }
            yinBuffer[tau] = sum
        }

        // Cumulative mean normalized difference
        yinBuffer[0] = 1.0
        var runningSum: Float = 0.0
        for tau in 1..<yinSize {
            runningSum += yinBuffer[tau]
            yinBuffer[tau] = runningSum > 0 ? yinBuffer[tau] * Float(tau) / runningSum : 1.0
        }

        // Find first minimum below threshold
        let threshold: Float = 0.15
        var tauEstimate = -1

        for tau in minLag..<yinSize {
            if yinBuffer[tau] < threshold {
                while tau + 1 < yinSize && yinBuffer[tau + 1] < yinBuffer[tau] {
                    break  // simplified — take first crossing
                }
                tauEstimate = tau
                break
            }
        }

        if tauEstimate <= 0 {
            // Fall back to global minimum if no threshold crossing found
            var minVal: Float = Float.infinity
            var minIdx = minLag
            for tau in minLag..<yinSize {
                if yinBuffer[tau] < minVal {
                    minVal = yinBuffer[tau]
                    minIdx = tau
                }
            }
            if minVal < 0.5 {
                tauEstimate = minIdx
            } else {
                return PitchResult(frequency: 0, confidence: 0)
            }
        }

        // Step 3: Parabolic interpolation for sub-sample accuracy
        let refinedTau: Float
        if tauEstimate > 0 && tauEstimate < yinSize - 1 {
            let s0 = yinBuffer[tauEstimate - 1]
            let s1 = yinBuffer[tauEstimate]
            let s2 = yinBuffer[tauEstimate + 1]
            let denominator = s0 - 2.0 * s1 + s2
            if abs(denominator) > 1e-6 {
                let adjustment = 0.5 * (s0 - s2) / denominator
                refinedTau = Float(tauEstimate) + adjustment
            } else {
                refinedTau = Float(tauEstimate)
            }
        } else {
            refinedTau = Float(tauEstimate)
        }

        guard refinedTau > 0 else { return PitchResult(frequency: 0, confidence: 0) }

        let frequency = sampleRate / refinedTau
        let conf = max(0, min(1, 1.0 - yinBuffer[tauEstimate]))

        return PitchResult(frequency: frequency, confidence: conf)
    }

    private func updatePublishedValues(_ result: PitchResult) {
        guard result.confidence > 0.3 && result.frequency > 0 else {
            // Fade out confidence
            confidence = max(0, confidence - 0.1)
            if confidence == 0 {
                currentPitch = 0
                currentMIDINote = 0
                noteName = "--"
                centsDeviation = 0
            }
            return
        }

        // Smooth pitch using history
        pitchHistory.append(result.frequency)
        if pitchHistory.count > historyLength {
            pitchHistory.removeFirst()
        }

        let smoothedFreq = pitchHistory.reduce(0, +) / Float(pitchHistory.count)

        let (midi, cents) = frequencyToMIDI(smoothedFreq)

        currentPitch = smoothedFreq
        currentMIDINote = midi
        confidence = result.confidence
        noteName = midiNoteToName(midi)
        centsDeviation = cents
    }

    // MARK: - Conversion Helpers

    /// Converts Hz to MIDI note number and cents deviation.
    func hzToMIDI(_ hz: Float) -> (note: Int, confidence: Float) {
        guard hz > 0 else { return (0, 0) }
        let midi = 12.0 * log2(hz / 440.0) + 69.0
        return (Int(midi.rounded()), 1.0)
    }

    /// Returns the MIDI note number and cents deviation from equal temperament.
    private func frequencyToMIDI(_ hz: Float) -> (note: Int, cents: Float) {
        guard hz > 0 else { return (0, 0) }
        let midiFloat = 12.0 * log2f(hz / 440.0) + 69.0
        let midiNote = Int(midiFloat.rounded())
        let cents = (midiFloat - Float(midiNote)) * 100.0
        return (max(0, min(127, midiNote)), cents)
    }

    /// Converts a MIDI note number to a human-readable name such as "C4" or "F#5".
    func midiNoteToName(_ midi: Int) -> String {
        Note.midiNoteToName(midi)
    }
}

// MARK: - PitchResult

private struct PitchResult {
    let frequency: Float
    let confidence: Float
}
