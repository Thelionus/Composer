import Foundation

// MARK: - PitchEvent

/// A raw detected pitch event from the recording pipeline.
struct PitchEvent {
    let pitch: Int                  // MIDI note number (-1 for rest)
    let timestamp: TimeInterval     // Absolute time in seconds from recording start
    let duration: TimeInterval      // Duration in seconds
    let confidence: Float           // Pitch confidence 0–1
    let velocity: Int               // Estimated velocity 0–127
}

// MARK: - QuantizationGrid

/// The minimum time resolution for rhythm quantization.
enum QuantizationGrid: String, CaseIterable, Identifiable {
    case quarter         = "1/4"
    case eighth          = "1/8"
    case sixteenth       = "1/16"
    case thirtySecond    = "1/32"
    case tripletEighth   = "1/8T"
    case tripletSixteenth = "1/16T"

    var id: String { rawValue }

    /// Grid step duration in beats (quarter note = 1.0).
    func gridBeats(for grid: QuantizationGrid) -> Double { beats }

    var beats: Double {
        switch self {
        case .quarter:          return 1.0
        case .eighth:           return 0.5
        case .sixteenth:        return 0.25
        case .thirtySecond:     return 0.125
        case .tripletEighth:    return 1.0 / 3.0
        case .tripletSixteenth: return 1.0 / 6.0
        }
    }

    var displayName: String { rawValue }
}

// MARK: - RhythmQuantizer

/// Converts raw pitch events (with timestamps and durations) into quantized
/// Note objects aligned to a musical grid given a tempo and time signature.
struct RhythmQuantizer {

    // MARK: - Public API

    /// Quantize pitch events to a rhythmic grid.
    ///
    /// - Parameters:
    ///   - events: Raw pitch events from PitchDetector.
    ///   - tempo: Tempo in BPM.
    ///   - grid: The minimum rhythmic subdivision.
    ///   - timeSignatureNumerator: Beats per bar.
    ///   - timeSignatureDenominator: Note value per beat (4 = quarter).
    /// - Returns: An array of quantized Note objects ready for insertion into a Part.
    func quantize(
        events: [PitchEvent],
        tempo: Double,
        grid: QuantizationGrid,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4
    ) -> [Note] {
        guard !events.isEmpty, tempo > 0 else { return [] }

        let secondsPerBeat = 60.0 / tempo
        let gridBeats = grid.beats
        let gridSeconds = gridBeats * secondsPerBeat

        var notes: [Note] = []

        for event in events {
            // Skip very short events (likely noise or detection artifacts)
            guard event.duration >= gridSeconds * 0.3 else { continue }

            // Quantize start time
            let startBeatRaw = event.timestamp / secondsPerBeat + 1.0 // 1-indexed
            let quantizedStart = round(startBeatRaw / gridBeats) * gridBeats

            // Quantize duration
            let durationBeatsRaw = event.duration / secondsPerBeat
            let quantizedDurationBeats = max(gridBeats, round(durationBeatsRaw / gridBeats) * gridBeats)

            // Find the best matching NoteDuration
            let duration = NoteDuration.nearest(beats: quantizedDurationBeats)

            // Flag low-confidence detections
            let isFlagged = event.confidence < 0.5
            let flagReason: String? = isFlagged ? "Low pitch detection confidence (\(Int(event.confidence * 100))%)" : nil

            let note = Note(
                pitch: event.pitch,
                duration: duration,
                startBeat: quantizedStart,
                velocity: event.velocity,
                articulation: .normal,
                dynamic: dynamicFromVelocity(event.velocity),
                isTied: false,
                isGraceNote: false,
                confidence: event.confidence,
                isFlagged: isFlagged,
                flagReason: flagReason
            )
            notes.append(note)
        }

        // Merge overlapping notes of the same pitch (legato)
        let merged = mergeOverlappingNotes(notes)

        // Fill gaps with rests if needed
        return insertRests(in: merged, grid: gridBeats)
    }

    /// Build a set of pitch events from raw pitch samples over time.
    ///
    /// - Parameters:
    ///   - pitchSamples: Array of (time, pitch, confidence) tuples sampled at regular intervals.
    ///   - sampleInterval: Time between samples in seconds.
    ///   - velocitySamples: Optional parallel array of velocity values.
    func buildEvents(
        fromPitchSamples pitchSamples: [(time: TimeInterval, pitch: Int, confidence: Float)],
        sampleInterval: TimeInterval,
        velocitySamples: [Int]? = nil
    ) -> [PitchEvent] {
        guard !pitchSamples.isEmpty else { return [] }

        var events: [PitchEvent] = []
        var i = 0

        while i < pitchSamples.count {
            let sample = pitchSamples[i]
            let startPitch = sample.pitch
            let startTime = sample.time

            // Find how long this pitch continues
            var j = i + 1
            while j < pitchSamples.count &&
                  abs(pitchSamples[j].pitch - startPitch) <= 1 && // allow ±1 semitone variation
                  pitchSamples[j].confidence > 0.3 {
                j += 1
            }

            let endTime = j < pitchSamples.count ? pitchSamples[j].time : sample.time + sampleInterval
            let duration = endTime - startTime

            // Average confidence over the note's duration
            let sliceSamples = Array(pitchSamples[i..<j])
            let avgConfidence = sliceSamples.isEmpty ? sample.confidence :
                sliceSamples.reduce(0) { $0 + $1.confidence } / Float(sliceSamples.count)

            let velocity: Int
            if let vels = velocitySamples, i < vels.count {
                velocity = vels[i]
            } else {
                velocity = 80
            }

            events.append(PitchEvent(
                pitch: startPitch,
                timestamp: startTime,
                duration: duration,
                confidence: avgConfidence,
                velocity: velocity
            ))

            i = j
        }

        return events
    }

    // MARK: - Private Helpers

    private func mergeOverlappingNotes(_ notes: [Note]) -> [Note] {
        guard notes.count > 1 else { return notes }

        var result: [Note] = []
        var current = notes[0]

        for next in notes.dropFirst() {
            // If same pitch and notes are adjacent (within 10% of a beat), merge
            let gap = next.startBeat - current.endBeat
            if next.pitch == current.pitch && abs(gap) < 0.1 {
                let combinedBeats = current.duration.beats + next.duration.beats
                var merged = current
                merged.duration = NoteDuration.nearest(beats: combinedBeats)
                merged.isTied = false
                current = merged
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    private func insertRests(in notes: [Note], grid: Double) -> [Note] {
        guard notes.count > 1 else { return notes }

        var result: [Note] = []
        var prevEnd = 1.0 // piece starts at beat 1

        for note in notes {
            let gap = note.startBeat - prevEnd
            if gap >= grid * 0.8 { // Insert rest if gap is significant
                let restDuration = NoteDuration.nearest(beats: gap)
                let rest = Note(
                    pitch: -1, // -1 = rest
                    duration: restDuration,
                    startBeat: prevEnd,
                    velocity: 0,
                    articulation: .normal,
                    dynamic: .mp,
                    confidence: 1.0
                )
                result.append(rest)
            }
            result.append(note)
            prevEnd = note.endBeat
        }

        return result
    }

    private func dynamicFromVelocity(_ velocity: Int) -> Dynamic {
        switch velocity {
        case 0..<20:   return .ppp
        case 20..<40:  return .pp
        case 40..<55:  return .p
        case 55..<70:  return .mp
        case 70..<85:  return .mf
        case 85..<100: return .f
        case 100..<115: return .ff
        default:        return .fff
        }
    }
}

// MARK: - Demo / Testing Helpers

extension RhythmQuantizer {
    /// Generates a simple C major scale as test pitch events.
    static func testEvents(tempo: Double = 120) -> [PitchEvent] {
        let secondsPerBeat = 60.0 / tempo
        let scale = [60, 62, 64, 65, 67, 69, 71, 72] // C4 to C5
        return scale.enumerated().map { (i, pitch) in
            PitchEvent(
                pitch: pitch,
                timestamp: Double(i) * secondsPerBeat,
                duration: secondsPerBeat * 0.9,
                confidence: 0.9,
                velocity: 80
            )
        }
    }
}
